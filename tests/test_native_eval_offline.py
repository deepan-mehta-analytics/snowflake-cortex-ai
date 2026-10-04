"""Offline tests for native_eval.py helpers (no Snowflake connection)."""

# ── Imports ───────────────────────────────────────────────────
import os                                    # build import paths
import sys                                   # extend sys.path
from pathlib import Path                     # read the real template and dataset

import yaml                                  # parse the rendered config

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "eval"))  # make eval/ importable
from native_eval import dataset_name, load_golden, parse_results, render_config  # noqa: E402 — helpers under test

ROOT = Path(__file__).resolve().parent.parent                              # repo root
ROWS = load_golden(ROOT / "eval" / "golden_dataset.jsonl")                 # the real golden rows

# ── Dataset naming ────────────────────────────────────────────
def test_dataset_name_is_stable_and_shaped():
    """Same rows → same name; prefix + 8 hex characters."""
    assert dataset_name(ROWS) == dataset_name(ROWS)                        # deterministic
    assert dataset_name(ROWS).startswith("AP_GOLDEN_") and len(dataset_name(ROWS)) == 18  # prefix + 8 hex

def test_dataset_name_changes_when_ground_truth_changes():
    """Editing an answer key gives a new dataset name, so stale rows are never reused."""
    edited = [dict(r) for r in ROWS]                                       # copy rows
    edited[0]["ground_truth_output"] += " (edited)"                        # change one answer key
    assert dataset_name(edited) != dataset_name(ROWS)                      # new dataset name

def test_dataset_name_ignores_heuristic_fields():
    """Fields only the heuristic harness reads don't change the dataset name."""
    edited = [dict(r) for r in ROWS]                                       # copy rows
    edited[0]["check"] = "numeric_present"                                 # heuristic-only field
    assert dataset_name(edited) == dataset_name(ROWS)                      # not part of the evaluation dataset

# ── Config rendering ──────────────────────────────────────────
def test_render_config_fills_names():
    """The rendered template is valid YAML with the dataset and label filled in."""
    text = render_config((ROOT / "eval" / "agent_evaluation_config.yaml.tmpl").read_text(encoding="utf-8"),
                         "AP_GOLDEN_ABCDEF12", "COCO.EVAL.GOLDEN_QUESTIONS", "ci-1234abcd-1")
    config = yaml.safe_load(text)                                          # must stay valid YAML
    assert config["dataset"]["dataset_name"] == "AP_GOLDEN_ABCDEF12"       # dataset block
    assert config["dataset"]["table_name"] == "COCO.EVAL.GOLDEN_QUESTIONS"  # source table
    assert config["evaluation"]["source_metadata"]["dataset_name"] == "AP_GOLDEN_ABCDEF12"  # evaluation reads it
    assert config["evaluation"]["run_params"]["label"] == "ci-1234abcd-1"  # run label

def test_metrics_are_pinned_to_v3():
    """Both system metrics use judge version v3 (1M context) — v1 overflowed on our traces (Task 1)."""
    text = render_config((ROOT / "eval" / "agent_evaluation_config.yaml.tmpl").read_text(encoding="utf-8"),
                         "AP_GOLDEN_ABCDEF12", "COCO.EVAL.GOLDEN_QUESTIONS", "ci-1")
    metrics = {m["name"]: m["version"] for m in yaml.safe_load(text)["metrics"]}  # name → pinned version
    assert metrics == {"answer_correctness": "v3", "logical_consistency": "v3"}

def test_render_config_without_dataset_block():
    """Repeat runs on an existing dataset must omit the dataset: block (START fails with 'already exists')."""
    text = render_config((ROOT / "eval" / "agent_evaluation_config.yaml.tmpl").read_text(encoding="utf-8"),
                         "AP_GOLDEN_ABCDEF12", "COCO.EVAL.GOLDEN_QUESTIONS", "ci-1", include_dataset=False)
    config = yaml.safe_load(text)                                          # still valid YAML
    assert "dataset" not in config                                         # no dataset creation
    assert config["evaluation"]["source_metadata"]["dataset_name"] == "AP_GOLDEN_ABCDEF12"  # still points at it

# ── Result parsing ────────────────────────────────────────────
IDS = {"Which source system has the most invoices?": "q03", "Give me the invoice breakdown by system": "q09"}  # question → id

OK_STATUS = '{\n  "code": 200,\n  "message": "Ok"\n}'                    # METRIC_STATUS of a scored row (seen live)

def row(question, metric, score, error=None, status=OK_STATUS):
    """One GET_AI_EVALUATION_DATA row (only the columns the parser reads)."""
    return {"INPUT": question, "METRIC_NAME": metric, "EVAL_AGG_SCORE": score, "ERROR": error, "METRIC_STATUS": status}

def test_judge_failure_status_is_an_error_not_a_score():
    """A non-200 METRIC_STATUS (e.g. judge context overflow, seen live) is reported as an error and scores 0."""
    bad = '{\n  "code": 400,\n  "message": "LLM judge computation/processing hit context window limit"\n}'  # live text
    scores, errors = parse_results([row("Which source system has the most invoices?", "answer_correctness", 0.0, status=bad),
                                    row("Which source system has the most invoices?", "logical_consistency", 1.0)], IDS)
    assert scores["q03"] == {"answer_correctness": 0.0, "logical_consistency": 1.0}  # failed metric counts as 0
    assert "context window" in errors["q03"]                               # the judge's reason reaches the summary

def test_parse_results_groups_by_question_and_metric():
    """Rows become {qid: {metric: score}} with no errors."""
    scores, errors = parse_results([row(q, m, 1.0) for q in IDS for m in ("answer_correctness", "logical_consistency")], IDS)
    assert scores == {"q03": {"answer_correctness": 1.0, "logical_consistency": 1.0},
                      "q09": {"answer_correctness": 1.0, "logical_consistency": 1.0}}
    assert errors == {}                                                    # nothing errored

def test_errored_record_scores_zero_and_is_reported():
    """An errored record counts as 0.0 (never dropped) and its reason is kept."""
    rows = [row("Which source system has the most invoices?", "answer_correctness", None, "agent timeout"),
            row("Which source system has the most invoices?", "logical_consistency", None, "agent timeout")]
    scores, errors = parse_results(rows, IDS)                              # parse the errored rows
    assert scores["q03"] == {"answer_correctness": 0.0, "logical_consistency": 0.0}  # counted, not dropped
    assert "agent timeout" in errors["q03"]                                # reason kept for the summary

def test_unknown_question_text_is_an_error():
    """A row whose question isn't in the golden set raises KeyError naming it."""
    try:
        parse_results([row("Some other question", "answer_correctness", 1.0)], IDS)  # unknown question
        assert False, "expected KeyError"
    except KeyError as exc:
        assert "Some other question" in str(exc)                           # names the offending text

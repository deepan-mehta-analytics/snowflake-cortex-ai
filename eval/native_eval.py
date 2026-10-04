"""Run Snowflake's native Cortex Agent Evaluation on AP_INVOICE_AGENT and gate it.

CI entry point (see .github/workflows/live-eval.yml). Loads the golden questions
into COCO.EVAL.GOLDEN_QUESTIONS, uploads the evaluation config, runs
EXECUTE_AI_EVALUATION, reads SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA and applies
eval/gate.py against eval/baseline.json. Exit codes: 0 pass, 1 regression,
2 infrastructure problem.
"""

# ── Imports ───────────────────────────────────────────────────
import hashlib                               # content hash → dataset name
import json                                  # read JSONL rows, write results
from pathlib import Path                     # file paths

# ── Paths and names ───────────────────────────────────────────
EVAL_DIR = Path(__file__).resolve().parent                    # eval/
GOLDEN_PATH = EVAL_DIR / "golden_dataset.jsonl"               # questions + answer keys
TEMPLATE_PATH = EVAL_DIR / "agent_evaluation_config.yaml.tmpl"  # config template
BASELINE_PATH = EVAL_DIR / "baseline.json"                    # committed baseline
RESULTS_DIR = EVAL_DIR / "results"                            # gitignored run outputs
TABLE = "COCO.EVAL.GOLDEN_QUESTIONS"                          # dataset source table
STAGE = "@COCO.EVAL.CONFIG_STAGE"                             # where the rendered config is PUT

# ── Offline helpers ───────────────────────────────────────────
def load_golden(path=GOLDEN_PATH):
    """Read the golden JSONL into a list of dicts."""
    with open(path, encoding="utf-8") as handle:                       # UTF-8: answer keys may hold "—"
        return [json.loads(line) for line in handle if line.strip()]   # skip blank lines

def dataset_name(rows):
    """Name the evaluation dataset after a hash of what the evaluation reads (id, question, answer key)."""
    canonical = json.dumps([[r["id"], r["question"], r["ground_truth_output"]] for r in rows],
                           ensure_ascii=False, separators=(",", ":"))  # stable text of the evaluated fields only
    return "AP_GOLDEN_" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:8].upper()  # 8 hex chars

def render_config(template_text, dataset, table, label, include_dataset=True):
    """Fill the YAML template's {dataset}, {table}, {label} placeholders.

    include_dataset=False drops the leading `dataset:` block: START fails with
    'already exists' when that dataset was created by an earlier run.
    """
    if not include_dataset:                                            # repeat run on an existing dataset
        template_text = template_text[template_text.index("evaluation:"):]  # keep evaluation: and metrics: only
    return template_text.replace("{dataset}", dataset).replace("{table}", table).replace("{label}", label)  # plain replace keeps YAML braces safe

def parse_results(rows, id_by_question):
    """Group GET_AI_EVALUATION_DATA rows into {qid: {metric: score}} plus {qid: error text}."""
    scores, errors = {}, {}                                            # outputs
    for r in rows:                                                     # one row per (record, metric)
        qid = id_by_question[r["INPUT"]]                               # KeyError names an unknown question
        score = r["EVAL_AGG_SCORE"]                                    # judge score (0.0–1.0, verified live)
        status = json.loads(r.get("METRIC_STATUS") or '{"code": 200}')  # judge outcome, e.g. {"code": 400, "message": ...}
        if r.get("ERROR"):                                             # the agent failed on this record
            errors[qid] = str(r["ERROR"])[:200]                        # keep a short reason for the summary
        elif status.get("code") != 200:                                # the judge failed: its 0.0 is not a real score
            errors[qid] = f"{r['METRIC_NAME']}: {status.get('message', 'judge failed')}"[:200]  # reason for the summary
            score = None                                               # treat like an errored record
        scores.setdefault(qid, {})[r["METRIC_NAME"]] = float(score) if score is not None else 0.0  # errors count as 0
    return scores, errors                                              # per-question scores + error notes

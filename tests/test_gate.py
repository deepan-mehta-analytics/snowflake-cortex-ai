"""Offline tests for the native-evaluation regression gate."""

# ── Imports ───────────────────────────────────────────────────
import os                                    # build the import path to eval/
import sys                                   # extend sys.path so gate can be imported

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "eval"))  # make eval/ importable
from gate import evaluate_gate, means, render_summary                     # noqa: E402 — functions under test, after the path insert

# ── Fixtures ──────────────────────────────────────────────────
BASE = {                                                                   # baseline: both metrics mean 0.8
    "recorded": "2026-10-05", "run_name": "baseline",
    "means": {"answer_correctness": 0.8, "logical_consistency": 0.8},
    "per_question": {"q01": {"answer_correctness": 0.8, "logical_consistency": 0.8},
                     "q02": {"answer_correctness": 0.8, "logical_consistency": 0.8}},
}

def run(ac1, ac2, lc1=0.8, lc2=0.8):
    """Build a two-question score dict."""
    return {"q01": {"answer_correctness": ac1, "logical_consistency": lc1},   # question 1 scores
            "q02": {"answer_correctness": ac2, "logical_consistency": lc2}}   # question 2 scores

# ── Tests ─────────────────────────────────────────────────────
def test_means():
    """Each metric's mean is the plain average across questions."""
    assert means(run(1.0, 0.5)) == {"answer_correctness": 0.75, "logical_consistency": 0.8}  # simple averages

def test_unchanged_run_passes():
    """A run identical to the baseline passes."""
    assert evaluate_gate(run(0.8, 0.8), BASE).passed                     # identical to baseline

def test_drop_of_exactly_tolerance_passes():
    """A drop of exactly 0.10 is still within tolerance."""
    assert evaluate_gate(run(0.7, 0.7), BASE).passed                     # 0.8 → 0.7 is exactly −0.10

def test_answer_correctness_drop_fails():
    """A mean answer_correctness drop beyond 0.10 fails and names the metric."""
    result = evaluate_gate(run(0.6, 0.7), BASE)                            # mean 0.65, below 0.70
    assert not result.passed and "answer_correctness" in result.reasons[0]  # reason names the metric

def test_logical_consistency_drop_fails():
    """A mean logical_consistency drop beyond 0.10 fails."""
    assert not evaluate_gate(run(0.8, 0.8, 0.5, 0.6), BASE).passed       # lc mean 0.55

def test_single_question_drop_is_warning_only():
    """A big single-question drop is reported; only the mean decides pass/fail."""
    result = evaluate_gate(run(0.25, 1.0), BASE)                           # q01 drops 0.55, mean 0.625 → fails on mean...
    assert any("q01" in w for w in result.warnings)                       # ...and q01 is listed as a warning
    ok = evaluate_gate({"q01": {"answer_correctness": 0.3, "logical_consistency": 0.8},
                        "q02": {"answer_correctness": 1.0, "logical_consistency": 0.8},
                        "q03": {"answer_correctness": 1.0, "logical_consistency": 0.8}},
                       {**BASE, "means": {"answer_correctness": 0.75, "logical_consistency": 0.8}})
    assert ok.passed and any("q01" in w for w in ok.warnings)             # mean holds, warning still shown

def test_new_question_without_baseline_is_noted_not_crash():
    """A question added after the baseline is a warning, not an error."""
    scores = {**run(0.8, 0.8), "q16": {"answer_correctness": 0.9, "logical_consistency": 0.9}}  # q16 has no baseline
    result = evaluate_gate(scores, BASE)                                   # gate the run
    assert result.passed and any("q16" in w and "no baseline" in w for w in result.warnings)

def test_baseline_question_missing_from_run_is_warning():
    """A baseline question absent from the run is reported."""
    result = evaluate_gate({"q01": {"answer_correctness": 0.8, "logical_consistency": 0.8}}, BASE)  # q02 missing
    assert any("q02" in w and "missing" in w for w in result.warnings)

def test_summary_keeps_unicode(tmp_path):
    """The summary survives a UTF-8 round trip (GitHub step summary) and shows the verdict."""
    result = evaluate_gate(run(0.8, 0.8), BASE)                            # passing run
    text = render_summary(run(0.8, 0.8), BASE, result, {"q01": "core", "q02": "core"}, {"q02": "timeout — retried"})
    path = tmp_path / "summary.md"                                         # write like $GITHUB_STEP_SUMMARY
    path.write_text(text, encoding="utf-8")                                # UTF-8 on disk
    assert "—" in path.read_text(encoding="utf-8") and "PASS" in text     # dash survives; verdict shown

def test_summary_escapes_table_breaking_text():
    """Agent/judge text in notes can't break the markdown table or inject markup (security review)."""
    result = evaluate_gate(run(0.8, 0.8), BASE)                            # passing run
    text = render_summary(run(0.8, 0.8), BASE, result, {}, {"q01": "bad | cell\n## injected [link](http://x)"})
    q01_line = next(line for line in text.splitlines() if line.startswith("| q01"))  # the q01 table row
    assert q01_line.count("|") == 6                                        # 5 cells → 6 pipes, none from the note
    assert "\n## injected" not in text                                     # no new heading from the note
    assert "[link](http://x)" not in text                                  # link markup neutralised

"""Offline checks that the golden dataset is well-formed for native evaluation."""

# ── Imports ───────────────────────────────────────────────────
import json                                   # parse each JSONL row
from pathlib import Path                      # locate repo files relative to this test

DATASET = Path(__file__).resolve().parent.parent / "eval" / "golden_dataset.jsonl"  # golden questions file

# ── Helpers ───────────────────────────────────────────────────
def load_rows():
    """Return every non-blank JSONL row as a dict."""
    with DATASET.open(encoding="utf-8") as handle:                   # read as UTF-8 (answers may contain "—")
        return [json.loads(line) for line in handle if line.strip()]  # skip blank lines

# ── Tests ─────────────────────────────────────────────────────
def test_rows_parse_and_ids_are_unique():
    """17 rows, each with a unique id."""
    ids = [row["id"] for row in load_rows()]            # every question id
    assert len(ids) == 17                               # 15 original + q16 (Cortex Search) + q17 (hallucination trap)
    assert len(set(ids)) == len(ids)                    # no duplicate ids

def test_every_row_has_ground_truth_output():
    """Native evaluation needs a non-trivial answer key on every row."""
    for row in load_rows():                                             # check each question
        truth = row.get("ground_truth_output", "")                       # the answer key text
        assert isinstance(truth, str) and len(truth) >= 40, row["id"]    # present and more than a stub

def test_every_check_exists_in_metrics():
    """Each row's heuristic `check` names a function in eval/metrics.py (local smoke test)."""
    import sys                                                          # extend sys.path for eval/
    sys.path.insert(0, str(DATASET.parent))                             # make eval/ importable
    from metrics import CHECKS                                          # dispatch table of heuristic checks
    for row in load_rows():                                             # every question
        assert row["check"] in CHECKS, row["id"]                        # check name resolves

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
    assert len(ids) == 21                               # 15 original + q16 search + q17 hallucination trap + q18 overdue as-of + q19 as-of date + q20 vendor overdue total + q21 BR-004 review status
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

# ── expected_totals (check B, v1.1.0) ─────────────────────────
def test_expected_totals_shape():
    """Each expected total names a real currency, a whole count and a 2-decimal amount."""
    from decimal import Decimal                                         # exact amounts
    rows = [row for row in load_rows() if "expected_totals" in row]     # rows check B covers
    assert {row["id"] for row in rows} == {"q08", "q11", "q15", "q20"}   # single per-currency totals only
    for row in rows:                                                    # each covered row
        for currency, total in row["expected_totals"].items():          # each currency
            assert currency in {"USD", "EUR", "GBP"}, row["id"]         # the three source currencies
            assert isinstance(total["count"], int) and total["count"] >= 0, row["id"]  # whole invoice count
            assert Decimal(total["amount"]).as_tuple().exponent == -2, row["id"]  # two decimal places

def test_expected_totals_match_ground_truth_text():
    """Every expected amount appears, with thousands separators, in that row's answer key."""
    from decimal import Decimal                                         # exact amounts
    for row in load_rows():                                             # every question
        for currency, total in row.get("expected_totals", {}).items():  # its expected totals
            text = f"{Decimal(total['amount']):,.2f}"                    # e.g. 469,300.00
            assert text in row["ground_truth_output"], (row["id"], currency, text)  # same figure as the key

"""Offline tests for cortex_agent/amounts.py — the amount reader shared by checks B and C."""

# ── Imports ───────────────────────────────────────────────────
import sys                                                   # extend sys.path for cortex_agent/
from decimal import Decimal                                  # exact amounts
from pathlib import Path                                     # fixture files

ROOT = Path(__file__).resolve().parent.parent                # repo root
sys.path.insert(0, str(ROOT / "cortex_agent"))               # make amounts importable
from amounts import check_expected_totals, extract_amounts  # noqa: E402 — functions under test

FIXTURES = ROOT / "tests" / "fixtures" / "q11_outputs"       # real q11 answers from the v1.0.0 eval runs
Q11_TOTALS = {"USD": {"count": 14, "amount": "469300.00"},   # q11 answer key (golden set expected_totals)
              "EUR": {"count": 5, "amount": "101450.50"},
              "GBP": {"count": 3, "amount": "30600.00"}}

def fixture(run_id):
    """Text of one saved q11 answer."""
    return (FIXTURES / f"run_{run_id}.txt").read_text(encoding="utf-8")  # saved OUTPUT column

def values(text):
    """(currency, value) pairs found in a text, in order."""
    return [(a.currency, a.value) for a in extract_amounts(text)]  # drop spans for easy comparison

# ── Check B on the real v1.0.0 answers ────────────────────────
def test_q11_wrong_totals_mismatch():
    """The three runs that hand-summed USD wrongly (679,700 / 657,600 / 709,300) are caught; EUR and GBP pass."""
    for run_id in ("39183731867", "39185143387", "39189340822"):  # the wrong runs
        assert check_expected_totals(fixture(run_id), Q11_TOTALS) == {"USD": "MISMATCH", "EUR": "PASS", "GBP": "PASS"}, run_id

def test_q11_correct_total_passes():
    """The run that quoted 469,300.00 passes for every currency."""
    assert check_expected_totals(fixture("39186725823"), Q11_TOTALS) == {"USD": "PASS", "EUR": "PASS", "GBP": "PASS"}

# ── Formats ───────────────────────────────────────────────────
def test_formats_are_parsed():
    """Currency before or after, symbols, bold markup and plain table cells all read as the same amount."""
    for text in ("USD 469,300", "469,300.00 USD", "$469,300", "**USD 469,300.00**", "- **USD:** 14 invoices totaling $469,300.00"):
        assert values(text) == [("USD", Decimal("469300"))], text  # numeric equality ignores trailing zeros
    assert values("€101,450.50 and £30,600.00") == [("EUR", Decimal("101450.50")), ("GBP", Decimal("30600.00"))]

def test_table_cells_take_the_row_currency():
    """Amount cells inside a [table] block take the currency from the row's CURRENCY_CODE column."""
    table = ('[table]\n```json\n{"columns": ["VENDOR_NAME", "CURRENCY_CODE", "TOTAL_AMOUNT"], '
             '"data": [["Summit Energy Corp", "USD", "138700.00"], ["Nordic Metals AB", "EUR", "88500.00"]]}\n```\n[/table]')
    assert values(table) == [("USD", Decimal("138700.00")), ("EUR", Decimal("88500.00"))]

# ── Things that are not amounts ───────────────────────────────
def test_non_amounts_are_ignored():
    """Dates, invoice numbers, counts, percentages and question ids are never read as amounts."""
    for text in ("As of 2025-04-30", "INV-2025-0010 and ORA-INV-50008", "22 invoices", "25% of the limit", "see q11", "BR-004"):
        assert values(text) == [], text                      # nothing extracted

def test_no_amounts_answer():
    """An answer without amounts gives no amounts and, with no expected totals, no verdicts."""
    text = "This data is a snapshot as of **2025-06-30**."       # q19-style answer
    assert extract_amounts(text) == []                       # nothing to check
    assert check_expected_totals(text, {}) == {}             # caller reports NOT-APPLICABLE

def test_missing_currency_is_not_found():
    """An expected currency that the answer never mentions is NOT-FOUND, not a mismatch."""
    assert check_expected_totals("USD 469,300.00", Q11_TOTALS) == {"USD": "PASS", "EUR": "NOT-FOUND", "GBP": "NOT-FOUND"}

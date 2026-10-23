"""Offline tests for run_agent.parse_final_response.

The canned events below copy the shape of a real `response` SSE event
returned by COCO.AGENT.AP_INVOICE_AGENT:run on 2026-10-04 (current agent
schema: named events, final message carries the full content list).
"""

# ── Imports ───────────────────────────────────────────────────
import os                                    # build the import path to cortex_agent/
import sys                                   # extend sys.path so run_agent can be imported

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "cortex_agent"))  # make run_agent importable
from run_agent import parse_final_response    # the pure parser under test (no network, no env vars)

# ── Canned content items (shapes from the live agent) ─────────
TEXT_ITEM = {"type": "text", "text": "Here's the invoice count by source system, totaling 50 invoices."}  # final answer text
THINKING_ITEM = {"type": "thinking", "thinking": {"text": "internal planning"}}                      # must not leak into the answer
TABLE_ITEM = {                                                                                          # rows the agent executed itself
    "type": "table",
    "table": {
        "title": "Invoices per Source System",
        "result_set": {
            "data": [["SAP", "15"], ["ORACLE", "15"], ["BAAN", "10"], ["WORKDAY", "10"]],
            "resultSetMetaData": {"rowType": [{"name": "SOURCE_SYSTEM", "type": "text"},
                                              {"name": "INVOICE_COUNT", "type": "fixed"}]},
        },
    },
}
DATE_TABLE_ITEM = {                                                                                     # DATE cells arrive as epoch days
    "type": "table",
    "table": {"title": "Due dates", "result_set": {"data": [["20089"]],
              "resultSetMetaData": {"rowType": [{"name": "DUE_DATE", "type": "date"}]}}},
}

# ── Tests ─────────────────────────────────────────────────────
def test_text_and_table_are_both_returned():
    """Answer text comes first, then the executed table with a header row."""
    answer = parse_final_response({"content": [THINKING_ITEM, TEXT_ITEM, TABLE_ITEM]})  # parse a full message
    assert answer.startswith("Here's the invoice count")                                # text answer first
    assert "SOURCE_SYSTEM, INVOICE_COUNT" in answer                                      # table header present
    assert "WORKDAY, 10" in answer                                                       # table rows present
    assert "internal planning" not in answer                                             # thinking is never shown

def test_date_cells_are_converted():
    """Epoch-day DATE values are shown as YYYY-MM-DD."""
    answer = parse_final_response({"content": [DATE_TABLE_ITEM]})  # table-only message
    assert "2025-01-01" in answer                                    # 20089 days after 1970-01-01

def test_iso_date_cells_pass_through():
    """The live agent's tables already send DATE cells as ISO strings (seen 2026-10-04) — keep them as-is."""
    iso_item = {"type": "table", "table": {"result_set": {"data": [["2025-01-01"]],               # ISO date, not epoch days
                "resultSetMetaData": {"rowType": [{"name": "DUE_DATE", "type": "date"}]}}}}
    assert "2025-01-01" in parse_final_response({"content": [iso_item]})                           # no int() crash, value kept

def test_empty_message_returns_placeholder():
    """A message with no text or table gives an explicit placeholder, not an empty string."""
    assert parse_final_response({"content": [THINKING_ITEM]}) == "(no answer or tool result returned)"  # nothing usable

# ── Check C: amounts traceable to query results (v1.1.0) ──────
import json                                                     # read the real q11 table  # noqa: E402
from decimal import Decimal                                     # exact amounts  # noqa: E402
from pathlib import Path                                        # fixture path  # noqa: E402

from run_agent import collect_tool_values, verify_amounts       # noqa: E402 — check C under test

def result_table(columns, rows):
    """A `table` content item in the agent's result_set shape (all columns typed text/fixed)."""
    row_type = [{"name": c, "type": "fixed" if "AMOUNT" in c else "text"} for c in columns]  # column metadata
    return {"type": "table", "table": {"title": "rows", "result_set": {"data": rows, "resultSetMetaData": {"rowType": row_type}}}}

def q11_message(answer):
    """Final message for q11: the real 22 overdue rows from the v1.0.0 main run, plus the given answer text."""
    saved = (Path(__file__).parent / "fixtures" / "q11_outputs" / "run_39189340822.txt").read_text(encoding="utf-8")  # real answer
    table = json.loads(saved.split("```json", 1)[1].split("```", 1)[0])   # its embedded result table
    return {"content": [{"type": "text", "text": answer}, result_table(table["columns"], table["data"])]}

def test_traceable_total_is_quiet():
    """An amount that is a cell of a query result is backed: no flag."""
    message = {"content": [{"type": "text", "text": "Acme Industrial Supply: 40,700.00 USD."},
                           result_table(["VENDOR_NAME", "CURRENCY_CODE", "TOTAL_AMOUNT"], [["Acme Industrial Supply", "USD", "40700.00"]])]}
    assert verify_amounts("Acme Industrial Supply: 40,700.00 USD.", collect_tool_values(message)) == []

def test_exact_hand_sum_is_quiet():
    """A total that equals the per-currency sum of a returned amount column is backed: no flag."""
    message = q11_message("USD total 469,300.00")                         # correct hand-sum of the 14 USD rows
    assert verify_amounts("USD total 469,300.00", collect_tool_values(message)) == []

def test_wrong_hand_sum_is_flagged_with_recomputed_value():
    """The v1.0.0 main-run mistake (USD 709,300.00) is flagged with the true sum of the rows returned."""
    answer = "By currency, the overdue totals are **USD 709,300.00**, **EUR 101,450.50**, and **GBP 30,600.00**."  # real wording
    flags = verify_amounts(answer, collect_tool_values(q11_message(answer)))  # check the real answer
    assert len(flags) == 1                                                 # only the USD total is wrong
    assert flags[0].amount.currency == "USD" and flags[0].amount.value == Decimal("709300.00")  # the wrong figure
    assert flags[0].recomputed == Decimal("469300.00")                     # what the rows actually sum to

def test_untraceable_amount_without_rows():
    """An amount with no query result behind it is flagged without a recomputed value."""
    flags = verify_amounts("The total is USD 1,234.00.", collect_tool_values({"content": [{"type": "text", "text": "x"}]}))
    assert len(flags) == 1 and flags[0].recomputed is None                 # nothing to recompute from

def test_no_amounts_no_flags():
    """An answer without amounts (q19-style) never produces a flag."""
    assert verify_amounts("This data is a snapshot as of **2025-06-30**.", collect_tool_values({"content": []})) == []

def test_tool_result_values_are_backed():
    """Values inside a tool_result item (e.g. invoice_totals output) count as query results."""
    message = {"content": [{"type": "tool_result", "tool_result": {"name": "invoice_totals", "content": [{"type": "json", "json": {
        "result_set": {"data": [["USD", "14", "469300.00"]], "resultSetMetaData": {"rowType": [
            {"name": "CURRENCY_CODE", "type": "text"}, {"name": "INVOICE_COUNT", "type": "fixed"}, {"name": "TOTAL_AMOUNT", "type": "fixed"}]}}}}]}}]}
    assert verify_amounts("USD 469,300.00 across 14 invoices", collect_tool_values(message)) == []

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

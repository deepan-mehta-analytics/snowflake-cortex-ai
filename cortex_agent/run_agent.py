"""Minimal client for the Snowflake Cortex Agents REST API.

Sends a single natural-language question to the registered agent object
COCO.AGENT.AP_INVOICE_AGENT — the same agent the MCP server exposes to
Claude. The agent's model, tools and instructions live in Snowflake
(synced copy: cortex_project/ap_invoice_agent.agent.yaml), with the
orchestration model on `auto`, so a retired model can't break this client.

The agent runs its generated SQL itself (execution_environment on
WH_COCO_PIPELINE) and streams the current agent event schema: named SSE
events ending in one `response` event that carries the full message. This
client reads that final message and prints its text plus any result tables.

Check C (v1.1.0): every amount in the answer text must be traceable to the
data — a value some query returned, or the exact per-currency sum of a
returned amount column. Anything else is printed after the answer as a
⚠️ amount check, with the true sum of the rows when it can be worked out.
"""

# ── Imports ───────────────────────────────────────────────────
import os                                    # read account/token config from environment variables
import sys                                   # read the question from argv and exit with proper codes
import json                                  # parse each SSE data payload
import datetime                              # convert raw epoch-day DATE values to calendar dates
from dataclasses import dataclass, field     # small records for check C
from decimal import Decimal, InvalidOperation  # exact amounts, no float rounding
from typing import NamedTuple                # flag record
import requests                              # issue HTTPS requests to the Cortex Agents API

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # amounts.py lives next to this file
from amounts import CURRENCIES, Amount, extract_amounts  # noqa: E402 — shared amount reader (check B + C)

# ── Constants ─────────────────────────────────────────────────
EPOCH = datetime.date(1970, 1, 1)                                # result sets return DATE cells as days since this epoch
AGENT_PATH = "/api/v2/databases/COCO/schemas/AGENT/agents/AP_INVOICE_AGENT:run"  # run the registered agent object
REQUEST_TIMEOUT = (10, 120)                                      # (connect, read) seconds — a stalled call fails instead of hanging
NO_ANSWER = "(no answer or tool result returned)"                # explicit placeholder when the message has nothing usable

# ── Shared auth headers ──────────────────────────────────────────
def auth_headers(pat: str) -> dict:
    """Build the PAT-based auth headers for the streaming agent call."""
    return {
        "Authorization": f"Bearer {pat}",                       # PAT-based auth against the REST API
        "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",  # tells Snowflake the bearer token is a PAT, not OAuth/session
        "Content-Type": "application/json",                    # request body is JSON
        "Accept": "text/event-stream",                          # the agent streams server-sent events
    }

# ── Format one result table ─────────────────────────────────────
def format_table(table: dict) -> str:
    """Render a `table` content item as a title, a header row and one line per row."""
    result_set = table.get("result_set", {})                     # executed query result in SQL API jsonv2 shape
    row_types = result_set.get("resultSetMetaData", {}).get("rowType", [])  # per-column name + type metadata
    lines = [table["title"]] if table.get("title") else []        # optional table title from the agent
    lines.append(", ".join(col["name"] for col in row_types))     # header row
    for raw_row in result_set.get("data", []):                    # each raw row is a list of string cells
        cells = []                                                 # this row's formatted cells
        for col, value in zip(row_types, raw_row):                 # pair each cell with its column's type
            if col.get("type") == "date" and str(value).isdigit():  # epoch-day string (SQL API style); ISO dates pass through
                value = (EPOCH + datetime.timedelta(days=int(value))).isoformat()  # convert to YYYY-MM-DD
            cells.append(str(value))                                # keep every cell as text
        lines.append(", ".join(cells))                              # one output line per row
    return "\n".join(lines)                                         # the whole table as text

# ── Parse the final agent message ────────────────────────────────
def parse_final_response(message: dict) -> str:
    """Turn the final `response` event's message into printable text (text first, then tables)."""
    texts = []                                                     # answer text blocks, in order
    tables = []                                                    # formatted result tables, in order
    for item in message.get("content", []):                        # walk every content item in the message
        if item.get("type") == "text":                             # final answer text (thinking items are skipped)
            texts.append(item.get("text", ""))                     # keep the text block
        elif item.get("type") == "table":                          # rows from SQL the agent executed itself
            tables.append(format_table(item.get("table", {})))     # keep the formatted table
    parts = ["".join(texts).strip()] + tables                       # text first, then each table
    answer = "\n\n".join(part for part in parts if part)            # drop empty parts
    return answer or NO_ANSWER                                       # never return an empty string

# ── Check C: amounts traceable to query results ───────────────
@dataclass
class ToolValues:
    cells: set = field(default_factory=set)                         # every number any query returned
    column_sums: dict = field(default_factory=dict)                 # currency (or None) → list of (rows, sum) per amount column

class Flag(NamedTuple):
    amount: Amount                                                  # the amount in the answer that no query backs
    recomputed: Decimal | None                                      # true per-currency sum of the rows returned, if known
    reason: str                                                     # line printed under the answer

def to_decimal(value):
    """A cell as an exact number, or None when it is not numeric."""
    try:
        return Decimal(str(value).replace(",", ""))                 # "469300.00" → Decimal
    except (InvalidOperation, ValueError):                          # text, dates, empty cells
        return None                                                 # not a number

def result_sets(node):
    """Every result_set-shaped object (rowType + data) anywhere inside a content item."""
    if isinstance(node, dict):                                      # walk dicts
        if "data" in node and "resultSetMetaData" in node:          # SQL API jsonv2 result
            yield node                                              # one result set
        for value in node.values():                                 # and anything nested
            yield from result_sets(value)
    elif isinstance(node, list):                                    # walk lists
        for value in node:
            yield from result_sets(value)

def scalars(node):
    """Every scalar inside a tool_result item (procedure output may not be a result_set)."""
    if isinstance(node, dict):                                      # walk dicts
        for value in node.values():
            yield from scalars(value)
    elif isinstance(node, list):                                    # walk lists
        for value in node:
            yield from scalars(value)
    else:                                                           # a leaf value
        yield node

def collect_tool_values(message):
    """Numbers the agent's tools returned in the final message: table cells, tool_result values, column sums."""
    values = ToolValues()                                           # what the answer may quote
    for item in message.get("content", []):                        # every content item
        if item.get("type") not in ("table", "tool_result"):       # answer text and thinking are not data
            continue                                                # skip them
        if item.get("type") == "tool_result":                      # raw tool output
            values.cells |= {d for d in map(to_decimal, scalars(item)) if d is not None}  # any number in it
        for result in result_sets(item):                            # each returned table
            names = [c.get("name", "").upper() for c in result.get("resultSetMetaData", {}).get("rowType", [])]  # columns
            currency_col = next((i for i, n in enumerate(names) if n.startswith("CURRENCY")), None)  # CURRENCY_CODE
            money_cols = [i for i, n in enumerate(names) if any(k in n for k in ("AMOUNT", "TOTAL", "SPEND")) and "COUNT" not in n]
            for i in money_cols:                                    # each amount column
                per_currency = {}                                   # currency → (rows, running sum)
                for row in result.get("data", []):                  # each row
                    amount = to_decimal(row[i]) if i < len(row) else None  # the cell as a number
                    if amount is None:                              # empty or text cell
                        continue                                    # not summable
                    currency = str(row[currency_col]).upper() if currency_col is not None else None  # row currency
                    currency = currency if currency in CURRENCIES else None  # unknown → None
                    rows, total = per_currency.get(currency, (0, Decimal(0)))  # running count + sum
                    per_currency[currency] = (rows + 1, total + amount)  # add this row
                for currency, pair in per_currency.items():         # keep each column's sum per currency
                    values.column_sums.setdefault(currency, []).append(pair)
            for row in result.get("data", []):                      # every cell is a returned value
                values.cells |= {d for d in map(to_decimal, row) if d is not None}
    return values                                                   # traceable numbers

def verify_amounts(answer_text, values):
    """Check C: flag each amount in the answer text that is neither a returned value nor an exact column sum."""
    flags = []                                                      # untraceable amounts
    for amount in extract_amounts(answer_text):                     # every amount the answer states
        currencies = [amount.currency, None] if amount.currency else list(values.column_sums)  # sums it may equal
        sums = [total for c in currencies for _, total in values.column_sums.get(c, [])]  # candidate sums
        if amount.value in values.cells or amount.value in sums:   # returned by a query, or an exact sum of one
            continue                                                # backed by the data
        same = values.column_sums.get(amount.currency, []) if amount.currency else []  # sums in its currency
        recomputed = max(same)[1] if same else None                 # the sum over the most rows, if any
        label = f"{amount.currency + ' ' if amount.currency else ''}{amount.value:,.2f}"  # e.g. USD 709,300.00
        if recomputed is not None:                                  # we know what the rows add up to
            reason = f"{label} is not in any query result; the rows returned sum to {amount.currency} {recomputed:,.2f}"
        else:                                                       # nothing to recompute from
            reason = f"{label} could not be traced to any query result"
        flags.append(Flag(amount, recomputed, reason))              # record it
    return flags                                                    # empty = every amount is backed

def answer_text(message):
    """The final message's answer text only (what check C reads)."""
    return "".join(i.get("text", "") for i in message.get("content", []) if i.get("type") == "text").strip()  # text items

# ── Call the agent ────────────────────────────────────────────
def run_agent(question: str) -> tuple:
    """Send one question to the registered agent; return (formatted answer, check C flags)."""
    account = os.environ["SNOWFLAKE_ACCOUNT"]                      # e.g. "xy12345-ab12345" — required, no default
    pat = os.environ["SNOWFLAKE_PAT"]                              # programmatic access token used for auth
    url = f"https://{account}.snowflakecomputing.com{AGENT_PATH}"   # full agent:run URL for this account
    payload = {                                                    # model, tools and instructions come from the agent object
        "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],  # single-turn question
    }
    response = requests.post(url, headers=auth_headers(pat), json=payload, stream=True, timeout=REQUEST_TIMEOUT)  # open the stream
    response.raise_for_status()                                    # fail loudly on non-2xx before parsing anything
    response.encoding = "utf-8"                                    # SSE has no charset header; requests would assume ISO-8859-1 and garble "—"

    event_name = None                                              # name of the SSE event the next data line belongs to
    for line in response.iter_lines(decode_unicode=True):          # iterate over each SSE line as it arrives
        if line.startswith("event: "):                             # an event name line precedes its data line
            event_name = line[len("event: "):]                     # remember which event is next
        elif line.startswith("data: ") and event_name == "response":  # the final message with the full content list
            message = json.loads(line[len("data: "):])            # the full final message
            flags = verify_amounts(answer_text(message), collect_tool_values(message))  # check C
            return parse_final_response(message), flags             # answer + any untraceable amounts
        elif line.startswith("data: ") and event_name == "error":  # the agent reported an error mid-stream
            raise RuntimeError(f"agent error: {line[len('data: '):]}")  # surface it instead of returning nothing
    return NO_ANSWER, []                                            # the stream ended without a final message

def format_flags(flags: list) -> str:
    """The ⚠️ block printed under an answer; empty when every amount is backed."""
    if not flags:                                                   # nothing untraceable
        return ""                                                   # print nothing extra
    return "\n".join(["⚠️ Amount check:"] + [f"- {f.reason}" for f in flags])  # one line per flagged amount

# ── Entry point ───────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2:                                       # require a question on the command line
        print("Usage: python run_agent.py \"<question>\"")      # usage message for missing argv
        sys.exit(1)                                             # non-zero exit on misuse

    if hasattr(sys.stdout, "reconfigure"):                      # Windows consoles default to cp1252
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # "⚠️" must never crash the print
    answer, flags = run_agent(sys.argv[1])                      # run the agent against the supplied question
    print(answer)                                               # print the final answer to stdout
    if flags:                                                   # check C found untraceable amounts
        print("\n" + format_flags(flags))                       # warn the reader; exit code unchanged

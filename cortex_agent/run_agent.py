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
"""

# ── Imports ───────────────────────────────────────────────────
import os                                    # read account/token config from environment variables
import sys                                   # read the question from argv and exit with proper codes
import json                                  # parse each SSE data payload
import datetime                              # convert raw epoch-day DATE values to calendar dates
import requests                              # issue HTTPS requests to the Cortex Agents API

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

# ── Call the agent ────────────────────────────────────────────
def run_agent(question: str) -> str:
    """Send one question to the registered agent and return its formatted answer."""
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
            return parse_final_response(json.loads(line[len("data: "):]))  # parse and return it
        elif line.startswith("data: ") and event_name == "error":  # the agent reported an error mid-stream
            raise RuntimeError(f"agent error: {line[len('data: '):]}")  # surface it instead of returning nothing
    return NO_ANSWER                                                # the stream ended without a final message

# ── Entry point ───────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2:                                       # require a question on the command line
        print("Usage: python run_agent.py \"<question>\"")      # usage message for missing argv
        sys.exit(1)                                             # non-zero exit on misuse

    answer = run_agent(sys.argv[1])                             # run the agent against the supplied question
    print(answer)                                               # print the final answer to stdout

"""Minimal client for the Snowflake Cortex Agents REST API.

Exercises the agent defined in agent_spec.yaml against a single
natural-language question. The cortex_analyst_text_to_sql tool returns
governed SQL rather than executed results, so this client executes that SQL
itself via the SQL API and prints the interpretation plus real rows.
"""

# ── Imports ───────────────────────────────────────────────────
import os                                    # read account/token config from environment variables
import sys                                   # read the question from argv and exit with proper codes
import json                                  # build request bodies and parse streamed/response JSON
import datetime                              # convert SQL API's raw epoch-day DATE values to calendar dates
import yaml                                  # load agent_spec.yaml into a Python dict
import requests                              # issue HTTPS requests to the Cortex Agents and SQL APIs

EPOCH = datetime.date(1970, 1, 1)            # SQL API returns DATE columns as days since this epoch

# ── Configuration ─────────────────────────────────────────────
SNOWFLAKE_ACCOUNT = os.environ["SNOWFLAKE_ACCOUNT"]              # e.g. "xy12345.us-east-1" — required, no default
SNOWFLAKE_PAT = os.environ["SNOWFLAKE_PAT"]                      # programmatic access token used for auth
AGENT_SPEC_PATH = os.path.join(os.path.dirname(__file__), "agent_spec.yaml")  # co-located spec file
AGENT_ENDPOINT = f"https://{SNOWFLAKE_ACCOUNT}.snowflakecomputing.com/api/v2/cortex/agent:run"  # agent REST endpoint
SQL_ENDPOINT = f"https://{SNOWFLAKE_ACCOUNT}.snowflakecomputing.com/api/v2/statements"          # SQL API endpoint

# ── Shared auth headers ──────────────────────────────────────────
def auth_headers(accept: str) -> dict:
    """Build the PAT-based auth headers shared by both REST calls."""
    return {
        "Authorization": f"Bearer {SNOWFLAKE_PAT}",             # PAT-based auth against the REST API
        "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",  # tells Snowflake the bearer token is a PAT, not OAuth/session
        "Content-Type": "application/json",                    # request body is JSON
        "Accept": accept,                                       # SSE for the agent, plain JSON for the SQL API
    }

# ── Load agent spec ───────────────────────────────────────────
def load_agent_spec() -> dict:
    """Read agent_spec.yaml and return it as a plain dict."""
    with open(AGENT_SPEC_PATH, "r", encoding="utf-8") as f:  # open the YAML spec for reading
        return yaml.safe_load(f)                              # parse YAML into a Python dict

# ── Execute governed SQL ─────────────────────────────────────────
def execute_sql(sql: str, warehouse: str) -> tuple:
    """Run SQL via the SQL API and return (column_names, rows)."""
    body = {"statement": sql, "warehouse": warehouse.upper(), "database": "COCO"}  # SQL API needs the exact-cased (uppercase) object name here, unlike inside a SQL statement
    resp = requests.post(SQL_ENDPOINT, headers=auth_headers("application/json"), json=body)  # synchronous SQL API call
    if not resp.ok:
        print(f"DEBUG: SQL API error body: {resp.text}", file=sys.stderr)  # surface the exact error detail before raising
    resp.raise_for_status()                                     # fail loudly on non-2xx before parsing anything
    result = resp.json()                                        # parse the SQL API's JSON response
    row_types = result["resultSetMetaData"]["rowType"]           # per-column name + type metadata
    columns = [col["name"] for col in row_types]                  # extract column names in order
    rows = []                                                      # accumulate type-formatted rows
    for raw_row in result.get("data", []):                        # walk each raw row (list of string cell values)
        formatted_row = []                                         # accumulate this row's formatted cells
        for col, value in zip(row_types, raw_row):                # pair each cell with its column's type metadata
            if value is not None and col["type"] == "date":        # DATE cells arrive as a raw epoch-day string
                value = (EPOCH + datetime.timedelta(days=int(value))).isoformat()  # convert to YYYY-MM-DD
            formatted_row.append(value)
        rows.append(formatted_row)
    return columns, rows                                         # hand back both for formatting

# ── Call the agent ────────────────────────────────────────────
def run_agent(question: str) -> str:
    """Send one question to the agent and return a formatted answer."""
    spec = load_agent_spec()                                   # load tool/model config from agent_spec.yaml
    warehouse = spec["tool_resources"]["ap_semantic_view"]["warehouse"]  # warehouse used to execute any generated SQL

    payload = {
        "model": spec["models"]["orchestration"],               # orchestration model from the spec
        "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],  # single-turn question
        "tools": spec["tools"],                                 # tool specs (semantic view + search) from the spec
        "tool_resources": spec["tool_resources"],               # concrete resources each tool binds to
    }

    response = requests.post(AGENT_ENDPOINT, headers=auth_headers("text/event-stream"), json=payload, stream=True)  # open streaming request
    response.raise_for_status()                                 # fail loudly on non-2xx before parsing anything

    final_text_parts = []                                       # accumulate text deltas across the SSE stream
    generated_sql = None                                        # SQL surfaced by the cortex_analyst_text_to_sql tool, if any
    sql_interpretation = None                                   # the tool's plain-English restatement of the question

    for line in response.iter_lines(decode_unicode=True):        # iterate over each SSE line as it arrives
        if not line or not line.startswith("data: "):           # skip keep-alive/blank lines
            continue
        raw = line[len("data: "):]                               # payload after the "data: " prefix
        if raw == "[DONE]":                                       # standard SSE terminal sentinel, not an event
            continue
        try:
            event = json.loads(raw)                              # parse the JSON payload
        except json.JSONDecodeError:
            continue                                              # skip any other non-JSON control lines

        for delta in event.get("delta", {}).get("content", []):  # walk content deltas in this event
            delta_type = delta.get("type")                        # e.g. "text", "tool_use", "tool_results"
            if delta_type == "text":                              # plain-text answer chunk from the orchestration model
                final_text_parts.append(delta.get("text", ""))    # append this chunk to the running answer
            elif delta_type == "tool_results":                    # result of a tool call (e.g. generated SQL)
                for item in delta.get("tool_results", {}).get("content", []):  # walk this tool's result content
                    if item.get("type") == "json":                # cortex_analyst_text_to_sql returns a json payload
                        payload_json = item.get("json", {})       # the {"sql": ..., "text": ...} payload
                        generated_sql = payload_json.get("sql")   # governed SQL generated from the semantic view
                        sql_interpretation = payload_json.get("text")  # the tool's restated interpretation of the question

    answer = "".join(final_text_parts)                            # prefer a direct text answer if the model gave one
    if answer:                                                    # orchestration model produced its own summary
        return answer

    if generated_sql:                                             # no text answer, but the tool returned SQL — run it
        columns, rows = execute_sql(generated_sql, warehouse)      # execute the governed SQL to get real results
        lines = []                                                 # accumulate formatted output lines
        if sql_interpretation:                                     # include the tool's restated question, if given
            lines.append(sql_interpretation)
            lines.append("")
        lines.append(", ".join(columns))                           # header row
        for row in rows:                                           # one line per result row
            lines.append(", ".join(str(value) for value in row))
        return "\n".join(lines)

    return "(no answer or tool result returned)"                  # neither a text answer nor a tool result arrived

# ── Entry point ───────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2:                                       # require a question on the command line
        print("Usage: python run_agent.py \"<question>\"")      # usage message for missing argv
        sys.exit(1)                                             # non-zero exit on misuse

    answer = run_agent(sys.argv[1])                             # run the agent against the supplied question
    print(answer)                                               # print the final answer to stdout

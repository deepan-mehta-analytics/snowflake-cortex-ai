"""Minimal client for the Snowflake Cortex Agents REST API.

Scaffold only: exercises the agent defined in agent_spec.yaml against a
single natural-language question and prints the final text answer. Extend
or replace with a proper SDK call once your account's Cortex Agents API
surface is confirmed.
"""

# ── Imports ───────────────────────────────────────────────────
import os                                    # read account/token config from environment variables
import sys                                   # read the question from argv and exit with proper codes
import json                                  # build the request body and parse streamed response chunks
import yaml                                  # load agent_spec.yaml into a Python dict
import requests                              # issue the HTTPS request to the Cortex Agents endpoint

# ── Configuration ─────────────────────────────────────────────
SNOWFLAKE_ACCOUNT = os.environ["SNOWFLAKE_ACCOUNT"]              # e.g. "xy12345.us-east-1" — required, no default
SNOWFLAKE_PAT = os.environ["SNOWFLAKE_PAT"]                      # programmatic access token used for auth
AGENT_SPEC_PATH = os.path.join(os.path.dirname(__file__), "agent_spec.yaml")  # co-located spec file
AGENT_ENDPOINT = f"https://{SNOWFLAKE_ACCOUNT}.snowflakecomputing.com/api/v2/cortex/agent:run"  # REST endpoint

# ── Load agent spec ───────────────────────────────────────────
def load_agent_spec() -> dict:
    """Read agent_spec.yaml and return it as a plain dict."""
    with open(AGENT_SPEC_PATH, "r", encoding="utf-8") as f:  # open the YAML spec for reading
        return yaml.safe_load(f)                              # parse YAML into a Python dict

# ── Call the agent ────────────────────────────────────────────
def run_agent(question: str) -> str:
    """Send one question to the agent and return its final text answer."""
    spec = load_agent_spec()                                   # load tool/model config from agent_spec.yaml

    headers = {
        "Authorization": f"Bearer {SNOWFLAKE_PAT}",             # PAT-based auth against the REST API
        "Content-Type": "application/json",                    # request body is JSON
        "Accept": "text/event-stream",                         # agent responses are streamed as SSE
    }

    payload = {
        "model": spec["models"]["orchestration"],               # orchestration model from the spec
        "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],  # single-turn question
        "tools": spec["tools"],                                 # tool specs (semantic view + search) from the spec
        "tool_resources": spec["tool_resources"],               # concrete resources each tool binds to
    }

    response = requests.post(AGENT_ENDPOINT, headers=headers, json=payload, stream=True)  # open streaming request
    response.raise_for_status()                                 # fail loudly on non-2xx before parsing anything

    final_text_parts = []                                       # accumulate text deltas across the SSE stream
    for line in response.iter_lines(decode_unicode=True):        # iterate over each SSE line as it arrives
        if not line or not line.startswith("data: "):           # skip keep-alive/blank lines
            continue
        event = json.loads(line[len("data: "):])                # parse the JSON payload after the "data: " prefix
        for delta in event.get("delta", {}).get("content", []):  # walk content deltas in this event
            if delta.get("type") == "text":                      # only accumulate plain-text deltas
                final_text_parts.append(delta.get("text", ""))   # append this chunk to the running answer

    return "".join(final_text_parts)                            # join all chunks into the final answer string

# ── Entry point ───────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2:                                       # require a question on the command line
        print("Usage: python run_agent.py \"<question>\"")      # usage message for missing argv
        sys.exit(1)                                             # non-zero exit on misuse

    answer = run_agent(sys.argv[1])                             # run the agent against the supplied question
    print(answer)                                               # print the final answer to stdout

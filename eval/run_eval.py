"""Evaluation harness for the AP invoice Cortex Agent.

Runs every question in golden_dataset.jsonl through the agent, scores each
answer with metrics.py, and writes a timestamped results file plus a
pass-rate summary to stdout.
"""

# ── Imports ───────────────────────────────────────────────────
import os                                    # build file paths relative to this script
import sys                                   # add cortex_agent/ to the import path
import json                                  # read the JSONL dataset and write JSON results
import datetime                              # stamp the results filename

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "cortex_agent"))  # allow importing run_agent
from run_agent import run_agent               # the same client used interactively, reused for eval
from metrics import score                     # scoring dispatch table keyed by golden-row "check"

# ── Paths ─────────────────────────────────────────────────────
DATASET_PATH = os.path.join(os.path.dirname(__file__), "golden_dataset.jsonl")  # golden Q&A set
RESULTS_DIR = os.path.join(os.path.dirname(__file__), "results")                # where run output lands

# ── Dataset loading ───────────────────────────────────────────
def load_dataset() -> list[dict]:
    """Read golden_dataset.jsonl into a list of row dicts."""
    rows = []                                      # accumulate parsed rows here
    with open(DATASET_PATH, "r", encoding="utf-8") as f:  # open the JSONL file for reading
        for line in f:                              # iterate one JSON object per line
            line = line.strip()                      # drop trailing newline/whitespace
            if line:                                  # skip any blank lines
                rows.append(json.loads(line))          # parse and collect the row
    return rows                                        # return the full dataset

# ── Evaluation loop ───────────────────────────────────────────
def run_evaluation() -> list[dict]:
    """Run every dataset row through the agent and score the result."""
    results = []                                        # collect one result dict per question
    for row in load_dataset():                          # iterate the golden dataset in order
        answer = run_agent(row["question"])              # call the live agent with this question
        passed, note = score(answer, row)                 # score the answer against its named check
        results.append({                                  # record everything needed to audit this run later
            "id": row["id"],
            "category": row["category"],
            "question": row["question"],
            "answer": answer,
            "passed": passed,
            "note": note,
        })
        print(f"[{row['id']}] {'PASS' if passed else 'FAIL'} — {note}")  # progress line as we go
    return results                                         # return the full set of scored results

# ── Results persistence ───────────────────────────────────────
def save_results(results: list[dict]) -> str:
    """Write results to a timestamped JSON file under eval/results/ and return its path."""
    os.makedirs(RESULTS_DIR, exist_ok=True)               # ensure the results directory exists
    timestamp = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")  # UTC timestamp for the filename
    out_path = os.path.join(RESULTS_DIR, f"eval_run_{timestamp}.json")  # unique path for this run
    with open(out_path, "w", encoding="utf-8") as f:        # open the output file for writing
        json.dump(results, f, indent=2)                      # pretty-print the results as JSON
    return out_path                                          # hand back the path for the summary line

# ── Entry point ───────────────────────────────────────────────
if __name__ == "__main__":
    results = run_evaluation()                              # run the full golden set against the live agent
    passed_count = sum(1 for r in results if r["passed"])    # count how many checks passed
    total_count = len(results)                               # total number of questions evaluated
    out_path = save_results(results)                          # persist the detailed results to disk

    print(f"\n{passed_count}/{total_count} checks passed")     # headline pass rate
    print(f"Results written to {out_path}")                    # where to find the full detail

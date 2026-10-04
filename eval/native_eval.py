"""Run Snowflake's native Cortex Agent Evaluation on AP_INVOICE_AGENT and gate it.

CI entry point (see .github/workflows/live-eval.yml). Loads the golden questions
into COCO.EVAL.GOLDEN_QUESTIONS, uploads the evaluation config, runs
EXECUTE_AI_EVALUATION, reads SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA and applies
eval/gate.py against eval/baseline.json. Exit codes: 0 pass, 1 regression,
2 infrastructure problem.
"""

# ── Imports ───────────────────────────────────────────────────
import argparse                              # CLI flags
import datetime                              # timestamps for results/baseline
import hashlib                               # content hash → dataset name
import json                                  # read JSONL rows, write results
import os                                    # env vars
import sys                                   # exit codes, stderr
import tempfile                              # local file to PUT
import time                                  # sleep between status polls
from pathlib import Path                     # file paths

import snowflake.connector                   # Snowflake Python connector (requirements-dev.txt)

sys.path.insert(0, str(Path(__file__).resolve().parent))  # import gate.py from eval/
from gate import METRICS, evaluate_gate, means, render_summary  # noqa: E402 — pure gate (Task 2), after the path insert

# ── Paths and names ───────────────────────────────────────────
EVAL_DIR = Path(__file__).resolve().parent                    # eval/
GOLDEN_PATH = EVAL_DIR / "golden_dataset.jsonl"               # questions + answer keys
TEMPLATE_PATH = EVAL_DIR / "agent_evaluation_config.yaml.tmpl"  # config template
BASELINE_PATH = EVAL_DIR / "baseline.json"                    # committed baseline
RESULTS_DIR = EVAL_DIR / "results"                            # gitignored run outputs
TABLE = "COCO.EVAL.GOLDEN_QUESTIONS"                          # dataset source table
STAGE = "@COCO.EVAL.CONFIG_STAGE"                             # where the rendered config is PUT

# ── Offline helpers ───────────────────────────────────────────
def load_golden(path=GOLDEN_PATH):
    """Read the golden JSONL into a list of dicts."""
    with open(path, encoding="utf-8") as handle:                       # UTF-8: answer keys may hold "—"
        return [json.loads(line) for line in handle if line.strip()]   # skip blank lines

def dataset_name(rows):
    """Name the evaluation dataset after a hash of what the evaluation reads (id, question, answer key)."""
    canonical = json.dumps([[r["id"], r["question"], r["ground_truth_output"]] for r in rows],
                           ensure_ascii=False, separators=(",", ":"))  # stable text of the evaluated fields only
    return "AP_GOLDEN_" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:8].upper()  # 8 hex chars

def render_config(template_text, dataset, table, label, include_dataset=True):
    """Fill the YAML template's {dataset}, {table}, {label} placeholders.

    include_dataset=False drops the leading `dataset:` block: START fails with
    'already exists' when that dataset was created by an earlier run.
    """
    if not include_dataset:                                            # repeat run on an existing dataset
        template_text = template_text[template_text.index("evaluation:"):]  # keep evaluation: and metrics: only
    return template_text.replace("{dataset}", dataset).replace("{table}", table).replace("{label}", label)  # plain replace keeps YAML braces safe

def parse_results(rows, id_by_question):
    """Group GET_AI_EVALUATION_DATA rows into {qid: {metric: score}} plus {qid: error text}."""
    scores, errors = {}, {}                                            # outputs
    for r in rows:                                                     # one row per (record, metric)
        qid = id_by_question[r["INPUT"]]                               # KeyError names an unknown question
        scores.setdefault(qid, {})                                     # every returned question gets a score entry
        if r.get("METRIC_NAME") not in METRICS:                        # not computed yet (seen live) or an ungated metric
            continue                                                   # never becomes a metric key; filled with 0 below
        score = r["EVAL_AGG_SCORE"]                                    # judge score (0.0–1.0, verified live)
        try:
            status = json.loads(r.get("METRIC_STATUS") or "{}")        # judge outcome, e.g. {"code": 200, "message": "Ok"}
        except (TypeError, ValueError):                                # unreadable status → untrusted
            status = {}                                                # fail closed below
        if r.get("ERROR"):                                             # the agent failed on this record
            errors[qid] = str(r["ERROR"])[:200]                        # keep a short reason for the summary
            score = None                                               # count as 0
        elif status.get("code") != 200:                                # judge failed or no status: its score isn't trusted
            errors[qid] = f"{r['METRIC_NAME']}: {status.get('message', 'no judge status')}"[:200]  # reason for the summary
            score = None                                               # fail closed: count as 0
        scores[qid][r["METRIC_NAME"]] = float(score) if score is not None else 0.0  # errors count as 0
    for qid, metrics in scores.items():                                # every question must carry every gated metric
        for metric in METRICS:                                         # answer_correctness, logical_consistency
            if metric not in metrics:                                  # judge never scored it
                metrics[metric] = 0.0                                  # fail closed
                errors.setdefault(qid, f"{metric}: not scored")        # say why, unless a reason is already recorded
    return scores, errors                                              # per-question scores + error notes

# ── Live section ──────────────────────────────────────────────
TERMINAL_OK = {"COMPLETED", "PARTIALLY_COMPLETED"}           # run finished; partial = some records errored (scored 0)
TERMINAL_BAD = {"CANCELLED"}                                 # run will never produce scores

class RunFailed(Exception):
    """The evaluation run failed, was cancelled or timed out, or setup is missing (exit 2)."""

def wait_for_run(get_status, sleep=time.sleep, timeout_s=1500, interval_s=30):
    """Poll get_status() until the run finishes; raise RunFailed on cancellation or timeout."""
    waited = 0                                                     # seconds spent waiting
    while True:                                                    # until a terminal status
        status = get_status()                                      # current run status word
        if status in TERMINAL_OK:                                  # finished (INVOCATION_COMPLETED is NOT terminal)
            return status
        if status in TERMINAL_BAD:                                 # finished badly
            raise RunFailed(f"evaluation run ended with status {status}")
        if waited >= timeout_s:                                    # out of time
            raise RunFailed(f"evaluation run timed out after {waited}s (last status {status})")
        sleep(interval_s)                                          # wait before the next poll
        waited += interval_s                                       # count the wait

def connect():
    """Open a PAT session from environment variables (never printed)."""
    missing = [v for v in ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PAT") if not os.environ.get(v)]  # required settings
    if missing:                                                    # fail fast with a plain message
        raise RunFailed(f"missing environment variable(s): {', '.join(missing)}")
    return snowflake.connector.connect(                            # one session for the whole run
        account=os.environ["SNOWFLAKE_ACCOUNT"], user=os.environ["SNOWFLAKE_USER"],  # who connects
        authenticator="PROGRAMMATIC_ACCESS_TOKEN", token=os.environ["SNOWFLAKE_PAT"],  # PAT goes in token=, not password=
        role=os.environ.get("SNOWFLAKE_ROLE") or None,             # default role unless overridden
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "WH_COCO_PIPELINE"),  # agent SQL + evaluation tasks
        database="COCO", schema="EVAL")                            # dataset lands in the session schema (Task 1)

def load_dataset(cur, rows):
    """Replace the table's rows with the golden set (small table; full refresh keeps it exact)."""
    cur.execute(f"DELETE FROM {TABLE}")                            # drop old rows
    for r in rows:                                                 # 15 inserts, bound parameters
        truth = json.dumps({"ground_truth_output": r["ground_truth_output"]}, ensure_ascii=False)  # VARIANT payload
        cur.execute(f"INSERT INTO {TABLE} (question_id, category, query_text, ground_truth) "
                    "SELECT %s, %s, %s, PARSE_JSON(%s)",          # PARSE_JSON needs INSERT … SELECT
                    (r["id"], r["category"], r["question"], truth))

def put_config(cur, run_name, config_text):
    """Write the rendered config to a temp file, PUT it on the stage, return its stage path."""
    with tempfile.TemporaryDirectory() as tmp:                     # local copy to PUT
        path = Path(tmp) / f"{run_name}.yaml"                      # one config file per run
        path.write_text(config_text, encoding="utf-8")             # rendered YAML
        cur.execute(f"PUT 'file://{path.as_posix()}' {STAGE} AUTO_COMPRESS=FALSE OVERWRITE=TRUE")  # upload as-is
    return f"{STAGE}/{run_name}.yaml"                              # stage path for EXECUTE_AI_EVALUATION

def start_run(cur, run_name, dataset, template_text):
    """START with the dataset: block; if that dataset already exists, START again without it."""
    start_sql = "CALL EXECUTE_AI_EVALUATION('START', OBJECT_CONSTRUCT('run_name', %s), %s)"  # start statement
    config_ref = put_config(cur, run_name, render_config(template_text, dataset, TABLE, run_name))  # first try creates the dataset
    try:
        cur.execute(start_sql, (run_name, config_ref))            # start the run
    except snowflake.connector.errors.ProgrammingError as exc:     # Task 1: 210007 "already exists" on repeat runs
        if "already exists" not in str(exc):                       # any other error is real
            raise
        reuse = render_config(template_text, dataset, TABLE, run_name, include_dataset=False)  # no dataset: block
        config_ref = put_config(cur, run_name, reuse)              # replace the staged config
        cur.execute(start_sql, (run_name, config_ref))            # start against the existing dataset
    return config_ref                                              # STATUS calls need the same config path

def run_evaluation(cur, run_name, dataset, template_text):
    """Start the run, poll until done, return GET_AI_EVALUATION_DATA rows as dicts."""
    config_ref = start_run(cur, run_name, dataset, template_text)  # dataset created or reused
    def status():                                                  # one STATUS poll
        cur.execute("CALL EXECUTE_AI_EVALUATION('STATUS', OBJECT_CONSTRUCT('run_name', %s), %s)", (run_name, config_ref))
        columns = [d[0] for d in cur.description]                  # RUN_NAME, AGENT_NAME, AGENT_TYPE, STATUS, STATUS_DETAILS
        return str(dict(zip(columns, cur.fetchone()))["STATUS"]).upper()  # e.g. COMPUTATION_IN_PROGRESS
    final = wait_for_run(status)                                   # raises RunFailed on cancel/timeout
    print(f"evaluation run {run_name}: {final}")                   # CI log
    cur.execute("SELECT * FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA('COCO', 'AGENT', 'AP_INVOICE_AGENT', 'CORTEX AGENT', %s))",
                (run_name,))                                       # agent's database + schema, run name
    columns = [d[0] for d in cur.description]                      # column names
    return [dict(zip(columns, row)) for row in cur.fetchall()]     # rows as dicts

def gate_and_report(rows, scores, errors, args):
    """Gate scores against the baseline file, print + append the summary; return 0 pass, 1 regression, 2 no baseline."""
    baseline_path = Path(args.baseline)                            # committed baseline
    if not baseline_path.exists():                                 # no baseline yet = setup problem, not quality
        print(f"infrastructure problem: baseline {baseline_path} not found; record one first", file=sys.stderr)
        return 2
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))  # committed baseline
    result = evaluate_gate(scores, baseline)                       # pass/fail
    text = render_summary(scores, baseline, result, {r["id"]: r["category"] for r in rows}, errors)  # markdown
    print(text)                                                    # CI log
    if args.summary:                                               # GitHub step summary
        with open(args.summary, "a", encoding="utf-8") as handle:  # append, UTF-8
            handle.write(text)
    return 0 if result.passed else 1                               # quality verdict

def main(argv=None):
    """CLI: run, gate (or record a baseline), write summary + results; return 0/1/2."""
    parser = argparse.ArgumentParser(description=__doc__)          # help text = module docstring
    parser.add_argument("--summary")                               # markdown file to append (CI: $GITHUB_STEP_SUMMARY)
    parser.add_argument("--baseline", default=str(BASELINE_PATH))  # baseline file to gate against / write
    parser.add_argument("--record-baseline", action="store_true")  # write the baseline instead of gating
    parser.add_argument("--scores-file")                           # re-gate a saved results JSON (no live run, no credits)
    args = parser.parse_args(argv)                                 # parsed flags
    rows = load_golden()                                           # golden questions
    if args.scores_file:                                           # offline re-gate of an earlier run
        saved = json.loads(Path(args.scores_file).read_text(encoding="utf-8"))  # {"scores": ..., "errors": ...}
        return gate_and_report(rows, saved["scores"], saved["errors"], args)    # same gate path as a live run
    dataset = dataset_name(rows)                                   # content-hashed dataset name
    sha = os.environ.get("GITHUB_SHA", "local")[:8]                # commit (or "local")
    suffix = os.environ.get("GITHUB_RUN_ID") or datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")  # unique per run
    run_name = f"ci-{sha}-{suffix}"                                # evaluation run name (never reused)
    try:
        with connect() as conn:                                    # PAT session; the only network section
            cur = conn.cursor()                                    # one cursor
            load_dataset(cur, rows)                                # refresh the source table
            raw = run_evaluation(cur, run_name, dataset, TEMPLATE_PATH.read_text(encoding="utf-8"))  # live run
    except (RunFailed, snowflake.connector.errors.Error) as exc:   # anything that isn't a quality verdict
        print(f"infrastructure problem: {exc}", file=sys.stderr)   # plain message for the CI log
        return 2
    scores, errors = parse_results(raw, {r["question"]: r["id"] for r in rows})  # per-question scores
    RESULTS_DIR.mkdir(exist_ok=True)                               # gitignored output dir
    out = {"run_name": run_name, "dataset": dataset, "scores": scores, "errors": errors, "means": means(scores)}  # run record
    (RESULTS_DIR / f"native_{run_name}.json").write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
    if args.record_baseline:                                       # write the baseline, don't gate
        baseline = {"recorded": datetime.date.today().isoformat(), "run_name": run_name,
                    "means": means(scores), "per_question": scores}  # what later runs compare against
        Path(args.baseline).write_text(json.dumps(baseline, indent=2), encoding="utf-8")
        print(f"baseline recorded: {baseline['means']}  errors: {errors}")  # visible in the CI log
        return 0
    return gate_and_report(rows, scores, errors, args)             # gate this run

if __name__ == "__main__":
    sys.exit(main())                                               # exit code for CI

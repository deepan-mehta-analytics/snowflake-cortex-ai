"""Run a .sql file against Snowflake via the PAT and fail on any check row whose OUTCOME is 'FAIL'."""
# ── Imports ───────────────────────────────────────────────────
import argparse                                                   # command-line options
import io                                                         # wrap SQL text as a stream for execute_stream
import sys                                                        # exit codes
import time                                                       # wait between --repeat attempts
import tomllib                                                    # read config/connection.toml
from pathlib import Path                                          # resolve repo-relative paths
import snowflake.connector                                        # Snowflake Python connector (requirements-dev.txt)

# ── Paths ─────────────────────────────────────────────────────
REPO_ROOT = Path(__file__).resolve().parent.parent                # scripts/ → repo root
CONFIG_PATH = REPO_ROOT / "config" / "connection.toml"            # gitignored connection file


def load_settings(connection_name):                               # read one [connections.<name>] block
    with open(CONFIG_PATH, "rb") as config_file:                  # TOML must be opened in binary mode
        return tomllib.load(config_file)["connections"][connection_name]  # dict of connection settings


def substitute_tokens(sql_text, assignments):                     # replace <KEY> tokens with --set values
    for assignment in assignments:                                # each KEY=VALUE pair
        key, value = assignment.split("=", 1)                     # split on the first '=' only
        sql_text = sql_text.replace(f"<{key}>", value)            # literal token replacement
    return sql_text                                               # text ready to execute


def run_once(connection, sql_text):                               # execute every statement, return the FAIL count
    failures = 0                                                  # FAIL rows seen in this pass
    for cursor in connection.execute_stream(io.StringIO(sql_text), remove_comments=False):  # one cursor per statement
        columns = [column[0].upper() for column in (cursor.description or [])]  # result column names
        rows = cursor.fetchall() if cursor.description else []    # statements like USE return no rows
        print(f"-- {cursor.query.strip().splitlines()[0][:100]}")  # first line of the statement, for context
        for row in rows:                                          # print every result row
            record = dict(zip(columns, row))                      # column name → value
            print("   ", record)                                  # one line per row
            if record.get("OUTCOME") == "FAIL":                   # a failed check
                failures += 1                                     # count it
    return failures                                               # 0 means every check passed


def main():                                                       # CLI entry point
    parser = argparse.ArgumentParser(description=__doc__)         # help text = module docstring
    parser.add_argument("sql_file")                               # path to the .sql file to run
    parser.add_argument("--connection", default="default")        # [connections.<name>] block to use
    parser.add_argument("--set", action="append", default=[], dest="assignments")  # KEY=VALUE token substitutions
    parser.add_argument("--repeat", type=int, default=1)          # attempts until no FAIL rows (for scheduled results)
    parser.add_argument("--interval", type=int, default=120)      # seconds between attempts
    args = parser.parse_args()                                    # parse the command line
    sql_text = substitute_tokens(Path(args.sql_file).read_text(encoding="utf-8"), args.assignments)  # load + substitute
    settings = load_settings(args.connection)                     # connection settings (token never printed)
    connection = snowflake.connector.connect(                     # open one session for the whole file
        account=settings["account"], user=settings["user"],       # account + login
        authenticator="PROGRAMMATIC_ACCESS_TOKEN", token=settings["token"],  # PAT goes in token=, not password=
        role=settings["role"], warehouse=settings["warehouse"], database=settings.get("database"))  # SYSADMIN context
    try:                                                          # always close the session
        for attempt in range(1, args.repeat + 1):                 # one or more passes
            failures = run_once(connection, sql_text)             # run every statement
            print(f"== attempt {attempt}: {failures} FAIL row(s)")  # pass summary
            if failures == 0 or attempt == args.repeat:           # done: passed, or out of attempts
                break                                             # stop retrying
            time.sleep(args.interval)                             # wait before the next attempt
    finally:
        connection.close()                                        # end the session
    sys.exit(1 if failures else 0)                                # non-zero exit when any check failed


if __name__ == "__main__":                                        # only when run as a script
    main()                                                        # run the CLI

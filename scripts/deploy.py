"""Deploy the project's SQL in manifest order through the PAT (no Snowflake CLI needed).

--plan   prints every statement of the `deploy` files and lists `checklist` files; runs nothing.
--apply  runs the `deploy` files in order as the connection's role (SYSADMIN) and stops at the first error.
`checklist` files are never executed here — see docs/deploy_checklist.md.
"""
# ── Imports ───────────────────────────────────────────────────
import argparse                                                   # command-line options
import io                                                         # wrap SQL text as a stream for the splitter
import sys                                                        # exit codes + import path
from pathlib import Path                                          # repo-relative paths

import snowflake.connector                                        # Snowflake Python connector (requirements-dev.txt)
from snowflake.connector.util_text import split_statements as _split  # the connector's own $$-aware splitter

sys.path.insert(0, str(Path(__file__).resolve().parent))          # make sibling scripts importable
from run_sql_checks import load_settings                          # noqa: E402 — reuse the PAT settings reader

# ── Paths ─────────────────────────────────────────────────────
REPO_ROOT = Path(__file__).resolve().parent.parent                # scripts/ → repo root
SQL_ROOT = REPO_ROOT / "sql"                                      # all SQL lives here
MANIFEST = SQL_ROOT / "deploy_manifest.txt"                       # ordered deploy list
TAGS = {"deploy", "checklist"}                                    # allowed manifest tags


# ── Manifest ──────────────────────────────────────────────────
def read_manifest(path=MANIFEST):
    """Return [(tag, path relative to sql/)] in file order; raise on a bad tag or missing file."""
    entries = []                                                  # parsed rows
    for number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), start=1):  # 1-based line numbers
        text = line.split("#", 1)[0].strip()                      # drop comments + whitespace
        if not text:                                              # blank or comment-only line
            continue                                              # skip it
        parts = text.split()                                      # tag and path
        if len(parts) != 2 or parts[0] not in TAGS:               # malformed row
            raise ValueError(f"manifest line {number}: expected '<deploy|checklist> <path>', got {text!r}")
        tag, rel = parts                                          # unpack
        if not (SQL_ROOT / rel).is_file():                        # path must exist
            raise FileNotFoundError(f"manifest line {number}: sql/{rel} not found")
        entries.append((tag, rel))                                # keep it
    return entries                                                # ordered entries


# ── Statements ────────────────────────────────────────────────
def split_statements(sql_text):
    """Split SQL into executable statements ($$ bodies kept whole, comments removed, blanks dropped)."""
    pieces = _split(io.StringIO(sql_text), remove_comments=True)  # yields (statement, is_put_or_get)
    return [statement.strip() for statement, _ in pieces if statement.strip()]  # non-empty statements only


def statements_for(rel):
    """Statements of one manifest file."""
    return split_statements((SQL_ROOT / rel).read_text(encoding="utf-8"))  # read + split


# ── Plan ──────────────────────────────────────────────────────
def plan(entries):
    """Print what --apply would run; return the number of deploy statements."""
    total = 0                                                     # deploy statements counted
    for tag, rel in entries:                                      # manifest order
        if tag == "checklist":                                    # never executed by this script
            print(f"MANUAL     {rel}   (see docs/deploy_checklist.md)")  # shown, not run
            continue                                              # next entry
        statements = statements_for(rel)                          # this file's statements
        print(f"DEPLOY     {rel}   ({len(statements)} statements)")  # file header
        for index, statement in enumerate(statements, start=1):   # each statement
            print(f"   {index:>3}. {statement.splitlines()[0][:110]}")  # first line only
        total += len(statements)                                  # running count
    print(f"== {total} deploy statement(s); nothing was executed")  # dry-run footer
    return total                                                  # for tests / callers


# ── Apply ─────────────────────────────────────────────────────
def apply(entries, cursor):
    """Run deploy files in order; stop at the first error. Return 0 on success, 1 on failure."""
    for tag, rel in entries:                                      # manifest order
        if tag != "deploy":                                       # checklist files are manual
            continue                                              # skip
        for index, statement in enumerate(statements_for(rel), start=1):  # each statement
            try:
                cursor.execute(statement)                         # run it
            except snowflake.connector.errors.Error as exc:       # any Snowflake error
                print(f"FAILED {rel} statement {index}: {statement.splitlines()[0][:110]}")  # where
                print(f"       {exc}")                            # why
                return 1                                          # stop: nothing after this runs
        print(f"OK         {rel}")                                # file done
    print("== deploy complete; now run the checklist steps after 'deploy' (90_grants.sql first)")  # next steps
    return 0                                                      # success


# ── CLI ───────────────────────────────────────────────────────
def main(argv=None):
    """Parse flags, then plan or apply."""
    parser = argparse.ArgumentParser(description=__doc__)         # help text = module docstring
    mode = parser.add_mutually_exclusive_group(required=True)     # exactly one mode
    mode.add_argument("--plan", action="store_true")              # dry run
    mode.add_argument("--apply", action="store_true")             # execute
    parser.add_argument("--connection", default="default")        # [connections.<name>] block
    args = parser.parse_args(argv)                                # parse
    entries = read_manifest()                                     # validate the manifest first
    if args.plan:                                                 # dry run needs no connection
        plan(entries)                                             # print it
        return 0                                                  # done
    settings = load_settings(args.connection)                     # PAT settings (token never printed)
    connection = snowflake.connector.connect(                     # one session for the whole deploy
        account=settings["account"], user=settings["user"],       # who
        authenticator="PROGRAMMATIC_ACCESS_TOKEN", token=settings["token"],  # PAT in token=
        role=settings["role"], warehouse=settings["warehouse"])   # SYSADMIN + project warehouse
    try:
        return apply(entries, connection.cursor())                # run
    finally:
        connection.close()                                        # always end the session


if __name__ == "__main__":                                        # script entry point
    sys.exit(main())                                              # exit code for shells/CI

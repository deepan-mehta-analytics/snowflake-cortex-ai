"""Offline tests for scripts/deploy.py (no Snowflake connection)."""

# ── Imports ───────────────────────────────────────────────────
import sys                                                   # extend sys.path for scripts/
from pathlib import Path                                     # temp manifest files

import pytest                                                # raises + tmp_path fixtures
import snowflake.connector                                   # error class the runner catches

ROOT = Path(__file__).resolve().parent.parent                # repo root
sys.path.insert(0, str(ROOT / "scripts"))                    # make deploy importable
from deploy import apply, plan, read_manifest, split_statements  # noqa: E402 — functions under test

# ── Manifest ──────────────────────────────────────────────────
def test_real_manifest_parses_and_every_file_exists():
    """The committed manifest names only real files, tagged deploy or checklist."""
    entries = read_manifest()                                # the real sql/deploy_manifest.txt
    assert entries                                           # not empty
    assert {tag for tag, _ in entries} == {"deploy", "checklist"}  # both kinds present
    for _, rel in entries:                                   # every listed file
        assert (ROOT / "sql" / rel).is_file(), rel           # exists on disk

def test_manifest_rejects_unknown_tag(tmp_path):
    """A typo in the tag must stop the deploy before anything runs."""
    bad = tmp_path / "m.txt"                                 # temp manifest
    bad.write_text("deplyo 01_bronze_sources/01_sap_ap_invoices.sql\n", encoding="utf-8")  # misspelt tag
    with pytest.raises(ValueError, match="line 1"):          # names the offending line
        read_manifest(bad)

def test_manifest_rejects_missing_file(tmp_path):
    """A path that doesn't exist must stop the deploy before anything runs."""
    bad = tmp_path / "m.txt"                                 # temp manifest
    bad.write_text("deploy 99_nowhere/missing.sql\n", encoding="utf-8")  # no such file
    with pytest.raises(FileNotFoundError, match="missing.sql"):  # names the file
        read_manifest(bad)

def test_manifest_ignores_comments_and_blank_lines(tmp_path):
    """Comment lines, inline comments and blank lines are skipped."""
    ok = tmp_path / "m.txt"                                  # temp manifest
    ok.write_text("# header\n\ndeploy 06_ci/01_eval_objects.sql   # eval objects\n", encoding="utf-8")
    assert read_manifest(ok) == [("deploy", "06_ci/01_eval_objects.sql")]  # one clean entry

# ── Splitting + plan ──────────────────────────────────────────
def test_split_keeps_dollar_quoted_body_whole():
    """A $$ … $$ body containing semicolons stays one statement."""
    sql = "SELECT 1;\nCREATE PROCEDURE p() RETURNS INT LANGUAGE SQL AS $$ BEGIN RETURN 1; END; $$;\nSELECT 2;"
    statements = split_statements(sql)                       # split the text
    assert len(statements) == 3                              # not 5
    assert "RETURN 1; END;" in statements[1]                 # body intact

def test_plan_counts_only_deploy_statements(capsys):
    """--plan prints checklist files as manual and counts only deploy statements."""
    entries = [("checklist", "90_grants.sql"), ("deploy", "06_ci/01_eval_objects.sql")]  # one of each
    count = plan(entries)                                    # dry run
    out = capsys.readouterr().out                            # printed plan
    assert "MANUAL" in out and "90_grants.sql" in out        # checklist shown, not run
    assert count == len(split_statements((ROOT / "sql" / "06_ci/01_eval_objects.sql").read_text(encoding="utf-8")))  # deploy statements only

# ── Apply ─────────────────────────────────────────────────────
class FakeCursor:
    """Records statements; raises on the statement containing `fail_on`."""
    def __init__(self, fail_on=None):
        self.ran = []                                        # statements executed so far
        self.fail_on = fail_on                               # substring that triggers an error
    def execute(self, statement):
        if self.fail_on and self.fail_on in statement:       # simulated Snowflake failure
            raise snowflake.connector.errors.ProgrammingError("simulated failure")
        self.ran.append(statement)                           # success: remember it

def test_apply_skips_checklist_and_runs_deploy_in_order():
    """Checklist files never execute; deploy files run in manifest order."""
    cursor = FakeCursor()                                    # never fails
    entries = [("checklist", "90_grants.sql"), ("deploy", "06_ci/01_eval_objects.sql")]
    assert apply(entries, cursor) == 0                       # success
    assert cursor.ran and all("90_grants" not in s for s in cursor.ran)  # checklist untouched
    assert cursor.ran[0].upper().startswith("USE ROLE SYSADMIN")  # first statement of 06_ci/01

def test_apply_stops_at_first_error_and_names_it(capsys):
    """A failing statement stops the run and prints file + statement number."""
    cursor = FakeCursor(fail_on="CREATE TABLE")              # 06_ci/01 statement 3 creates the table
    entries = [("deploy", "06_ci/01_eval_objects.sql"), ("deploy", "06_ci/01_eval_objects.sql")]
    assert apply(entries, cursor) == 1                       # failure exit
    out = capsys.readouterr().out                            # printed report
    assert "FAILED 06_ci/01_eval_objects.sql statement 3" in out  # exact location
    assert len(cursor.ran) == 2                              # nothing after the failure ran

# ── Grants placement ──────────────────────────────────────────
def test_deploy_files_hold_no_object_grants():
    """Object grants to the MCP/CI roles live in 90_grants.sql, never in deploy-tagged files."""
    for tag, rel in read_manifest():                         # every manifest entry
        if tag != "deploy":                                  # only files deploy.py runs
            continue
        text = (ROOT / "sql" / rel).read_text(encoding="utf-8").upper()  # case-insensitive scan
        assert "TO ROLE MCP_CLAUDE_ROLE" not in text, rel    # MCP grants belong in 90
        assert "TO ROLE CI_EVAL_ROLE" not in text, rel       # CI grants belong in 90

def test_role_scripts_hold_no_object_grants_and_no_pat():
    """Role/user scripts keep only role, user and account-level grants (re-runnable on an empty account)."""
    for rel in ("04_mcp/00_mcp_role_and_user.sql", "06_ci/00_ci_eval_role_and_user.sql"):
        text = (ROOT / "sql" / rel).read_text(encoding="utf-8").upper()  # scan
        for needle in (" ON DYNAMIC TABLE ", " ON SEMANTIC VIEW ", " ON CORTEX SEARCH SERVICE ", " ON AGENT ", " ON STAGE ", " ON TABLE "):
            assert needle not in text, f"{rel}: {needle.strip()}"  # moved to 90_grants.sql
        assert "ADD PROGRAMMATIC ACCESS TOKEN" not in text, rel  # one-time step lives in the checklist

# ── Console encoding (Windows) ────────────────────────────────
def test_sql_runner_prints_box_drawing_on_a_cp1252_console(monkeypatch):
    """run_sql_checks prints '═' headers; a cp1252 console must not crash it (seen 2026-10-04, Task 2)."""
    import io                                                # build a cp1252 stdout
    import run_sql_checks                                    # module under test (scripts/ is on sys.path)
    monkeypatch.setattr(sys, "stdout", io.TextIOWrapper(io.BytesIO(), encoding="cp1252"))  # Windows-style console
    run_sql_checks.use_utf8_output()                         # what main() calls first
    print("-- ══════ header ══════")                         # must not raise UnicodeEncodeError

# ── Reporting date + re-runnability ───────────────────────────
def test_overdue_logic_never_uses_current_date():
    """Overdue is measured against silver.reporting_calendar, never the wall clock."""
    for rel in ("02_silver/02_dt_vendor_invoice_summary.sql", "03_semantic_view/01_sv_ap_analytics.sql"):
        code = "\n".join(line.split("--", 1)[0] for line in (ROOT / "sql" / rel).read_text(encoding="utf-8").splitlines())  # ignore comments
        assert "CURRENT_DATE" not in code.upper(), rel           # no wall-clock dependency
        assert "REPORTING_CALENDAR" in code.upper(), rel         # uses the as-of table

def test_reporting_date_is_2025_06_30_everywhere():
    """The calendar row, agent spec and Snowflake CLI copy all name the same as-of date."""
    for rel in ("sql/02_silver/00_reporting_calendar.sql", "sql/04_mcp/00b_fix_ap_invoice_agent.sql", "cortex_project/ap_invoice_agent.agent.yaml"):
        assert "2025-06-30" in (ROOT / rel).read_text(encoding="utf-8"), rel  # single agreed date

def test_agent_file_splits_into_create_and_alter():
    """00b creates the agent if missing, then replaces its live spec — both $$ bodies intact."""
    statements = [s.upper() for s in split_statements((ROOT / "sql/04_mcp/00b_fix_ap_invoice_agent.sql").read_text(encoding="utf-8"))]
    create = [s for s in statements if s.startswith("CREATE AGENT IF NOT EXISTS")]  # first-run path
    alter = [s for s in statements if "MODIFY LIVE VERSION SET SPECIFICATION" in s]  # every-run path
    assert len(create) == 1 and len(alter) == 1                  # exactly one of each
    assert "AP_INVOICE_SEARCH" in alter[0] and "2025-06-30" in alter[0]  # whole spec in one statement

def test_agent_computes_totals_in_sql_everywhere():
    """The agent must total in SQL, not by hand: q11 runs summed USD in prose and got it wrong."""
    rule = "never add numbers up yourself"                       # wording shared by both copies
    for rel in ("sql/04_mcp/00b_fix_ap_invoice_agent.sql", "cortex_project/ap_invoice_agent.agent.yaml"):
        assert rule in (ROOT / rel).read_text(encoding="utf-8"), rel  # live spec and CLI copy agree

def test_guardrail_attach_leaves_schedule_off():
    """Re-attaching the BR-004 DMF on deploy must not restart daily serverless spend."""
    statements = ["".join(s.split()).upper().rstrip(";") for s in split_statements((ROOT / "sql/05_guardrails/03_attach_to_silver.sql").read_text(encoding="utf-8"))]  # whitespace + trailing ';' removed
    assert statements[-1].endswith("SETDATA_METRIC_SCHEDULE=''")  # last action turns the schedule off

# ── Checklist ─────────────────────────────────────────────────
def test_checklist_covers_every_checklist_entry():
    """Every checklist-tagged manifest file is a step in docs/deploy_checklist.md."""
    text = (ROOT / "docs" / "deploy_checklist.md").read_text(encoding="utf-8")  # the checklist
    for tag, rel in read_manifest():                         # every manifest entry
        if tag == "checklist":                               # manual steps only
            assert rel in text, rel                          # documented

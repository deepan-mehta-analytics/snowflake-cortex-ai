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

-- ══════════════════════════════════════════════════════════════════
-- 91 — check the MCP and CI roles still hold every object grant
-- ══════════════════════════════════════════════════════════════════
-- Read-only. Run: python scripts/run_sql_checks.py sql/91_check_grants.sql
-- One row per expected grant: OUTCOME PASS / FAIL (exit 1 on any FAIL).
-- Matches on privilege + fully-qualified name (granted_on labels vary by type).

-- ── MCP role ─────────────────────────────────────────────────────
SHOW GRANTS TO ROLE mcp_claude_role;                                  -- current grants of the MCP role
WITH actual AS (                                                      -- rows from the SHOW above
    SELECT "privilege" AS privilege, "name" AS name                   -- privilege + object name
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))                          -- result of the previous statement
), expected AS (                                                      -- what 90_grants.sql + 04_mcp/01 grant
    SELECT column1 AS privilege, column2 AS name FROM VALUES          -- one row per grant
        ('USAGE', 'WH_COCO_PIPELINE'), ('USAGE', 'COCO'),
        ('USAGE', 'COCO.AGENT'), ('USAGE', 'COCO.SEMANTIC'), ('USAGE', 'COCO.SILVER'), ('USAGE', 'COCO.MCP'),
        ('USAGE', 'COCO.AGENT.AP_INVOICE_AGENT'), ('USAGE', 'COCO.AGENT.AP_INVOICE_SEARCH'),
        ('SELECT', 'COCO.SEMANTIC.SV_AP_ANALYTICS'),
        ('SELECT', 'COCO.SILVER.DT_SILVER_AP_INVOICES'), ('SELECT', 'COCO.SILVER.DT_VENDOR_INVOICE_SUMMARY'),
        ('SELECT', 'COCO.SILVER.REPORTING_CALENDAR'),
        ('USAGE', 'COCO.MCP.AP_INVOICE_MCP')
)
SELECT 'mcp_claude_role ' || e.privilege || ' ' || e.name AS CHECK_NAME,  -- one check per grant
       'granted' AS EXPECTED,                                         -- what we want
       IFF(a.name IS NULL, 'missing', 'granted') AS ACTUAL,           -- what is there
       IFF(a.name IS NULL, 'FAIL', 'PASS') AS OUTCOME                 -- verdict
FROM expected e                                                       -- every expected grant
LEFT JOIN actual a ON a.privilege = e.privilege AND a.name = e.name   -- present?
ORDER BY OUTCOME, CHECK_NAME;                                         -- FAILs first

-- ── CI role ──────────────────────────────────────────────────────
SHOW GRANTS TO ROLE ci_eval_role;                                     -- current grants of the CI role
WITH actual AS (                                                      -- rows from the SHOW above
    SELECT "privilege" AS privilege, "name" AS name                   -- privilege + object name
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))                          -- result of the previous statement
), expected AS (                                                      -- what 90_grants.sql grants
    SELECT column1 AS privilege, column2 AS name FROM VALUES          -- one row per grant
        ('USAGE', 'WH_COCO_PIPELINE'), ('USAGE', 'COCO'),
        ('USAGE', 'COCO.SILVER'), ('USAGE', 'COCO.SEMANTIC'), ('USAGE', 'COCO.AGENT'), ('USAGE', 'COCO.EVAL'),
        ('SELECT', 'COCO.SILVER.DT_SILVER_AP_INVOICES'), ('SELECT', 'COCO.SILVER.DT_VENDOR_INVOICE_SUMMARY'),
        ('SELECT', 'COCO.SILVER.REPORTING_CALENDAR'),
        ('SELECT', 'COCO.SEMANTIC.SV_AP_ANALYTICS'), ('USAGE', 'COCO.AGENT.AP_INVOICE_SEARCH'),
        ('USAGE', 'COCO.AGENT.AP_INVOICE_AGENT'), ('MONITOR', 'COCO.AGENT.AP_INVOICE_AGENT'),
        ('SELECT', 'COCO.EVAL.GOLDEN_QUESTIONS'), ('INSERT', 'COCO.EVAL.GOLDEN_QUESTIONS'), ('DELETE', 'COCO.EVAL.GOLDEN_QUESTIONS'),
        ('READ', 'COCO.EVAL.CONFIG_STAGE'), ('WRITE', 'COCO.EVAL.CONFIG_STAGE'),
        ('CREATE DATASET', 'COCO.EVAL'), ('CREATE TASK', 'COCO.EVAL'), ('CREATE FILE FORMAT', 'COCO.EVAL')
)
SELECT 'ci_eval_role ' || e.privilege || ' ' || e.name AS CHECK_NAME,  -- one check per grant
       'granted' AS EXPECTED,                                         -- what we want
       IFF(a.name IS NULL, 'missing', 'granted') AS ACTUAL,           -- what is there
       IFF(a.name IS NULL, 'FAIL', 'PASS') AS OUTCOME                 -- verdict
FROM expected e                                                       -- every expected grant
LEFT JOIN actual a ON a.privilege = e.privilege AND a.name = e.name   -- present?
ORDER BY OUTCOME, CHECK_NAME;                                         -- FAILs first

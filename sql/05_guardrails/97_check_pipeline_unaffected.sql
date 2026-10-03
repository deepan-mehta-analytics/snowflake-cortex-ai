-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 97 — the real pipeline is unchanged and healthy
-- ══════════════════════════════════════════════════════════════════
SELECT 'silver_row_count' AS check_name, 50 AS expected,
       (SELECT COUNT(*) FROM coco.silver.dt_silver_ap_invoices) AS actual,                    -- still 50 invoices
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;
SELECT 'silver_one_dmf_association' AS check_name, 1 AS expected,
       (SELECT COUNT(*) FROM TABLE(coco.information_schema.data_metric_function_references(
            ref_entity_name => 'coco.silver.dt_silver_ap_invoices', ref_entity_domain => 'table'))) AS actual,  -- only BR-004
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;
SELECT 'silver_refresh_healthy' AS check_name, 'SUCCEEDED' AS expected,
       (SELECT state FROM TABLE(coco.information_schema.dynamic_table_refresh_history(
            name => 'COCO.SILVER.DT_SILVER_AP_INVOICES'))
         ORDER BY refresh_start_time DESC LIMIT 1) AS actual,                                  -- latest refresh
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;
SHOW GRANTS TO ROLE mcp_claude_role;                                                           -- MCP role grants
SELECT 'mcp_role_no_guardrails_access' AS check_name, 0 AS expected,
       (SELECT COUNT(*) FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "name" ILIKE 'COCO.GUARDRAILS%') AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;

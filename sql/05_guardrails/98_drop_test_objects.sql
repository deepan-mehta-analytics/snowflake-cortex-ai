-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 98 — remove BR-004 test objects (rebuild with 90)
-- ══════════════════════════════════════════════════════════════════
USE ROLE SYSADMIN;                                                    -- owner of the test schema
ALTER TABLE coco.guardrails_test.silver_invoices_test_synthetic
    DROP DATA METRIC FUNCTION coco.guardrails.count_invoices_over_usd_500k
    ON (source_system, invoice_id, invoice_amount, currency_code, invoice_date,
        TABLE(coco.guardrails.fx_rates(currency_code, rate_date, usd_per_unit)));  -- detach first (DMFs can't drop while attached)
DROP SCHEMA IF EXISTS coco.guardrails_test;                           -- tables, views, test alert, test task
SELECT 'test_schema_gone' AS check_name, 0 AS expected,
       (SELECT COUNT(*) FROM coco.information_schema.schemata WHERE schema_name = 'GUARDRAILS_TEST') AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;

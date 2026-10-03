-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 94 — recorded expectation results (needs a scheduled run)
-- ══════════════════════════════════════════════════════════════════
-- Run with --repeat 8 --interval 120: results appear only after a scheduled run.

-- ── Fixture: violated (3 > 2) ────────────────────────────────────
SELECT 'fixture_expectation_violated' AS check_name, TRUE AS expected,
       (SELECT expectation_violated
          FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS(
                 REF_ENTITY_NAME => 'COCO.GUARDRAILS_TEST.SILVER_INVOICES_TEST_SYNTHETIC',
                 REF_ENTITY_DOMAIN => 'TABLE'))
         WHERE expectation_name = 'HIGH_VALUE_COUNT_WITHIN_TOLERANCE'
         ORDER BY measurement_time DESC LIMIT 1) AS actual,                                    -- latest result
       IFF(actual IS NOT DISTINCT FROM expected, 'PASS', 'FAIL') AS outcome;                   -- NULL (no run yet) = FAIL
SELECT 'fixture_measured_value' AS check_name, 3 AS expected,
       (SELECT value::NUMBER
          FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS(
                 REF_ENTITY_NAME => 'COCO.GUARDRAILS_TEST.SILVER_INVOICES_TEST_SYNTHETIC',
                 REF_ENTITY_DOMAIN => 'TABLE'))
         WHERE expectation_name = 'HIGH_VALUE_COUNT_WITHIN_TOLERANCE'
         ORDER BY measurement_time DESC LIMIT 1) AS actual,                                    -- DMF value recorded
       IFF(actual IS NOT DISTINCT FROM expected, 'PASS', 'FAIL') AS outcome;

-- ── Silver: passing (0 <= 2) ─────────────────────────────────────
SELECT 'silver_expectation_passing' AS check_name, FALSE AS expected,
       (SELECT expectation_violated
          FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS(
                 REF_ENTITY_NAME => 'COCO.SILVER.DT_SILVER_AP_INVOICES',
                 REF_ENTITY_DOMAIN => 'TABLE'))
         WHERE expectation_name = 'HIGH_VALUE_COUNT_WITHIN_TOLERANCE'
         ORDER BY measurement_time DESC LIMIT 1) AS actual,                                    -- latest result
       IFF(actual IS NOT DISTINCT FROM expected, 'PASS', 'FAIL') AS outcome;

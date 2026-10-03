-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 96b — did the test task stop everything? (read-only, repeatable)
-- ══════════════════════════════════════════════════════════════════
SHOW ALERTS LIKE 'ALERT_TEST_HIGH_VALUE_VOLUME' IN SCHEMA coco.guardrails_test;               -- read alert state
SELECT 'test_alert_suspended' AS check_name, 'suspended' AS expected,
       (SELECT "state" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;
SHOW TASKS LIKE 'TASK_TEST_AUTO_STOP' IN SCHEMA coco.guardrails_test;                          -- read task state
SELECT 'test_task_suspended' AS check_name, 'suspended' AS expected,
       (SELECT "state" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;
SHOW PARAMETERS LIKE 'DATA_METRIC_SCHEDULE' IN TABLE coco.guardrails_test.silver_invoices_test_synthetic;  -- read schedule
SELECT 'test_schedule_cleared' AS check_name, '' AS expected,
       (SELECT "value" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))) AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;

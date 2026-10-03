-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 95b — did the test alert's action run? (read-only, repeatable)
-- ══════════════════════════════════════════════════════════════════
SELECT 'test_alert_triggered' AS check_name, 'TRIGGERED' AS expected,
       (SELECT state FROM TABLE(coco.information_schema.alert_history(
              scheduled_time_range_start => DATEADD('minute', -30, CURRENT_TIMESTAMP())))
         WHERE name = 'ALERT_TEST_HIGH_VALUE_VOLUME' AND state <> 'SCHEDULED'
         ORDER BY scheduled_time DESC LIMIT 1) AS actual,                                      -- latest run state
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;

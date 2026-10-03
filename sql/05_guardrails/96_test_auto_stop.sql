-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 96 — prove the auto-stop body on test objects
-- ══════════════════════════════════════════════════════════════════
-- Runs the same 3 statements as 06 against the fixture, its test alert and
-- a test task. Check the outcome with 96b (read-only, repeatable).
USE ROLE SYSADMIN;                                                    -- owner of the test objects
ALTER TABLE coco.guardrails_test.silver_invoices_test_synthetic SET DATA_METRIC_SCHEDULE = '60 MINUTE';  -- something to stop
ALTER ALERT coco.guardrails_test.alert_test_high_value_volume RESUME; -- something to suspend
CREATE OR REPLACE TASK coco.guardrails_test.task_test_auto_stop       -- serverless test task
    SCHEDULE = 'USING CRON 0 0 1 1 * UTC'                             -- far-off; run by hand
AS
EXECUTE IMMEDIATE $$
BEGIN
    ALTER ALERT coco.guardrails_test.alert_test_high_value_volume SUSPEND;                          -- 1: stop the alert
    ALTER TABLE coco.guardrails_test.silver_invoices_test_synthetic SET DATA_METRIC_SCHEDULE = '';  -- 2: stop the DMF runs
    ALTER TASK coco.guardrails_test.task_test_auto_stop SUSPEND;                                    -- 3: stop itself
END;
$$;
ALTER TASK coco.guardrails_test.task_test_auto_stop RESUME;           -- started, like the real one
EXECUTE TASK coco.guardrails_test.task_test_auto_stop;                -- run once now (asynchronous)

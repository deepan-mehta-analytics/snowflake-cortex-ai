-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 95 — end-to-end email test on the fixture (sends ONE email)
-- ══════════════════════════════════════════════════════════════════
-- Run ONCE with --set your_verified_email=<address>; never with --repeat
-- (each run sends mail). Check the outcome with 95b. The user confirms receipt.

-- ── Temporary test alert on the fixture's violated expectation ───
USE ROLE SYSADMIN;                                                    -- alert owner
CREATE OR REPLACE ALERT coco.guardrails_test.alert_test_high_value_volume
    SCHEDULE = 'USING CRON 0 0 1 1 * UTC'                             -- far-off schedule; only run by hand
    IF (EXISTS (
        SELECT 1
          FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS(
                 REF_ENTITY_NAME => 'COCO.GUARDRAILS_TEST.SILVER_INVOICES_TEST_SYNTHETIC',
                 REF_ENTITY_DOMAIN => 'TABLE'))
         WHERE expectation_name = 'HIGH_VALUE_COUNT_WITHIN_TOLERANCE'
           AND expectation_violated                                   -- the fixture is over tolerance
    ))
    THEN CALL coco.guardrails.send_high_value_alert_email(
             'COCO.GUARDRAILS_TEST.SILVER_INVOICES_TEST_SYNTHETIC', '<your_verified_email>');  -- same code path as Silver
EXECUTE ALERT coco.guardrails_test.alert_test_high_value_volume;      -- run once now (sends the email when it works)

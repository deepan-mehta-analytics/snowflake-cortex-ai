-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 05 — BR-004 volume alert: daily email when over tolerance
-- ══════════════════════════════════════════════════════════════════
-- Run as SYSADMIN after 00 (grants + integration) and 03 (expectation).
-- Run with: run_sql_checks.py … --set your_verified_email=<address>
-- (the address is substituted at run time and never committed).

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of procedure + alert
USE DATABASE coco;                                                    -- project database

-- ── Email procedure (reads the latest result, sends one email) ───
CREATE OR REPLACE PROCEDURE guardrails.send_high_value_alert_email(ref_entity_name VARCHAR, recipient VARCHAR)
    RETURNS VARCHAR                                                   -- the subject line that was sent
    LANGUAGE SQL                                                      -- Snowflake Scripting
    EXECUTE AS OWNER                                                  -- runs with SYSADMIN's grants
AS
$$
DECLARE
    flagged_count NUMBER;                                             -- latest DMF value
    subject VARCHAR;                                                  -- email subject
    body VARCHAR;                                                     -- email body
BEGIN
    SELECT value::NUMBER INTO :flagged_count                          -- latest measured count
      FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS(
             REF_ENTITY_NAME => :ref_entity_name, REF_ENTITY_DOMAIN => 'TABLE'))
     WHERE expectation_name = 'HIGH_VALUE_COUNT_WITHIN_TOLERANCE'
     ORDER BY measurement_time DESC LIMIT 1;
    subject := 'BR-004: ' || flagged_count || ' high-value invoices (tolerance 2)';  -- e.g. "BR-004: 3 high-value ..."
    body := 'The BR-004 guardrail counted ' || flagged_count || ' invoices over USD 500,000 equivalent '
            || '(or unassessable) on ' || ref_entity_name || ', above the Finance tolerance of 2. '
            || 'Review: SELECT * FROM COCO.GUARDRAILS.HIGH_VALUE_INVOICES_FOR_REVIEW;';  -- where to look
    CALL SYSTEM$SEND_EMAIL('email_finance_alerts', :recipient, :subject, :body);       -- send via the integration
    RETURN subject;                                                   -- shown in alert/procedure history
END;
$$;

-- ── Daily alert on Silver (serverless: no WAREHOUSE) ─────────────
CREATE OR REPLACE ALERT guardrails.alert_high_value_invoice_volume
    SCHEDULE = 'USING CRON 0 7 * * * UTC'                             -- one hour after the 06:00 DMF run
    IF (EXISTS (
        SELECT 1
          FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_EXPECTATION_STATUS(
                 REF_ENTITY_NAME => 'COCO.SILVER.DT_SILVER_AP_INVOICES',
                 REF_ENTITY_DOMAIN => 'TABLE'))
         WHERE expectation_name = 'HIGH_VALUE_COUNT_WITHIN_TOLERANCE'
           AND expectation_violated                                   -- over tolerance
           AND measurement_time >= DATEADD('hour', -24, CURRENT_TIMESTAMP())  -- only today's run → max 1 email/day
    ))
    THEN CALL guardrails.send_high_value_alert_email('COCO.SILVER.DT_SILVER_AP_INVOICES', '<your_verified_email>');
ALTER ALERT guardrails.alert_high_value_invoice_volume RESUME;        -- alerts are created suspended

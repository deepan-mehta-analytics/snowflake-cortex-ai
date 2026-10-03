-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 00 — account grants + email integration (BR-004)
-- ══════════════════════════════════════════════════════════════════
-- Run ONCE in a Snowsight worksheet as ACCOUNTADMIN, one statement at a time.
-- Replace <your_verified_email> IN THE WORKSHEET ONLY with the email verified on your
-- Snowflake user (Snowflake only emails verified addresses). Never commit the real address.
-- Prerequisite done 2026-10-03: free "Snowflake Public Data" listing installed as
-- SNOWFLAKE_PUBLIC_DATA_FREE and IMPORTED PRIVILEGES granted to SYSADMIN.

-- ── Context ──────────────────────────────────────────────────────
USE ROLE ACCOUNTADMIN;                                                -- account-level grants need ACCOUNTADMIN

-- ── Data Metric Functions ────────────────────────────────────────
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE SYSADMIN;       -- needed to associate + schedule DMFs
GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE SYSADMIN;  -- read DQ results views
GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_LOOKUP TO ROLE SYSADMIN;  -- call the expectation-status function

-- ── Alerts and tasks (serverless) ────────────────────────────────
GRANT EXECUTE ALERT ON ACCOUNT TO ROLE SYSADMIN;                      -- run alerts owned by SYSADMIN
GRANT EXECUTE MANAGED ALERT ON ACCOUNT TO ROLE SYSADMIN;              -- serverless alerts (no warehouse)
GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;                       -- run tasks owned by SYSADMIN
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE SYSADMIN;               -- serverless tasks (no warehouse)

-- ── Email notification integration ───────────────────────────────
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS email_finance_alerts    -- lets Snowflake send email
    TYPE = EMAIL                                                      -- email channel
    ENABLED = TRUE                                                    -- active immediately
    ALLOWED_RECIPIENTS = ('<your_verified_email>');                   -- only this verified address may receive mail
GRANT USAGE ON INTEGRATION email_finance_alerts TO ROLE SYSADMIN;     -- the alert's procedure sends as SYSADMIN

-- ── Confirm ──────────────────────────────────────────────────────
SHOW GRANTS TO ROLE SYSADMIN;                                         -- expect the 7 grants above + integration USAGE

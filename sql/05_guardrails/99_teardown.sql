-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 99 — OPTIONAL full removal of BR-004 (not part of the 10-day stop)
-- ══════════════════════════════════════════════════════════════════
-- The 10-day stop (06) only pauses things. Run this to delete everything.

-- ── As SYSADMIN ──────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of the guardrail objects
ALTER TASK IF EXISTS coco.guardrails.task_auto_stop_guardrail SUSPEND;            -- stop the one-off task
ALTER ALERT IF EXISTS coco.guardrails.alert_high_value_invoice_volume SUSPEND;    -- stop the alert
ALTER TABLE coco.silver.dt_silver_ap_invoices
    DROP DATA METRIC FUNCTION coco.guardrails.count_invoices_over_usd_500k
    ON (source_system, invoice_id, invoice_amount, currency_code, invoice_date,
        TABLE(coco.guardrails.fx_rates(currency_code, rate_date, usd_per_unit)));  -- detach from Silver
ALTER TABLE coco.silver.dt_silver_ap_invoices SET DATA_METRIC_SCHEDULE = '';      -- clear the schedule
DROP SCHEMA IF EXISTS coco.guardrails;                                -- views, DMF, procedure, alert, task

-- ── As ACCOUNTADMIN (user, Snowsight) ────────────────────────────
-- USE ROLE ACCOUNTADMIN;
-- DROP NOTIFICATION INTEGRATION IF EXISTS email_finance_alerts;      -- remove the email channel

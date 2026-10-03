-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 03 — attach the BR-004 DMF to Silver (daily 06:00 UTC)
-- ══════════════════════════════════════════════════════════════════
-- ALTER TABLE is the documented route for DMFs on dynamic tables.
-- Requires 00_account_grants_and_email.sql (EXECUTE DATA METRIC FUNCTION).
-- A table has ONE schedule for all its DMFs; Silver has no other DMFs.

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of the Silver dynamic table

-- ── Schedule (must exist before a DMF is added) ──────────────────
ALTER TABLE coco.silver.dt_silver_ap_invoices
    SET DATA_METRIC_SCHEDULE = 'USING CRON 0 6 * * * UTC';            -- daily 06:00 UTC

-- ── Association + expectation ────────────────────────────────────
ALTER TABLE coco.silver.dt_silver_ap_invoices
    ADD DATA METRIC FUNCTION coco.guardrails.count_invoices_over_usd_500k
    ON (source_system, invoice_id, invoice_amount, currency_code, invoice_date,   -- invoice columns
        TABLE(coco.guardrails.fx_rates(currency_code, rate_date, usd_per_unit)))  -- FX view as 2nd table
    EXPECTATION high_value_count_within_tolerance (VALUE <= 2);       -- N = 2, Finance-owned placeholder

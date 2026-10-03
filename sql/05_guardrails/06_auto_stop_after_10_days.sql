-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 06 — stop BR-004 automatically on 2026-10-13 07:30 UTC
-- ══════════════════════════════════════════════════════════════════
-- Keeps every object; stops everything that runs or bills. Restart for a
-- demo: SET DATA_METRIC_SCHEDULE = 'USING CRON 0 6 * * * UTC' on Silver,
-- then ALTER ALERT coco.guardrails.alert_high_value_invoice_volume RESUME.
-- The same 3 statements were proven on test objects by 96/96b.

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of alert, table and task
USE DATABASE coco;                                                    -- project database

-- ── One-off serverless task ──────────────────────────────────────
CREATE OR REPLACE TASK guardrails.task_auto_stop_guardrail
    SCHEDULE = 'USING CRON 30 7 13 10 * UTC'                          -- 2026-10-13 07:30 UTC (after that day's alert)
    COMMENT = 'BR-004: 10-day run ends 2026-10-13; suspends alert, clears DMF schedule, suspends itself'
AS
EXECUTE IMMEDIATE $$
BEGIN
    ALTER ALERT coco.guardrails.alert_high_value_invoice_volume SUSPEND;            -- 1: no more alert checks
    ALTER TABLE coco.silver.dt_silver_ap_invoices SET DATA_METRIC_SCHEDULE = '';    -- 2: no more DMF runs
    ALTER TASK coco.guardrails.task_auto_stop_guardrail SUSPEND;                    -- 3: never runs again
END;
$$;
ALTER TASK guardrails.task_auto_stop_guardrail RESUME;                -- tasks are created suspended

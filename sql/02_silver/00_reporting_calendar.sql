-- ══════════════════════════════════════════════════════════════════
-- 02_silver / 00 — reporting as-of date (one row)
-- ══════════════════════════════════════════════════════════════════
-- The sample invoices are a 2025 snapshot with no paid/unpaid flag, so
-- "overdue" is measured against this fixed date instead of CURRENT_DATE():
-- answers stay identical over time and the evaluation keys never rot.
-- 2025-06-30 = Q2/H1 month-end close: all 50 invoices issued, 44 overdue,
-- 6 not yet due (verified live 2026-10-04). Change the date only here.

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of the Silver schema objects

-- ── Table ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS coco.silver.reporting_calendar (           -- re-runnable: never replaced, keeps grants
    as_of_date DATE NOT NULL COMMENT 'Reporting as-of date: treat as today for overdue/recent questions'  -- the one value
) COMMENT = 'One row: the reporting as-of date for the 2025 AP snapshot';  -- shown in SHOW TABLES

-- ── Exactly one row, set to the as-of date ───────────────────────
MERGE INTO coco.silver.reporting_calendar AS target                  -- upsert keeps a single row
USING (SELECT '2025-06-30'::DATE AS as_of_date) AS source             -- the agreed date
ON TRUE                                                               -- match any existing row
WHEN MATCHED THEN UPDATE SET target.as_of_date = source.as_of_date    -- re-run: overwrite
WHEN NOT MATCHED THEN INSERT (as_of_date) VALUES (source.as_of_date); -- first run: insert

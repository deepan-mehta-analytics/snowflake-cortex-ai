-- ══════════════════════════════════════════════════════════════════
-- 02_silver / 90 — check the reporting as-of date is wired through
-- ══════════════════════════════════════════════════════════════════
-- Read-only. Run: python scripts/run_sql_checks.py sql/02_silver/90_check_reporting_date.sql

USE WAREHOUSE wh_coco_pipeline;                                       -- queries need a warehouse

SELECT 'calendar has one row' AS CHECK_NAME, '1' AS EXPECTED,         -- exactly one as-of row
       COUNT(*)::VARCHAR AS ACTUAL, IFF(COUNT(*) = 1, 'PASS', 'FAIL') AS OUTCOME
FROM coco.silver.reporting_calendar
UNION ALL
SELECT 'as-of date is 2025-06-30', '2025-06-30',                      -- the agreed date
       MAX(as_of_date)::VARCHAR, IFF(MAX(as_of_date) = '2025-06-30'::DATE, 'PASS', 'FAIL')
FROM coco.silver.reporting_calendar
UNION ALL
SELECT 'Silver still has 50 invoices', '50',                          -- pipeline unchanged
       COUNT(*)::VARCHAR, IFF(COUNT(*) = 50, 'PASS', 'FAIL')
FROM coco.silver.dt_silver_ap_invoices
UNION ALL
SELECT 'rollup overdue invoices = 44', '44',                          -- 44 past due at 2025-06-30
       SUM(overdue_invoice_count)::VARCHAR, IFF(SUM(overdue_invoice_count) = 44, 'PASS', 'FAIL')
FROM coco.silver.dt_vendor_invoice_summary
UNION ALL
SELECT 'rollup overdue amount matches Silver', 'equal',               -- independent recomputation
       IFF(r.amount = s.amount, 'equal', r.amount || ' vs ' || s.amount),
       IFF(r.amount = s.amount, 'PASS', 'FAIL')
FROM (SELECT SUM(total_overdue_amount) AS amount FROM coco.silver.dt_vendor_invoice_summary) AS r,
     (SELECT SUM(invoice_amount) AS amount FROM coco.silver.dt_silver_ap_invoices WHERE due_date < '2025-06-30') AS s;

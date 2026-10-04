USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA silver;                                        -- Silver Dynamic Tables live in their own schema

-- ── Dynamic Table: vendor-level invoice summary ──────────────────
-- Rolls dt_silver_ap_invoices up to one row per vendor. The source data
-- has no paid/unpaid flag, so "overdue" = due_date before the reporting
-- as-of date in silver.reporting_calendar (2025-06-30), and "pending" =
-- approval_status 'PENDING' — not a true payment-settled indicator.
CREATE OR REPLACE DYNAMIC TABLE dt_vendor_invoice_summary
    TARGET_LAG = DOWNSTREAM                               -- matches the upstream Silver table's lag policy (BR-009)
    WAREHOUSE = wh_coco_pipeline                           -- compute pool used to refresh this table
    REFRESH_MODE = AUTO                                    -- let Snowflake choose incremental vs full refresh
    AS
    SELECT
        i.vendor_name,                                      -- vendor display name (grouping key)
        COUNT(*)                                AS invoice_count,          -- total invoices seen for this vendor
        SUM(i.invoice_amount)                    AS total_spend,            -- lifetime invoiced amount (native currency, BR-002)
        SUM(IFF(i.approval_status = 'PENDING', i.invoice_amount, 0)) AS total_pending_amount,  -- awaiting approval
        SUM(IFF(i.due_date < c.as_of_date, i.invoice_amount, 0))     AS total_overdue_amount,  -- past due at the as-of date
        COUNT_IF(i.due_date < c.as_of_date)      AS overdue_invoice_count,  -- invoices past due at the as-of date
        MIN(i.invoice_date)                      AS first_invoice_date,     -- earliest invoice for this vendor
        MAX(i.invoice_date)                      AS last_invoice_date,      -- most recent invoice for this vendor
        COUNT(DISTINCT i.source_system)          AS source_system_count     -- distinct systems this vendor's invoices come from
    FROM dt_silver_ap_invoices AS i                          -- conformed Silver invoices
    CROSS JOIN reporting_calendar AS c                       -- the single as-of date row
    GROUP BY i.vendor_name;                                  -- one row per vendor

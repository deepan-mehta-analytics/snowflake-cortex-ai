USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA silver;                                        -- Silver Dynamic Tables live in their own schema

-- ── Dynamic Table: vendor-level invoice summary ──────────────────
-- Rolls dt_silver_ap_invoices up to one row per vendor. NOTE: the source
-- data has no paid/unpaid flag (see eval question "Show me overdue
-- invoices" in docs/business_requirements/ and eval/golden_dataset.jsonl),
-- so "overdue" is approximated as due_date in the past, and "pending" as
-- approval_status = 'PENDING' — not as a true payment-settled indicator.
CREATE OR REPLACE DYNAMIC TABLE dt_vendor_invoice_summary
    TARGET_LAG = DOWNSTREAM                               -- matches the upstream Silver table's lag policy (BR-009)
    WAREHOUSE = wh_coco_pipeline                           -- compute pool used to refresh this table
    REFRESH_MODE = AUTO                                    -- let Snowflake choose incremental vs full refresh
    AS
    SELECT
        vendor_name,                                        -- vendor display name (grouping key)
        COUNT(*)                              AS invoice_count,          -- total invoices seen for this vendor
        SUM(invoice_amount)                    AS total_spend,            -- lifetime invoiced amount across all sources (native currency, BR-002)
        SUM(
            CASE WHEN approval_status = 'PENDING'
                 THEN invoice_amount ELSE 0 END
        )                                       AS total_pending_amount,   -- amount on invoices still awaiting approval
        SUM(
            CASE WHEN due_date < CURRENT_DATE()
                 THEN invoice_amount ELSE 0 END
        )                                       AS total_overdue_amount,   -- amount on invoices past their due date
        MIN(invoice_date)                      AS first_invoice_date,      -- earliest invoice on record for this vendor
        MAX(invoice_date)                      AS last_invoice_date,       -- most recent invoice on record for this vendor
        COUNT(DISTINCT source_system)          AS source_system_count      -- how many distinct systems this vendor's invoices come from
    FROM dt_silver_ap_invoices                                -- built on top of the conformed Silver table
    GROUP BY vendor_name;

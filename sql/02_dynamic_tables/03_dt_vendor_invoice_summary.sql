USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA conformed;                                     -- Dynamic Tables live in the conformed schema

-- ── Dynamic Table: vendor-level invoice summary ──────────────────
-- Rolls the conformed invoice table up to one row per vendor, giving the
-- semantic view (and therefore the Cortex Agent) cheap, pre-aggregated
-- answers to "how much do we owe vendor X" style questions.
CREATE OR REPLACE DYNAMIC TABLE dt_vendor_invoice_summary
    TARGET_LAG = '1 hour'                                 -- refresh cadence matches the conformed header table
    WAREHOUSE = wh_coco_pipeline                           -- compute pool used to refresh this table
    REFRESH_MODE = AUTO                                    -- let Snowflake choose incremental vs full refresh
    AS
    SELECT
        vendor_name,                                        -- vendor display name (grouping key)
        COUNT(*)                              AS invoice_count,        -- total invoices seen for this vendor
        SUM(invoice_amount)                    AS total_invoiced_amount, -- lifetime invoiced amount across all sources
        SUM(
            CASE WHEN payment_status = 'OPEN' OR payment_status IS NULL
                 THEN invoice_amount ELSE 0 END
        )                                       AS total_outstanding_amount, -- amount not yet marked paid
        SUM(
            CASE WHEN due_date < CURRENT_DATE()
                  AND (payment_status = 'OPEN' OR payment_status IS NULL)
                 THEN invoice_amount ELSE 0 END
        )                                       AS total_overdue_amount,    -- outstanding amount past its due date
        MIN(invoice_date)                      AS first_invoice_date,      -- earliest invoice on record for this vendor
        MAX(invoice_date)                      AS last_invoice_date,       -- most recent invoice on record for this vendor
        AVG(extraction_confidence)             AS avg_extraction_confidence -- data-quality signal across sources
    FROM dt_invoices_conformed                                -- built on top of the conformed union table
    GROUP BY vendor_name;

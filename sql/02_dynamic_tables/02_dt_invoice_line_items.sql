USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA conformed;                                     -- Dynamic Tables live in the conformed schema

-- ── Dynamic Table: invoice line items flattened from vendor portal ──
-- The vendor portal is the only source that submits structured line-item
-- detail today; ERP and OCR sources are header-level only. This table
-- flattens the nested JSON so line-item questions can be answered directly.
CREATE OR REPLACE DYNAMIC TABLE dt_invoice_line_items
    TARGET_LAG = '1 hour'                                 -- refresh cadence matches the conformed header table
    WAREHOUSE = wh_coco_pipeline                           -- compute pool used to refresh this table
    REFRESH_MODE = AUTO                                    -- let Snowflake choose incremental vs full refresh
    AS
    SELECT
        v.invoice_id,                                       -- parent invoice reference
        v.vendor_id,                                         -- vendor ID, joinable back to the header table
        li.value:line_number::NUMBER      AS line_number,    -- 1-based line item position on the invoice
        li.value:description::STRING      AS description,    -- free-text line item description
        li.value:quantity::NUMBER(18,4)   AS quantity,       -- quantity billed on this line
        li.value:unit_price::NUMBER(18,4) AS unit_price,     -- unit price for this line
        li.value:line_amount::NUMBER(18,2) AS line_amount,   -- extended amount for this line (qty * unit_price)
        li.value:gl_account::STRING       AS gl_account      -- general ledger account code, if provided by the vendor
    FROM raw.raw_vendor_portal_invoices v,
         LATERAL FLATTEN(input => v.line_items) li;          -- explode the nested JSON array into one row per line item

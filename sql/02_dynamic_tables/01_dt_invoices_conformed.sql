USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA conformed;                                     -- Dynamic Tables live in the conformed schema

-- ── Dynamic Table: invoices conformed across all 3 sources ──────
-- Unions ERP, vendor portal, and OCR email invoices into one row-per-invoice
-- shape with consistent column names, so downstream consumers don't care
-- which system an invoice originated from.
CREATE OR REPLACE DYNAMIC TABLE dt_invoices_conformed
    TARGET_LAG = '1 hour'                                 -- refresh at most once an hour; tune per freshness needs
    WAREHOUSE = wh_coco_pipeline                           -- compute pool used to refresh this table
    REFRESH_MODE = AUTO                                    -- let Snowflake choose incremental vs full refresh
    AS
    SELECT
        invoice_id,                                        -- native ERP invoice number
        vendor_id,                                          -- ERP vendor master ID
        vendor_name,                                        -- vendor display name
        invoice_date,                                       -- invoice issue date
        due_date,                                           -- payment due date
        invoice_amount,                                     -- total invoice amount
        currency_code,                                      -- ISO currency code
        payment_status,                                     -- ERP payment status
        'ERP' AS source_system,                             -- tag row with its origin system
        1.0 AS extraction_confidence,                       -- ERP data is structured, treat as fully confident
        _loaded_at
    FROM raw.raw_erp_invoices

    UNION ALL

    SELECT
        invoice_id,                                         -- vendor portal invoice reference
        vendor_id,                                           -- vendor ID as known to the portal
        vendor_name,                                         -- vendor-submitted display name
        invoice_date,                                        -- invoice issue date
        due_date,                                             -- due date per submitted terms
        invoice_amount,                                       -- total invoice amount
        currency_code,                                        -- ISO currency code
        submission_status AS payment_status,                  -- map portal workflow status into the common column
        'VENDOR_PORTAL' AS source_system,                     -- tag row with its origin system
        1.0 AS extraction_confidence,                         -- portal submissions are structured, fully confident
        _loaded_at
    FROM raw.raw_vendor_portal_invoices

    UNION ALL

    SELECT
        invoice_id,                                          -- OCR-extracted invoice number
        NULL AS vendor_id,                                    -- OCR has no vendor master ID, resolved downstream
        vendor_name_raw AS vendor_name,                        -- OCR'd vendor name, needs fuzzy matching later
        invoice_date,                                          -- extracted invoice date
        due_date,                                               -- extracted due date
        invoice_amount,                                         -- extracted total amount
        currency_code,                                          -- extracted/inferred currency code
        NULL AS payment_status,                                 -- payment status not present in email documents
        'OCR_EMAIL' AS source_system,                           -- tag row with its origin system
        ocr_confidence AS extraction_confidence,                -- carry OCR confidence through for downstream filtering
        _loaded_at
    FROM raw.raw_ocr_email_invoices;

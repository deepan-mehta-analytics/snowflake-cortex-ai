USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA raw;                                           -- raw landing schema

-- ── Raw landing table: vendor self-service portal invoices ──────
-- Source: REST API pull from the vendor portal, landed as JSON via Snowpipe/Snowpipe Streaming.
CREATE TABLE IF NOT EXISTS raw_vendor_portal_invoices (
    invoice_id       STRING,                              -- vendor portal invoice reference
    vendor_id        STRING,                               -- vendor ID as known to the portal (maps to ERP vendor_id downstream)
    vendor_name      STRING,                               -- vendor-submitted display name
    invoice_date     DATE,                                 -- invoice issue date
    due_date         DATE,                                 -- due date per submitted terms
    invoice_amount   NUMBER(18,2),                         -- total invoice amount, source currency
    currency_code    STRING,                                -- ISO currency code
    submission_status STRING,                              -- portal workflow status (SUBMITTED, APPROVED, REJECTED)
    line_items       VARIANT,                               -- nested JSON array of invoice line items
    raw_payload      VARIANT,                               -- full API response for lineage/debugging
    _loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP() -- ingestion timestamp for freshness tracking
)
COMMENT = 'Raw vendor self-service portal invoice submissions, one row per invoice, loaded via API/Snowpipe';

-- ── Example load pattern (adjust pipe/stage to your setup) ──────
-- CREATE OR REPLACE STAGE stg_vendor_portal_invoices;                    -- landing stage for portal JSON files
-- CREATE OR REPLACE PIPE pipe_vendor_portal_invoices AS                  -- Snowpipe for near-real-time ingestion
--     COPY INTO raw_vendor_portal_invoices FROM @stg_vendor_portal_invoices
--     FILE_FORMAT = (TYPE = JSON);

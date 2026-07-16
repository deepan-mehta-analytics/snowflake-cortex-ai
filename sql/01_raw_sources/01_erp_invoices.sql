USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA raw;                                           -- raw landing schema

-- ── Raw landing table: ERP-exported AP invoices ─────────────────
-- Source: nightly batch export from the ERP (e.g. SAP/NetSuite) as CSV/Parquet on an external stage.
CREATE TABLE IF NOT EXISTS raw_erp_invoices (
    invoice_id       STRING,                              -- ERP-native invoice number
    vendor_id        STRING,                               -- ERP vendor master ID
    vendor_name      STRING,                               -- vendor display name as recorded in ERP
    invoice_date     DATE,                                 -- date invoice was issued
    due_date         DATE,                                 -- payment due date per ERP terms
    invoice_amount   NUMBER(18,2),                         -- total invoice amount, source currency
    currency_code    STRING,                                -- ISO currency code (USD, EUR, etc.)
    po_number        STRING,                                -- linked purchase order, if any
    payment_status   STRING,                                -- ERP payment status (OPEN, PAID, VOID)
    raw_payload      VARIANT,                               -- full source row for lineage/debugging
    _loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP() -- ingestion timestamp for freshness tracking
)
COMMENT = 'Raw ERP AP invoice export, one row per invoice, loaded via nightly batch stage COPY INTO';

-- ── Example load pattern (adjust stage/file format to your setup) ──
-- CREATE OR REPLACE FILE FORMAT ff_csv TYPE = CSV SKIP_HEADER = 1;      -- CSV parsing rules for the ERP export
-- CREATE OR REPLACE STAGE stg_erp_invoices FILE_FORMAT = ff_csv;        -- external/internal stage for landing files
-- COPY INTO raw_erp_invoices FROM @stg_erp_invoices;                    -- bulk load staged files into the table

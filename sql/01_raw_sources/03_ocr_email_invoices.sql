USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA raw;                                           -- raw landing schema

-- ── Raw landing table: OCR'd email-attachment invoices ──────────
-- Source: PDF/image invoices attached to AP inbox emails, parsed by an OCR/Document AI step upstream
-- (e.g. Cortex Document AI) and landed here as structured + raw text.
CREATE TABLE IF NOT EXISTS raw_ocr_email_invoices (
    invoice_id        STRING,                             -- best-effort invoice number extracted by OCR
    vendor_name_raw   STRING,                              -- vendor name as OCR'd from the document (needs fuzzy matching downstream)
    invoice_date      DATE,                                -- extracted invoice date
    due_date          DATE,                                -- extracted due date, nullable if not present on document
    invoice_amount    NUMBER(18,2),                        -- extracted total amount
    currency_code     STRING,                               -- extracted or inferred currency code
    ocr_confidence    FLOAT,                                -- OCR/Document AI confidence score (0-1) for the extraction
    email_subject     STRING,                               -- source email subject line, useful for audit/search
    email_received_at TIMESTAMP_NTZ,                        -- when the source email arrived
    document_text     STRING,                                -- full OCR'd plain text of the invoice document
    raw_payload       VARIANT,                               -- full Document AI response for lineage/debugging
    _loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP() -- ingestion timestamp for freshness tracking
)
COMMENT = 'Raw OCR-extracted invoices from AP inbox email attachments, one row per document';

-- ── Example load pattern (adjust to your Document AI integration) ──
-- CREATE OR REPLACE STAGE stg_ocr_email_invoices;                        -- landing stage for OCR output files
-- COPY INTO raw_ocr_email_invoices FROM @stg_ocr_email_invoices          -- bulk load OCR extraction results
--     FILE_FORMAT = (TYPE = JSON);

USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA agent;                                         -- agent-support objects live in their own schema

-- ── Cortex Search service: invoice document text ─────────────────
-- Gives the agent a second tool alongside the semantic view: free-text
-- retrieval over OCR'd invoice documents, for questions the semantic view
-- can't answer structurally (e.g. "does any invoice mention a late fee").
CREATE OR REPLACE CORTEX SEARCH SERVICE cs_invoice_documents
    ON document_text                                      -- column to build the search index over
    ATTRIBUTES invoice_id, vendor_name_raw, email_received_at -- filterable/returnable metadata alongside search hits
    WAREHOUSE = wh_coco_pipeline                            -- compute used to build/refresh the search index
    TARGET_LAG = '1 hour'                                   -- how fresh the index stays relative to source rows
    AS
    SELECT
        invoice_id,                                          -- returned as a filterable attribute
        vendor_name_raw,                                      -- returned as a filterable attribute
        email_received_at,                                    -- returned as a filterable attribute
        document_text                                         -- the text column that gets embedded and indexed
    FROM raw.raw_ocr_email_invoices
    WHERE document_text IS NOT NULL;                          -- skip rows with no OCR'd text to index

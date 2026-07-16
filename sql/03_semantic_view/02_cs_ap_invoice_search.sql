USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA agent;                                         -- Cortex Search service lives alongside other agent support objects

-- ── Cortex Search service: AP invoice line-description search ────
-- Complements sv_ap_analytics (structured/aggregate questions via Cortex
-- Analyst) with fuzzy, semantic lookup over free-text invoice line
-- descriptions — e.g. "find invoices mentioning hydraulic equipment" or
-- "PPE" style queries that don't map to a clean WHERE clause.
-- NOTE: this service already existed live in the account (created via
-- Snowsight's Agent Studio UI during earlier session work) before being
-- codified here — this CREATE OR REPLACE brings it under version control
-- and switches it onto this project's dedicated warehouse for consistency
-- with the rest of the pipeline (it was originally created on COMPUTE_WH).
CREATE OR REPLACE CORTEX SEARCH SERVICE ap_invoice_search
    ON line_description                                    -- column semantically indexed for search
    ATTRIBUTES vendor_name, approval_status, source_system, cost_center, gl_account, po_number  -- filterable metadata returned alongside matches
    WAREHOUSE = wh_coco_pipeline                            -- this project's dedicated warehouse, not the default COMPUTE_WH
    TARGET_LAG = '1 hour'                                   -- how fresh the search index needs to stay relative to the source table
    AS (
        SELECT
            invoice_id,                                     -- returned alongside search matches for downstream lookup
            invoice_number,                                 -- business-facing invoice number
            line_description,                               -- the free-text column being semantically indexed
            vendor_name,                                    -- filterable attribute
            approval_status,                                -- filterable attribute
            source_system,                                  -- filterable attribute
            cost_center,                                     -- filterable attribute
            gl_account,                                      -- filterable attribute
            po_number                                        -- filterable attribute
        FROM coco.silver.dt_silver_ap_invoices               -- same conformed Silver table the semantic view is built on
    );

-- ── Proof query: confirm the service is active and indexed ───────
-- SHOW CORTEX SEARCH SERVICES IN SCHEMA coco.agent;

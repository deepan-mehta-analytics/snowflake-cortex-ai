-- ── Warehouse ─────────────────────────────────────────────────
-- Single small warehouse for pipeline compute; Dynamic Tables use their own
-- serverless compute unless TARGET_LAG forces a warehouse refresh.
CREATE WAREHOUSE IF NOT EXISTS wh_coco_pipeline           -- warehouse used for manual loads and ad-hoc queries
    WAREHOUSE_SIZE = 'XSMALL'                             -- smallest size, cost-controlled for a portfolio project
    AUTO_SUSPEND = 60                                     -- suspend after 60s idle to minimise credit burn
    AUTO_RESUME = TRUE                                    -- resume automatically on next query
    INITIALLY_SUSPENDED = TRUE;                           -- don't start running until first used

-- ── Database ──────────────────────────────────────────────────
CREATE DATABASE IF NOT EXISTS coco                        -- top-level database for the AP invoice pipeline
    COMMENT = 'Multi-source AP invoice pipeline: raw sources -> Dynamic Tables -> semantic view -> Cortex Agent';

USE DATABASE coco;                                        -- switch context to the new database

-- ── Schemas ───────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS raw                           -- landing zone for each source system, minimally transformed
    COMMENT = 'Raw landing tables per AP invoice source (ERP, vendor portal, OCR email)';

CREATE SCHEMA IF NOT EXISTS conformed                     -- Dynamic Tables that clean, union, and enrich raw data
    COMMENT = 'Dynamic Tables: conformed and aggregated invoice data, auto-refreshed off raw';

CREATE SCHEMA IF NOT EXISTS semantic                      -- semantic view(s) grounding the Cortex Agent
    COMMENT = 'Semantic views exposing business-friendly facts/dimensions/metrics to Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS agent                         -- Cortex Search services + agent-facing objects
    COMMENT = 'Cortex Search services and any agent-support objects (stages, functions)';

-- ── Role grants (adjust principal names to your account) ───────
GRANT USAGE ON WAREHOUSE wh_coco_pipeline TO ROLE sysadmin;   -- allow pipeline builders to use the warehouse
GRANT USAGE ON DATABASE coco TO ROLE sysadmin;                -- allow pipeline builders to see the database
GRANT USAGE ON ALL SCHEMAS IN DATABASE coco TO ROLE sysadmin; -- and all schemas within it

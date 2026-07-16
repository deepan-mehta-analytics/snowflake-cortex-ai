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
    COMMENT = 'Multi-source AP invoice pipeline: bronze sources -> Silver Dynamic Table -> semantic view -> Cortex Agent';

USE DATABASE coco;                                        -- switch context to the new database

-- ── Schemas ───────────────────────────────────────────────────
-- Naming follows medallion architecture (bronze/silver), matching the
-- reference workshop this project is built from (see docs/business_requirements/).
CREATE SCHEMA IF NOT EXISTS bronze                        -- landing zone per AP invoice source system, minimally transformed
    COMMENT = 'Bronze landing tables per AP invoice source (SAP, Oracle, Baan, Workday)';

CREATE SCHEMA IF NOT EXISTS silver                        -- Dynamic Tables that clean, union, and conform bronze data
    COMMENT = 'Silver Dynamic Tables: conformed and aggregated invoice data, auto-refreshed off bronze';

CREATE SCHEMA IF NOT EXISTS semantic                      -- semantic view(s) grounding the Cortex Agent
    COMMENT = 'Semantic views exposing business-friendly facts/dimensions/metrics to Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS agent                         -- agent-facing support objects
    COMMENT = 'Cortex Agent support objects (evaluation tables, stages, functions)';

-- ── Role grants (adjust principal names to your account) ───────
GRANT USAGE ON WAREHOUSE wh_coco_pipeline TO ROLE sysadmin;   -- allow pipeline builders to use the warehouse
GRANT USAGE ON DATABASE coco TO ROLE sysadmin;                -- allow pipeline builders to see the database
GRANT USAGE ON ALL SCHEMAS IN DATABASE coco TO ROLE sysadmin; -- and all schemas within it

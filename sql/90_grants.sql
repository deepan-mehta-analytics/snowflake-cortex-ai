-- ══════════════════════════════════════════════════════════════════
-- 90 — object grants for the MCP and CI roles (re-runnable)
-- ══════════════════════════════════════════════════════════════════
-- Checklist step: run in Snowsight as ACCOUNTADMIN after every
-- `python scripts/deploy.py --apply` — CREATE OR REPLACE drops grants on
-- the replaced objects. Roles/users come from 04_mcp/00 and 06_ci/00;
-- MCP-server grants stay in 04_mcp/01. Verify with 91_check_grants.sql.

-- ── Context ──────────────────────────────────────────────────────
USE ROLE ACCOUNTADMIN;                                                -- can grant on ACCOUNTADMIN-owned coco and SYSADMIN-owned objects

-- ── MCP role: read path for the Claude connector ─────────────────
GRANT USAGE ON WAREHOUSE wh_coco_pipeline TO ROLE mcp_claude_role;    -- runs the agent's generated SQL
GRANT USAGE ON DATABASE coco TO ROLE mcp_claude_role;                 -- resolve objects in the project database
GRANT USAGE ON SCHEMA coco.agent TO ROLE mcp_claude_role;             -- agent + search service schema
GRANT USAGE ON SCHEMA coco.semantic TO ROLE mcp_claude_role;          -- semantic view schema
GRANT USAGE ON SCHEMA coco.silver TO ROLE mcp_claude_role;            -- Silver Dynamic Tables + reporting calendar
GRANT USAGE ON AGENT coco.agent.ap_invoice_agent TO ROLE mcp_claude_role;  -- invoke the agent tool
GRANT USAGE ON CORTEX SEARCH SERVICE coco.agent.ap_invoice_search TO ROLE mcp_claude_role;  -- invoke the search tool
GRANT SELECT ON SEMANTIC VIEW coco.semantic.sv_ap_analytics TO ROLE mcp_claude_role;  -- invoke the analyst tool
GRANT SELECT ON DYNAMIC TABLE coco.silver.dt_silver_ap_invoices TO ROLE mcp_claude_role;      -- Silver invoices
GRANT SELECT ON DYNAMIC TABLE coco.silver.dt_vendor_invoice_summary TO ROLE mcp_claude_role;  -- vendor rollup
GRANT SELECT ON TABLE coco.silver.reporting_calendar TO ROLE mcp_claude_role;                 -- as-of date (v1.0.0)
GRANT USAGE ON PROCEDURE coco.agent.invoice_totals(VARCHAR, VARCHAR, VARCHAR) TO ROLE mcp_claude_role;  -- agent tool: exact totals (v1.1.0)
GRANT USAGE ON PROCEDURE coco.agent.review_status(NUMBER) TO ROLE mcp_claude_role;  -- agent tool: BR-004 review status (v1.1.0)

-- ── CI role: native agent evaluation ─────────────────────────────
GRANT USAGE ON WAREHOUSE wh_coco_pipeline TO ROLE ci_eval_role;       -- agent SQL + evaluation tasks
GRANT USAGE ON DATABASE coco TO ROLE ci_eval_role;                    -- project database
GRANT USAGE ON SCHEMA coco.silver TO ROLE ci_eval_role;               -- Silver schema
GRANT USAGE ON SCHEMA coco.semantic TO ROLE ci_eval_role;             -- semantic view schema
GRANT USAGE ON SCHEMA coco.agent TO ROLE ci_eval_role;                -- agent + search schema
GRANT USAGE ON SCHEMA coco.eval TO ROLE ci_eval_role;                 -- eval schema = session schema
GRANT SELECT ON DYNAMIC TABLE coco.silver.dt_silver_ap_invoices TO ROLE ci_eval_role;         -- Silver invoices
GRANT SELECT ON DYNAMIC TABLE coco.silver.dt_vendor_invoice_summary TO ROLE ci_eval_role;     -- vendor rollup
GRANT SELECT ON TABLE coco.silver.reporting_calendar TO ROLE ci_eval_role;                    -- as-of date (v1.0.0)
GRANT SELECT ON SEMANTIC VIEW coco.semantic.sv_ap_analytics TO ROLE ci_eval_role;            -- analyst tool
GRANT USAGE ON CORTEX SEARCH SERVICE coco.agent.ap_invoice_search TO ROLE ci_eval_role;      -- search tool
GRANT USAGE ON AGENT coco.agent.ap_invoice_agent TO ROLE ci_eval_role;                       -- run the agent
GRANT USAGE ON PROCEDURE coco.agent.invoice_totals(VARCHAR, VARCHAR, VARCHAR) TO ROLE ci_eval_role;  -- agent tool: exact totals (v1.1.0)
GRANT USAGE ON PROCEDURE coco.agent.review_status(NUMBER) TO ROLE ci_eval_role;  -- agent tool: BR-004 review status (v1.1.0)
GRANT MONITOR ON AGENT coco.agent.ap_invoice_agent TO ROLE ci_eval_role;                     -- evaluate the agent
GRANT SELECT, INSERT, DELETE ON TABLE coco.eval.golden_questions TO ROLE ci_eval_role;       -- refresh + read the dataset
GRANT READ, WRITE ON STAGE coco.eval.config_stage TO ROLE ci_eval_role;                      -- PUT + read the config
GRANT CREATE DATASET ON SCHEMA coco.eval TO ROLE ci_eval_role;        -- run's dataset: block creates it here
GRANT CREATE TASK ON SCHEMA coco.eval TO ROLE ci_eval_role;           -- docs: CREATE TASK on the current schema
GRANT CREATE FILE FORMAT ON SCHEMA coco.eval TO ROLE ci_eval_role;    -- docs: CREATE FILE FORMAT on the current schema

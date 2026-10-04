-- ══════════════════════════════════════════════════════════════════
-- 06_ci / 00 — least-privilege identity for GitHub Actions live eval
-- ══════════════════════════════════════════════════════════════════
-- Run ONCE in a Snowsight worksheet as ACCOUNTADMIN, one statement at a time.
-- No secrets in this file: the PAT secret is shown ONCE in the result of the
-- last statement — paste it straight into GitHub (repo Settings → Secrets and
-- variables → Actions → SNOWFLAKE_PAT), never into chat or a file.
-- Privilege list = docs "Cortex Agent evaluations → Access control" + the
-- agent's tool path (mirrors mcp_claude_role, without the MCP server).

-- ── Role ─────────────────────────────────────────────────────────
USE ROLE ACCOUNTADMIN;                                                -- grants, users and network policies need it
CREATE ROLE IF NOT EXISTS ci_eval_role                                -- the only role the CI job can use
    COMMENT = 'GitHub Actions: native agent evaluation, read-only data path';  -- documents purpose in SHOW ROLES
GRANT ROLE ci_eval_role TO ROLE SYSADMIN;                             -- keeps it in the hierarchy; SYSADMIN PAT can diagnose it

-- ── Agent read path (same as mcp_claude_role, without the MCP server) ──
GRANT USAGE ON DATABASE coco TO ROLE ci_eval_role;                    -- project database
GRANT USAGE ON SCHEMA coco.silver TO ROLE ci_eval_role;               -- Silver schema the agent's SQL reads
GRANT USAGE ON SCHEMA coco.semantic TO ROLE ci_eval_role;             -- semantic view schema
GRANT USAGE ON SCHEMA coco.agent TO ROLE ci_eval_role;                -- agent + search service schema
GRANT SELECT ON DYNAMIC TABLE coco.silver.dt_silver_ap_invoices TO ROLE ci_eval_role;      -- Silver invoices
GRANT SELECT ON DYNAMIC TABLE coco.silver.dt_vendor_invoice_summary TO ROLE ci_eval_role;  -- vendor rollup
GRANT SELECT ON SEMANTIC VIEW coco.semantic.sv_ap_analytics TO ROLE ci_eval_role;         -- Cortex Analyst tool
GRANT USAGE ON CORTEX SEARCH SERVICE coco.agent.ap_invoice_search TO ROLE ci_eval_role;   -- Cortex Search tool
GRANT USAGE ON AGENT coco.agent.ap_invoice_agent TO ROLE ci_eval_role;                    -- run the agent (docs: USAGE)
GRANT MONITOR ON AGENT coco.agent.ap_invoice_agent TO ROLE ci_eval_role;                  -- evaluate the agent (docs: MONITOR)
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE ci_eval_role; -- invoke Cortex Agents
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ci_eval_role;       -- evaluation LLM judge (docs)
GRANT EXECUTE TASK ON ACCOUNT TO ROLE ci_eval_role;                   -- evaluation runs execute as tasks (docs)
GRANT USAGE ON WAREHOUSE wh_coco_pipeline TO ROLE ci_eval_role;       -- agent SQL + evaluation tasks

-- ── Evaluation dataset, config and session schema (coco.eval) ────
GRANT USAGE ON SCHEMA coco.eval TO ROLE ci_eval_role;                 -- eval schema = the session's current schema
GRANT SELECT, INSERT, DELETE ON TABLE coco.eval.golden_questions TO ROLE ci_eval_role;  -- native_eval.py refreshes + reads it
GRANT READ, WRITE ON STAGE coco.eval.config_stage TO ROLE ci_eval_role;    -- PUT the rendered YAML + let the run read it
GRANT CREATE DATASET ON SCHEMA coco.eval TO ROLE ci_eval_role;        -- run's dataset: block creates it here (ledger T1 fact 4)
GRANT CREATE TASK ON SCHEMA coco.eval TO ROLE ci_eval_role;           -- docs: CREATE TASK on the current schema
GRANT CREATE FILE FORMAT ON SCHEMA coco.eval TO ROLE ci_eval_role;    -- docs: CREATE FILE FORMAT on the current schema

-- ── Network policy (PATs need one) ───────────────────────────────
CREATE NETWORK POLICY IF NOT EXISTS ci_eval_network_policy            -- attached to the CI user only
    ALLOWED_IP_LIST = ('0.0.0.0/0')                                   -- GitHub-hosted runner IPs are not fixed
    COMMENT = 'GitHub runners have no fixed IPs; the role restriction is the boundary';  -- documents the trade-off

-- ── Service user + PAT ───────────────────────────────────────────
CREATE USER IF NOT EXISTS ci_eval_user                                -- the identity GitHub Actions connects as
    TYPE = SERVICE                                                    -- no password, no browser sign-in
    DEFAULT_ROLE = ci_eval_role                                       -- sessions start in the narrow role
    DEFAULT_WAREHOUSE = wh_coco_pipeline                              -- X-Small project warehouse
    NETWORK_POLICY = ci_eval_network_policy                           -- required for programmatic access tokens
    COMMENT = 'GitHub Actions live-eval (snowflake-cortex-ai)';       -- documents purpose in SHOW USERS
GRANT ROLE ci_eval_role TO USER ci_eval_user;                         -- its only non-PUBLIC role
ALTER USER ci_eval_user ADD PROGRAMMATIC ACCESS TOKEN ci_eval_pat_2026_10  -- token GitHub stores as SNOWFLAKE_PAT
    ROLE_RESTRICTION = 'CI_EVAL_ROLE'                                 -- token can only ever act as ci_eval_role
    DAYS_TO_EXPIRY = 37;                                              -- ≈ 2026-11-10, just before the trial ends; copy the secret NOW

-- ── Confirm ──────────────────────────────────────────────────────
SHOW GRANTS TO ROLE ci_eval_role;                                     -- expect the grants above
SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER ci_eval_user;           -- expect ci_eval_pat_2026_10, ACTIVE

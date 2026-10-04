-- ══════════════════════════════════════════════════════════════════
-- 06_ci / 00 — least-privilege identity for GitHub Actions live eval
-- ══════════════════════════════════════════════════════════════════
-- Checklist step A5: run in a Snowsight worksheet as ACCOUNTADMIN, one
-- statement at a time. Re-runnable. No secrets in this file: the CI token
-- is created once by hand (docs/deploy_checklist.md step D5).
-- Privilege list = docs "Cortex Agent evaluations → Access control" + the
-- agent's tool path (mirrors mcp_claude_role, without the MCP server).

-- ── Role ─────────────────────────────────────────────────────────
USE ROLE ACCOUNTADMIN;                                                -- grants, users and network policies need it
CREATE ROLE IF NOT EXISTS ci_eval_role                                -- the only role the CI job can use
    COMMENT = 'GitHub Actions: native agent evaluation, read-only data path';  -- documents purpose in SHOW ROLES
GRANT ROLE ci_eval_role TO ROLE SYSADMIN;                             -- keeps it in the hierarchy; SYSADMIN PAT can diagnose it

-- ── Account-level privileges ─────────────────────────────────────
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE ci_eval_role; -- invoke Cortex Agents
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ci_eval_role;       -- evaluation LLM judge (docs)
GRANT EXECUTE TASK ON ACCOUNT TO ROLE ci_eval_role;                   -- evaluation runs execute as tasks (docs)

-- ── Object grants ────────────────────────────────────────────────
-- Moved to sql/90_grants.sql (v1.0.0): they need the objects to exist, so
-- they run after `scripts/deploy.py --apply` — see docs/deploy_checklist.md.

-- ── Network policy (PATs need one) ───────────────────────────────
CREATE NETWORK POLICY IF NOT EXISTS ci_eval_network_policy            -- attached to the CI user only
    ALLOWED_IP_LIST = ('0.0.0.0/0')                                   -- GitHub-hosted runner IPs are not fixed
    COMMENT = 'GitHub runners have no fixed IPs; the role restriction is the boundary';  -- documents the trade-off

-- ── Service user ─────────────────────────────────────────────────
CREATE USER IF NOT EXISTS ci_eval_user                                -- the identity GitHub Actions connects as
    TYPE = SERVICE                                                    -- no password, no browser sign-in
    DEFAULT_ROLE = ci_eval_role                                       -- sessions start in the narrow role
    DEFAULT_WAREHOUSE = wh_coco_pipeline                              -- X-Small project warehouse
    NETWORK_POLICY = ci_eval_network_policy                           -- required for programmatic access tokens
    COMMENT = 'GitHub Actions live-eval (snowflake-cortex-ai)';       -- documents purpose in SHOW USERS
GRANT ROLE ci_eval_role TO USER ci_eval_user;                         -- its only non-PUBLIC role

-- ── PAT (one-time, NOT re-runnable) ──────────────────────────────
-- Created once by hand: see docs/deploy_checklist.md step D5 "CI token".
-- Re-adding a token under an existing name fails, so it is not in this file.

-- ── Confirm ──────────────────────────────────────────────────────
SHOW GRANTS TO ROLE ci_eval_role;                                     -- expect the account-level grants above (+ 90_grants.sql once run)
SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER ci_eval_user;           -- expect ci_eval_pat_* ACTIVE (created by the checklist)

-- ══════════════════════════════════════════════════════════════════
-- 04_mcp / 00 — Least-privilege role + dedicated user for Claude MCP
-- ══════════════════════════════════════════════════════════════════
-- Why a dedicated USER (not just a role): Claude's MCP client always
-- requests the OAuth scope session:role:all, so the MCP session runs as
-- the connecting user's DEFAULT_ROLE. Pointing your own user's default
-- role at a narrow MCP role would also change every Snowsight login.
-- A separate user keeps your normal login untouched and pins Claude to
-- the narrow role. (Source: Snowflake-managed MCP server docs,
-- "Role behavior in OAuth sessions".)
--
-- Run in a Snowsight worksheet with Ctrl+A → Run All. Replace the two
-- <PLACEHOLDERS> in the worksheet only — never save the real password
-- to this file (keep a filled copy as *.local.sql, which is gitignored).

-- ── Role ─────────────────────────────────────────────────────────
USE ROLE SECURITYADMIN;                                               -- role administrator for creating roles and granting privileges
CREATE ROLE IF NOT EXISTS mcp_claude_role                             -- narrow role that every Claude MCP session will run as
    COMMENT = 'Least-privilege role for the Claude.ai MCP connector (coco AP invoice tools only)';  -- documents purpose in SHOW ROLES
GRANT ROLE mcp_claude_role TO ROLE SYSADMIN;                          -- keep the custom role inside the standard role hierarchy

-- ── Cortex Agent access (SNOWFLAKE database role) ────────────────
USE ROLE ACCOUNTADMIN;                                                -- SNOWFLAKE database roles are granted by ACCOUNTADMIN
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE mcp_claude_role;  -- required to invoke Cortex Agents (docs: Agent-based MCP server)

-- ── Compute + container access ───────────────────────────────────
USE ROLE SECURITYADMIN;                                               -- back to the grant administrator for object grants
GRANT USAGE ON WAREHOUSE wh_coco_pipeline TO ROLE mcp_claude_role;    -- X-Small project warehouse runs the agent's generated SQL
GRANT USAGE ON DATABASE coco TO ROLE mcp_claude_role;                 -- allows resolving objects inside the project database
GRANT USAGE ON SCHEMA coco.agent TO ROLE mcp_claude_role;             -- schema holding the Cortex Agent and Cortex Search service
GRANT USAGE ON SCHEMA coco.semantic TO ROLE mcp_claude_role;          -- schema holding the semantic view
GRANT USAGE ON SCHEMA coco.silver TO ROLE mcp_claude_role;            -- schema holding the Silver Dynamic Tables the agent queries

-- ── Tool-level privileges (MCP server access ≠ tool access) ──────
GRANT USAGE ON AGENT coco.agent.ap_invoice_agent TO ROLE mcp_claude_role;  -- invoke the AP invoice Cortex Agent tool
GRANT USAGE ON CORTEX SEARCH SERVICE coco.agent.ap_invoice_search TO ROLE mcp_claude_role;  -- invoke the line-description search tool
GRANT SELECT ON SEMANTIC VIEW coco.semantic.sv_ap_analytics TO ROLE mcp_claude_role;  -- invoke the Cortex Analyst tool over the semantic view
GRANT SELECT ON DYNAMIC TABLE coco.silver.dt_silver_ap_invoices TO ROLE mcp_claude_role;  -- read access for SQL generated from the semantic view
GRANT SELECT ON DYNAMIC TABLE coco.silver.dt_vendor_invoice_summary TO ROLE mcp_claude_role;  -- read access for vendor rollup queries

-- ── Dedicated Claude user ────────────────────────────────────────
USE ROLE USERADMIN;                                                   -- user administrator creates users
CREATE USER IF NOT EXISTS claude_mcp_user                             -- the identity you sign in as on Claude's OAuth consent screen
    TYPE = PERSON                                                     -- interactive OAuth sign-in (SERVICE users can't do browser OAuth)
    PASSWORD = '<SET_A_STRONG_PASSWORD_IN_WORKSHEET_ONLY>'            -- placeholder; type the real value in Snowsight, never commit it
    MUST_CHANGE_PASSWORD = TRUE                                       -- forces a fresh password (and MFA enrolment) at first sign-in
    EMAIL = '<YOUR_EMAIL>'                                            -- placeholder; needed for MFA enrolment / password reset
    DEFAULT_ROLE = mcp_claude_role                                    -- Claude's session:role:all resolves to this role
    DEFAULT_WAREHOUSE = wh_coco_pipeline                              -- MCP sessions fail to initialise if this is NULL
    COMMENT = 'Sign-in identity for the Claude.ai Snowflake MCP connector';  -- documents purpose in SHOW USERS

-- ── Attach role to user ──────────────────────────────────────────
USE ROLE SECURITYADMIN;                                               -- grant administrator links roles to users
GRANT ROLE mcp_claude_role TO USER claude_mcp_user;                   -- the user's only non-PUBLIC role

-- ══════════════════════════════════════════════════════════════════
-- 04_mcp / 01 — Snowflake-managed MCP server for the AP invoice tools
-- ══════════════════════════════════════════════════════════════════
-- Run after 00_mcp_role_and_user.sql. Ctrl+A → Run All in Snowsight.
--
-- Tools exposed (names are what Claude sees in tools/list):
--   ap-invoice-agent   CORTEX_AGENT_RUN             coco.agent.ap_invoice_agent
--                      Snowflake's recommended client-facing tool: the agent
--                      orchestrates Analyst + Search itself.
--   ap-invoice-analyst CORTEX_ANALYST_MESSAGE       coco.semantic.sv_ap_analytics
--                      Returns generated SQL only (does not execute it).
--   ap-invoice-search  CORTEX_SEARCH_SERVICE_QUERY  coco.agent.ap_invoice_search
--                      Fuzzy search over invoice line descriptions.
-- Analyst + Search are exposed directly as a fallback because the
-- registered agent object was unreliable via Agent Studio / DATA_AGENT_RUN
-- in earlier sessions — pre-flight checks below confirm it first.
--
-- NOTE: the YAML inside $$ … $$ carries no inline comments on purpose —
-- the spec is parsed by Snowflake's YAML loader, so every tool is
-- documented in the header above instead (same reasoning as the
-- Dockerfile/.gitignore inline-comment exceptions).

-- ── Pre-flight: confirm the target objects exist ─────────────────
USE ROLE SYSADMIN;                                                    -- project objects are SYSADMIN-owned
DESCRIBE AGENT coco.agent.ap_invoice_agent;                           -- agent must exist and reference WH_COCO_PIPELINE, not COMPUTE_WH
SHOW CORTEX SEARCH SERVICES IN SCHEMA coco.agent;                     -- ap_invoice_search must be listed and ACTIVE
SHOW SEMANTIC VIEWS IN SCHEMA coco.semantic;                          -- sv_ap_analytics must be listed

-- ── Schema for MCP server objects ────────────────────────────────
-- Same pattern as sql/00_setup: the coco database is ACCOUNTADMIN-owned,
-- so the schema is created there and ownership handed to SYSADMIN
-- (SYSADMIN has no CREATE SCHEMA on coco — first live run failed on it).
USE ROLE ACCOUNTADMIN;                                                -- database owner can create schemas in coco
CREATE SCHEMA IF NOT EXISTS coco.mcp                                  -- keeps integration objects apart from pipeline layers
    COMMENT = 'Snowflake-managed MCP servers exposing coco tools to external AI clients';  -- documents purpose in SHOW SCHEMAS
GRANT OWNERSHIP ON SCHEMA coco.mcp TO ROLE SYSADMIN COPY CURRENT GRANTS;  -- SYSADMIN owns it, like bronze/silver/semantic/agent
USE ROLE SYSADMIN;                                                    -- create the MCP server as the project object owner

-- ── MCP server ───────────────────────────────────────────────────
CREATE MCP SERVER IF NOT EXISTS coco.mcp.ap_invoice_mcp               -- URL path: /api/v2/databases/COCO/schemas/MCP/mcp-servers/AP_INVOICE_MCP
  FROM SPECIFICATION $$
  tools:
    - title: "AP invoice agent"
      name: "ap-invoice-agent"
      type: "CORTEX_AGENT_RUN"
      identifier: "coco.agent.ap_invoice_agent"
      description: "Answers accounts-payable invoice questions across SAP, Oracle, Baan and Workday sources (spend, vendors, approval status, cost centers) by orchestrating Cortex Analyst and Cortex Search. Prefer this tool for business questions."
    - title: "AP invoice analyst (SQL generation)"
      name: "ap-invoice-analyst"
      type: "CORTEX_ANALYST_MESSAGE"
      identifier: "coco.semantic.sv_ap_analytics"
      description: "Generates SQL from a natural-language question over the AP invoice semantic view. Returns the SQL statement and interpretation only; it does not execute the query."
    - title: "AP invoice line search"
      name: "ap-invoice-search"
      type: "CORTEX_SEARCH_SERVICE_QUERY"
      identifier: "coco.agent.ap_invoice_search"
      description: "Semantic search over free-text invoice line descriptions, with vendor, approval status, source system, cost center, GL account and PO number attributes."
  $$;

-- ── Grant connection + discovery to the Claude role ──────────────
USE ROLE SECURITYADMIN;                                               -- grant administrator
GRANT USAGE ON SCHEMA coco.mcp TO ROLE mcp_claude_role;               -- resolve the MCP server's schema
GRANT USAGE ON MCP SERVER coco.mcp.ap_invoice_mcp TO ROLE mcp_claude_role;  -- connect + tools/list (tool privileges were granted in 00)

-- ══════════════════════════════════════════════════════════════════
-- 04_mcp / 99 — Teardown (remove the Claude MCP connector access)
-- ══════════════════════════════════════════════════════════════════
-- Run when the connector is no longer needed (or before the trial ends).
-- Also remove the connector in Claude → Settings → Connectors.

-- ── Revoke the OAuth client first (kills new token issuance) ─────
USE ROLE ACCOUNTADMIN;                                                -- integrations are ACCOUNTADMIN-owned
DROP SECURITY INTEGRATION IF EXISTS mcp_claude_oauth;                 -- Claude can no longer obtain or refresh tokens

-- ── MCP servers + schema ─────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of the MCP objects
DROP MCP SERVER IF EXISTS coco.mcp.ap_invoice_sql_mcp;                -- optional read-only SQL server (no-op if 03 never ran)
DROP MCP SERVER IF EXISTS coco.mcp.ap_invoice_mcp;                    -- main agent/analyst/search server
DROP SCHEMA IF EXISTS coco.mcp;                                       -- empty schema created for MCP objects

-- ── User + role ──────────────────────────────────────────────────
USE ROLE USERADMIN;                                                   -- user/role administrator
DROP USER IF EXISTS claude_mcp_user;                                  -- Claude sign-in identity
USE ROLE SECURITYADMIN;                                               -- role owner (created under SECURITYADMIN in 00)
DROP ROLE IF EXISTS mcp_claude_role;                                  -- drops the role and all its grants

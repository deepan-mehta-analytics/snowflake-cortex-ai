-- ══════════════════════════════════════════════════════════════════
-- 04_mcp / 04 — Verify the MCP setup and build the connector URL
-- ══════════════════════════════════════════════════════════════════
-- Run after 00–02 (and 03 if used). Every check is read-only.

-- ── Objects exist ────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of the MCP schema/servers
SHOW MCP SERVERS IN SCHEMA coco.mcp;                                  -- expect AP_INVOICE_MCP (and AP_INVOICE_SQL_MCP if 03 ran)
DESCRIBE MCP SERVER coco.mcp.ap_invoice_mcp;                          -- server_spec should list the three tools

-- ── Role + user wiring ───────────────────────────────────────────
USE ROLE SECURITYADMIN;                                               -- can inspect all grants and users
SHOW GRANTS TO ROLE mcp_claude_role;                                  -- expect only the narrow coco grants from 00/01 (no ALL / FUTURE grants)
SHOW GRANTS TO USER claude_mcp_user;                                  -- expect MCP_CLAUDE_ROLE only
DESCRIBE USER claude_mcp_user;                                        -- DEFAULT_ROLE = MCP_CLAUDE_ROLE, DEFAULT_WAREHOUSE = WH_COCO_PIPELINE

-- ── Connector URL (paste into Claude → Settings → Connectors) ────
SELECT 'https://'                                                     -- MCP endpoint is HTTPS only
    || LOWER(REPLACE(CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME(), '_', '-'))  -- org-account host; underscores → hyphens (docs warning)
    || '.snowflakecomputing.com'                                      -- public (non-PrivateLink) endpoint for SaaS clients
    || '/api/v2/databases/COCO/schemas/MCP/mcp-servers/AP_INVOICE_MCP'  -- fully qualified server path
    AS claude_connector_url;                                          -- single column to copy

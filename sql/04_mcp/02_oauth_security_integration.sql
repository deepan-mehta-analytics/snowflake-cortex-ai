-- ══════════════════════════════════════════════════════════════════
-- 04_mcp / 02 — Snowflake OAuth integration for the Claude.ai connector
-- ══════════════════════════════════════════════════════════════════
-- Run after 01_mcp_server.sql, as ACCOUNTADMIN.
--
-- Redirect URI: claude.ai's documented callback. If Claude's
-- "Add custom connector" dialog shows a different callback URI, use that
-- exact value instead (a mismatch is the #1 cause of consent failures).
-- Claude Desktop uses a localhost callback — add it via
-- OAUTH_ALTERNATE_REDIRECT_URIS only if you also connect from Desktop.
--
-- SECRETS: the client ID / secret returned by the last query are
-- credentials. Copy them straight from Snowsight into Claude's connector
-- dialog. Never paste them into chat, a file, or a commit.

-- ── Security integration ─────────────────────────────────────────
USE ROLE ACCOUNTADMIN;                                                -- security integrations require ACCOUNTADMIN
CREATE SECURITY INTEGRATION IF NOT EXISTS mcp_claude_oauth            -- one integration can serve several MCP servers in the account
    TYPE = OAUTH                                                      -- Snowflake OAuth (not External OAuth / IdP)
    OAUTH_CLIENT = CUSTOM                                             -- custom client registration (MCP server has no dynamic registration)
    ENABLED = TRUE                                                    -- active immediately
    OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'                                -- claude.ai holds a client secret server-side
    OAUTH_REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback'    -- claude.ai connector callback (confirm in the connector dialog)
    OAUTH_USE_SECONDARY_ROLES = NONE                                  -- session uses DEFAULT_ROLE only; no secondary-role privilege creep
    ALLOWED_ROLES_LIST = ('MCP_CLAUDE_ROLE')                          -- tokens can only ever carry the narrow MCP role
    COMMENT = 'OAuth client for the Claude.ai Snowflake MCP connector';  -- documents purpose in SHOW INTEGRATIONS

-- ── Inspect configuration (safe to share) ────────────────────────
DESCRIBE SECURITY INTEGRATION mcp_claude_oauth;                       -- confirm redirect URI, allowed roles, secondary-role setting

-- ── Client credentials (DO NOT share output) ─────────────────────
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('MCP_CLAUDE_OAUTH');          -- integration name must be UPPERCASE; returns client id + secrets

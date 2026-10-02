-- ══════════════════════════════════════════════════════════════════
-- 04_mcp / 03 — OPTIONAL: separate read-only SQL MCP server
-- ══════════════════════════════════════════════════════════════════
-- Skip on first setup. Snowflake recommends NOT putting SYSTEM_EXECUTE_SQL
-- on the same server as the agent (it lets the client bypass the
-- semantic view and agent orchestration), and keeping direct SQL on its
-- own server.
--
-- Trade-off in this account: Snowflake's ideal is a separate dedicated
-- role too, but Claude always uses the signed-in user's DEFAULT_ROLE, so
-- a second role would need a second Snowflake user + second connector.
-- Here it reuses mcp_claude_role, which is bounded by read_only: true
-- (SELECT only) plus that role's narrow grants (two Silver DTs + the
-- semantic view) — it cannot see bronze, labs, or other databases.
--
-- Spec YAML has no inline comments (parsed by Snowflake's YAML loader).

-- ── Read-only SQL MCP server ─────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- MCP schema and servers are SYSADMIN-owned
CREATE MCP SERVER IF NOT EXISTS coco.mcp.ap_invoice_sql_mcp           -- URL path: /api/v2/databases/COCO/schemas/MCP/mcp-servers/AP_INVOICE_SQL_MCP
  FROM SPECIFICATION $$
  tools:
    - title: "Read-only SQL over AP invoice Silver layer"
      name: "ap-invoice-sql-readonly"
      type: "SYSTEM_EXECUTE_SQL"
      description: "Runs read-only SELECT queries against COCO.SILVER.DT_SILVER_AP_INVOICES and COCO.SILVER.DT_VENDOR_INVOICE_SUMMARY. Use only when the AP invoice agent cannot answer."
      config:
        read_only: true
        query_timeout: 60
        warehouse: "WH_COCO_PIPELINE"
  $$;

-- ── Grant connection to the Claude role ──────────────────────────
USE ROLE SECURITYADMIN;                                               -- grant administrator
GRANT USAGE ON MCP SERVER coco.mcp.ap_invoice_sql_mcp TO ROLE mcp_claude_role;  -- connect + discover the SQL tool

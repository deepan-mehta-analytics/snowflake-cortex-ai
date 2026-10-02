-- ══════════════════════════════════════════════════════════════════
-- 04_mcp / 00b — Rebuild the registered AP invoice agent before MCP
-- ══════════════════════════════════════════════════════════════════
-- Run after 00_mcp_role_and_user.sql and before 01_mcp_server.sql.
--
-- Why: DESCRIBE AGENT showed the registered object never matched
-- cortex_agent/agent_spec.yaml — Agent Studio's save bug (2026-07-16)
-- left it with only the Analyst tool (no Cortex Search tool), no
-- instructions, and generated SQL running on COMPUTE_WH, a warehouse
-- mcp_claude_role cannot use. Through MCP every agent call would fail.
--
-- Spec keys follow the current CREATE/ALTER AGENT + Agent REST docs:
-- execution_environment (not the legacy bare `warehouse` key) for the
-- Analyst tool, search_service for the Search tool, orchestration
-- model `auto`.
--
-- ALTER ... MODIFY LIVE VERSION swaps the spec on the existing object,
-- so the USAGE grant made in 00 is never touched. (First attempt used
-- CREATE OR REPLACE ... COPY GRANTS COMMENT = ...; the live parser
-- rejected COMMENT after COPY GRANTS despite the documented syntax.)
-- The new spec fully replaces the old one — omitted fields are removed.
--
-- NOTE: the YAML inside $$ … $$ carries no inline comments on purpose —
-- it is parsed by Snowflake's YAML loader (same rule as 01).

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- agent owner; owner can modify the live version

-- ── Replace the live spec with both tools ────────────────────────
ALTER AGENT coco.agent.ap_invoice_agent                               -- existing object, grants untouched
  MODIFY LIVE VERSION SET SPECIFICATION =                             -- full replacement of the live spec
  $$
  models:
    orchestration: auto
  instructions:
    response: "Answer concisely. State amounts with their currency; amounts are not converted between USD, EUR and GBP. Say which source systems the answer covers."
    orchestration: "Use ap_semantic_view for counts, totals, vendors, due dates, overdue amounts and approval status. Use ap_invoice_search to find invoices by what was bought, from the free-text line description."
    sample_questions:
      - question: "Which vendors have the most overdue invoices?"
      - question: "Find invoices for hydraulic equipment."
  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "ap_semantic_view"
        description: "Answers quantitative questions about invoices, vendors, amounts, due dates, currencies and approval status using the governed AP analytics semantic view."
    - tool_spec:
        type: "cortex_search"
        name: "ap_invoice_search"
        description: "Finds invoices by semantic match on the free-text line description, filterable by vendor, approval status, source system, cost center, GL account or PO number."
  tool_resources:
    ap_semantic_view:
      semantic_view: "COCO.SEMANTIC.SV_AP_ANALYTICS"
      execution_environment:
        type: "warehouse"
        warehouse: "WH_COCO_PIPELINE"
        query_timeout: 60
    ap_invoice_search:
      search_service: "COCO.AGENT.AP_INVOICE_SEARCH"
      max_results: 10
  $$;

-- ── Describe the agent ───────────────────────────────────────────
ALTER AGENT coco.agent.ap_invoice_agent SET                           -- metadata only, separate from the spec
  COMMENT = 'AP invoice agent: Cortex Analyst over sv_ap_analytics + Cortex Search over invoice line descriptions';  -- shown in SHOW AGENTS

-- ── Verify ───────────────────────────────────────────────────────
SHOW GRANTS ON AGENT coco.agent.ap_invoice_agent;                     -- expect USAGE → MCP_CLAUDE_ROLE (unchanged from 00)
DESCRIBE AGENT coco.agent.ap_invoice_agent;                           -- expect 2 tools and WH_COCO_PIPELINE in the spec

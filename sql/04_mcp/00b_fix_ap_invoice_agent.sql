-- ══════════════════════════════════════════════════════════════════
-- 04_mcp / 00b — Rebuild the registered AP invoice agent before MCP
-- ══════════════════════════════════════════════════════════════════
-- Runs on every deploy (scripts/deploy.py): creates the agent if missing,
-- then replaces its live spec.
--
-- Why: DESCRIBE AGENT showed the registered object never matched
-- the former cortex_agent/agent_spec.yaml (removed 2026-10-04; run_agent.py
-- now runs this object directly) — Agent Studio's save bug (2026-07-16)
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
-- v1.1.0: invoice_totals + review_status procedure tools; orchestration.tool_not_accessible = reject so a
-- role missing a procedure grant fails the run instead of silently skipping the tool (default: accept).
-- NOTE: the YAML inside $$ … $$ carries no inline comments on purpose —
-- it is parsed by Snowflake's YAML loader (same rule as 01).

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- agent owner; owner can modify the live version

-- ── Create on an empty account (no-op when it exists) ────────────
CREATE AGENT IF NOT EXISTS coco.agent.ap_invoice_agent                -- first deploy only; keeps grants + eval history otherwise
  FROM SPECIFICATION                                                  -- minimal spec; the ALTER below sets the real one
  $$
  models:
    orchestration: auto
-- ── Replace the live spec (4 tools; v1.1.0 adds the 2 procedures) ─

-- ── Replace the live spec with both tools ────────────────────────
ALTER AGENT coco.agent.ap_invoice_agent                               -- existing object, grants untouched
  MODIFY LIVE VERSION SET SPECIFICATION =                             -- full replacement of the live spec
  $$
  models:
    orchestration: auto
  orchestration:
    tool_not_accessible: reject
  instructions:
    response: "Answer concisely. State amounts with their currency; amounts are not converted between USD, EUR and GBP. Say which source systems the answer covers. This data is a snapshot as of 2025-06-30 (silver.reporting_calendar): treat 2025-06-30 as today for overdue, recent and other date-relative questions, and say so. Quote amount totals exactly as the tool result shows them; never add, subtract or average amounts yourself, because adding a long list of amounts by hand is where wrong totals come from. Adding a few small counts, such as 41 approved + 9 pending = 50 invoices, is fine. Give only the answer; do not describe your plan or the steps you will take."
    orchestration: "Use invoice_totals for any amount total, subtotal or invoice count per currency: overdue invoices as of a date (scope overdue) or all invoices issued by a date (scope all), optionally for one vendor; quote its total_amount exactly. Use review_status for BR-004 finance-review questions: which invoices need review (over USD 500,000 at invoice-date FX) and how close the largest invoices are to that limit. Use ap_semantic_view for lists of invoices, rankings, breakdowns by vendor or month, due dates and approval status; for any total or average it returns, have SQL compute it with SUM or AVG and GROUP BY currency_code, because amounts are in USD, EUR and GBP and are never converted. If the answer needs an amount total that no tool returned, call invoice_totals or run one more query rather than working it out. Use ap_invoice_search to find invoices by what was bought, from the free-text line description."
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
    - tool_spec:
        type: "generic"
        name: "invoice_totals"
        description: "Returns exact invoice counts and amount totals, one row per currency (currency_code, invoice_count, total_amount, as_of_date, scope). Overdue means issued on or before the as-of date and due before it. Never sums across currencies."
        input_schema:
          type: "object"
          properties:
            as_of_date:
              type: "string"
              description: "As-of date in ISO format, for example 2025-04-30. Leave empty for the reporting as-of date 2025-06-30."
            scope:
              type: "string"
              description: "overdue (default) for invoices past their due date, or all for every invoice issued by the as-of date."
            vendor_name:
              type: "string"
              description: "Exact vendor name to restrict the totals to one vendor. Leave empty for all vendors."
    - tool_spec:
        type: "generic"
        name: "review_status"
        description: "BR-004 finance review: rows of kind flagged are invoices over USD 500,000 at invoice-date FX or that cannot be assessed; rows of kind largest are the biggest invoices with their USD equivalent and percent of the USD 500,000 limit."
        input_schema:
          type: "object"
          properties:
            top_n:
              type: "number"
              description: "How many of the largest invoices to list. Default 3."
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
    invoice_totals:
      type: "procedure"
      identifier: "COCO.AGENT.INVOICE_TOTALS"
      execution_environment:
        type: "warehouse"
        warehouse: "WH_COCO_PIPELINE"
        query_timeout: 60
    review_status:
      type: "procedure"
      identifier: "COCO.AGENT.REVIEW_STATUS"
      execution_environment:
        type: "warehouse"
        warehouse: "WH_COCO_PIPELINE"
        query_timeout: 60
  $$;

-- ── Describe the agent ───────────────────────────────────────────
ALTER AGENT coco.agent.ap_invoice_agent SET                           -- metadata only, separate from the spec
  COMMENT = 'AP invoice agent: Cortex Analyst over sv_ap_analytics, Cortex Search over invoice line descriptions, invoice_totals + review_status procedure tools';  -- shown in SHOW AGENTS

-- ── Verify ───────────────────────────────────────────────────────
SHOW GRANTS ON AGENT coco.agent.ap_invoice_agent;                     -- expect USAGE → MCP_CLAUDE_ROLE (unchanged from 00)
DESCRIBE AGENT coco.agent.ap_invoice_agent;                           -- expect 2 tools and WH_COCO_PIPELINE in the spec

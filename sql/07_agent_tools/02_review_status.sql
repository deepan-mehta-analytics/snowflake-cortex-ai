-- ══════════════════════════════════════════════════════════════════
-- 07_agent_tools / 02 — review_status: BR-004 review queue for the agent
-- ══════════════════════════════════════════════════════════════════
-- Registered as a custom (generic) tool on coco.agent.ap_invoice_agent
-- (04_mcp/00b). Answers "which invoices need finance review, and how
-- close is anything to the threshold?".
--
-- Rows of kind 'flagged' come straight from the BR-004 review queue view
-- (05_guardrails/04_review_queue_view.sql), so the rule is never forked.
-- Rows of kind 'largest' are the top_n invoices by USD equivalent at
-- invoice-date FX. The two CTEs below are a copy of that view's FX join:
-- keep them in sync (same pattern as 05_guardrails/93_check_review_rule.sql).
-- Today the queue is empty (largest invoice USD 125,000 = 25% of the limit).
-- Grants live in sql/90_grants.sql, never here (deploy files hold no grants).

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of the agent schema objects
USE DATABASE coco;                                                    -- project database

-- ── Procedure ────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE agent.review_status(
    top_n NUMBER DEFAULT 3                                            -- how many of the largest invoices to list
)
RETURNS TABLE (row_kind VARCHAR, invoice_number VARCHAR, vendor_name VARCHAR, invoice_amount NUMBER(18,2),
               currency_code VARCHAR, usd_equivalent_amount NUMBER(18,2), percent_of_threshold NUMBER(6,1),
               review_reason VARCHAR)                                 -- flagged rows first, then the largest
LANGUAGE SQL                                                          -- Snowflake Scripting
EXECUTE AS OWNER                                                      -- callers need only USAGE on the procedure
COMMENT = 'Agent tool: BR-004 flagged invoices (> USD 500,000 at invoice-date FX) plus the largest invoices and % of the limit'  -- shown in SHOW PROCEDURES
AS
$$
DECLARE
    threshold_usd NUMBER(18,2) DEFAULT 500000;                        -- BR-004 limit in USD
    status_rows   RESULTSET;                                          -- the rows returned to the agent
BEGIN
    status_rows := (
        WITH latest_rate_date AS (                                    -- copy of 04_review_queue_view.sql: keep in sync
            SELECT i.invoice_number, i.vendor_name, i.invoice_date,   -- identifying columns
                   i.invoice_amount, i.currency_code,                 -- amount and currency
                   MAX(r.rate_date) AS fx_rate_date                   -- latest rate on or before the invoice date
            FROM coco.silver.dt_silver_ap_invoices i                  -- the real Silver invoices
            LEFT JOIN coco.guardrails.fx_rates r
                   ON r.currency_code = i.currency_code AND r.rate_date <= i.invoice_date  -- on or before
            GROUP BY i.invoice_id, i.source_system, i.invoice_number, i.vendor_name,
                     i.invoice_date, i.invoice_amount, i.currency_code  -- one row per invoice
        ),
        priced AS (                                                   -- USD equivalent per invoice
            SELECT l.invoice_number, l.vendor_name, l.invoice_amount, l.currency_code,  -- carried columns
                   ROUND(l.invoice_amount * IFF(l.currency_code = 'USD', 1, r.usd_per_unit), 2) AS usd_equivalent_amount  -- amount in USD
            FROM latest_rate_date l
            LEFT JOIN coco.guardrails.fx_rates r
                   ON r.currency_code = l.currency_code AND r.rate_date = l.fx_rate_date  -- the rate for that date
        )
        SELECT 'flagged' AS row_kind, q.invoice_number, q.vendor_name,             -- every invoice BR-004 flags
               q.invoice_amount::NUMBER(18,2), q.currency_code,                   -- original amount + currency
               q.usd_equivalent_amount::NUMBER(18,2),                             -- USD equivalent (NULL when unassessable)
               ROUND(q.usd_equivalent_amount / :threshold_usd * 100, 1)::NUMBER(6,1),  -- share of the limit
               q.review_reason                                                    -- why it is in the queue
        FROM coco.guardrails.high_value_invoices_for_review q                     -- the BR-004 rule itself
        UNION ALL
        SELECT 'largest', p.invoice_number, p.vendor_name,                        -- the largest invoices overall
               p.invoice_amount::NUMBER(18,2), p.currency_code,                   -- original amount + currency
               p.usd_equivalent_amount::NUMBER(18,2),                             -- USD equivalent
               ROUND(p.usd_equivalent_amount / :threshold_usd * 100, 1)::NUMBER(6,1),  -- share of the limit
               NULL                                                               -- not a review reason
        FROM priced p
        WHERE p.usd_equivalent_amount IS NOT NULL                                 -- unassessable ones are already 'flagged'
        QUALIFY ROW_NUMBER() OVER (ORDER BY p.usd_equivalent_amount DESC, p.invoice_number) <= :top_n  -- top_n by USD
        ORDER BY 1, 6 DESC NULLS FIRST                                            -- 'flagged' sorts before 'largest'; biggest USD first
    );
    RETURN TABLE(status_rows);                                        -- hand the rows to the caller
END;
$$;

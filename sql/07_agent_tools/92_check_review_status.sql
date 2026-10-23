-- ══════════════════════════════════════════════════════════════════
-- 07_agent_tools / 92 — check review_status against the live data
-- ══════════════════════════════════════════════════════════════════
-- Read-only. Run: python scripts/run_sql_checks.py sql/07_agent_tools/92_check_review_status.sql
-- One row per check: OUTCOME PASS / FAIL (exit 1 on any FAIL).
-- Expected values verified read-only on 2026-10-23 (queue empty; largest USD 125,000).

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- procedure owner
USE DATABASE coco;                                                    -- project database

-- ── Default call: no flagged rows, three largest invoices ────────
CALL agent.review_status();                                           -- top_n defaults to 3
WITH got AS (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))),      -- rows from the CALL above
largest AS (                                                          -- 'largest' rows ranked by USD
    SELECT *, ROW_NUMBER() OVER (ORDER BY "USD_EQUIVALENT_AMOUNT" DESC) AS rank_no
    FROM got WHERE "ROW_KIND" = 'largest'                             -- largest rows only
),
expected AS (                                                         -- the three largest at invoice-date FX
    SELECT column1 AS rank_no, column2 AS invoice_number, column3 AS usd_amount, column4 AS percent_of_limit FROM VALUES
        (1, 'ORA-INV-50008', 125000.00, 25.0), (2, 'INV-2025-0010', 92000.00, 18.4), (3, 'ORA-INV-50009', 71200.00, 14.2)
)
SELECT 'largest #' || e.rank_no || ' ' || e.invoice_number AS CHECK_NAME,  -- one check per rank
       e.usd_amount || ' USD / ' || e.percent_of_limit || '%' AS EXPECTED,    -- amount + share of the limit
       COALESCE(l."INVOICE_NUMBER" || ' ' || l."USD_EQUIVALENT_AMOUNT" || ' USD / ' || l."PERCENT_OF_THRESHOLD" || '%', 'missing') AS ACTUAL,  -- returned
       IFF(l."INVOICE_NUMBER" = e.invoice_number AND l."USD_EQUIVALENT_AMOUNT" = e.usd_amount
           AND l."PERCENT_OF_THRESHOLD" = e.percent_of_limit, 'PASS', 'FAIL') AS OUTCOME  -- verdict
FROM expected e LEFT JOIN largest l ON l.rank_no = e.rank_no          -- match by rank
UNION ALL
SELECT 'flagged rows = review queue view',                            -- the rule is not forked
       TO_VARCHAR((SELECT COUNT(*) FROM coco.guardrails.high_value_invoices_for_review)) AS EXPECTED,  -- queue size
       TO_VARCHAR(COUNT_IF("ROW_KIND" = 'flagged')) AS ACTUAL,        -- flagged rows returned
       IFF(COUNT_IF("ROW_KIND" = 'flagged') = (SELECT COUNT(*) FROM coco.guardrails.high_value_invoices_for_review), 'PASS', 'FAIL')  -- verdict
FROM got
UNION ALL
SELECT 'no invoice needs review today', '0', TO_VARCHAR(COUNT_IF("ROW_KIND" = 'flagged')),  -- the live queue is empty
       IFF(COUNT_IF("ROW_KIND" = 'flagged') = 0, 'PASS', 'FAIL')     -- verdict
FROM got
ORDER BY CHECK_NAME;                                                  -- stable order

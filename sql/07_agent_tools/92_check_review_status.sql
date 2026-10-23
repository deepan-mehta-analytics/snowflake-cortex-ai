-- ══════════════════════════════════════════════════════════════════
-- 07_agent_tools / 92 — check review_status against the live data
-- ══════════════════════════════════════════════════════════════════
-- Read-only. Run: python scripts/run_sql_checks.py sql/07_agent_tools/92_check_review_status.sql
-- One row per check: OUTCOME PASS / FAIL (exit 1 on any FAIL).
-- Expected values verified read-only on 2026-10-23 (queue empty; largest USD 125,000).
-- The procedure returns one VARIANT cell; the checks flatten its "invoices" array.

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- procedure owner
USE DATABASE coco;                                                    -- project database

-- ── Default call: no flagged invoices, three largest invoices ────
CALL agent.review_status();                                           -- top_n defaults to 3
WITH cell AS (SELECT $1 AS result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))),  -- the single cell from the CALL above
got AS (                                                              -- one row per listed invoice
    SELECT f.value:row_kind::VARCHAR AS row_kind, f.value:invoice_number::VARCHAR AS invoice_number,
           f.value:usd_equivalent_amount::NUMBER(18,2) AS usd_amount, f.value:percent_of_threshold::NUMBER(12,1) AS percent_of_limit
    FROM cell, LATERAL FLATTEN(input => cell.result:invoices) f       -- unpack the invoices array
),
largest AS (                                                          -- 'largest' rows ranked by USD
    SELECT *, ROW_NUMBER() OVER (ORDER BY usd_amount DESC) AS rank_no FROM got WHERE row_kind = 'largest'
),
expected AS (                                                         -- the three largest at invoice-date FX
    SELECT column1 AS rank_no, column2 AS invoice_number, column3 AS usd_amount, column4 AS percent_of_limit FROM VALUES
        (1, 'ORA-INV-50008', 125000.00, 25.0), (2, 'INV-2025-0010', 92000.00, 18.4), (3, 'ORA-INV-50009', 71200.00, 14.2)
)
SELECT 'largest #' || e.rank_no || ' ' || e.invoice_number AS CHECK_NAME,  -- one check per rank
       e.usd_amount || ' USD / ' || e.percent_of_limit || '%' AS EXPECTED,    -- amount + share of the limit
       COALESCE(l.invoice_number || ' ' || l.usd_amount || ' USD / ' || l.percent_of_limit || '%', 'missing') AS ACTUAL,  -- returned
       IFF(l.invoice_number = e.invoice_number AND l.usd_amount = e.usd_amount
           AND l.percent_of_limit = e.percent_of_limit, 'PASS', 'FAIL') AS OUTCOME  -- verdict
FROM expected e LEFT JOIN largest l ON l.rank_no = e.rank_no          -- match by rank
UNION ALL
SELECT 'flagged entries = review queue view',                         -- the rule is not forked
       TO_VARCHAR((SELECT COUNT(*) FROM coco.guardrails.high_value_invoices_for_review)),  -- queue size
       TO_VARCHAR(COUNT_IF(row_kind = 'flagged')),                    -- flagged entries returned
       IFF(COUNT_IF(row_kind = 'flagged') = (SELECT COUNT(*) FROM coco.guardrails.high_value_invoices_for_review), 'PASS', 'FAIL')  -- verdict
FROM got
UNION ALL
SELECT 'no invoice needs review today', '0', TO_VARCHAR(COUNT_IF(row_kind = 'flagged')),  -- the live queue is empty
       IFF(COUNT_IF(row_kind = 'flagged') = 0, 'PASS', 'FAIL')       -- verdict
FROM got
UNION ALL
SELECT 'threshold and flagged_count in the cell', '500000 / 0',       -- values the agent may quote
       (SELECT result:threshold_usd::VARCHAR || ' / ' || result:flagged_count::VARCHAR FROM cell),  -- returned
       IFF((SELECT result:threshold_usd::NUMBER FROM cell) = 500000 AND (SELECT result:flagged_count::NUMBER FROM cell) = 0, 'PASS', 'FAIL')  -- verdict
ORDER BY CHECK_NAME;                                                  -- stable order

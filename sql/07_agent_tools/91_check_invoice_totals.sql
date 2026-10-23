-- ══════════════════════════════════════════════════════════════════
-- 07_agent_tools / 91 — check invoice_totals against the answer keys
-- ══════════════════════════════════════════════════════════════════
-- No lasting changes (one session-only temporary table). Run: python scripts/run_sql_checks.py sql/07_agent_tools/91_check_invoice_totals.sql
-- One row per check: OUTCOME PASS / FAIL (exit 1 on any FAIL).
-- Warehouse seconds only, no AI credit.

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- procedure owner
USE DATABASE coco;                                                    -- project database

-- ── q11: overdue as of 30 April 2025 (golden answer key) ─────────
CALL agent.invoice_totals('2025-04-30', 'overdue', NULL);             -- the call the agent should make for q11
WITH got AS (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))),      -- rows from the CALL above
expected AS (                                                         -- q11 key: 22 invoices
    SELECT column1 AS currency_code, column2 AS invoice_count, column3 AS total_amount FROM VALUES
        ('EUR', 5, 101450.50), ('GBP', 3, 30600.00), ('USD', 14, 469300.00)
)
SELECT 'q11 overdue 2025-04-30 ' || e.currency_code AS CHECK_NAME,     -- one check per currency
       e.invoice_count || ' / ' || e.total_amount AS EXPECTED,        -- count / total from the key
       COALESCE(g."INVOICE_COUNT" || ' / ' || g."TOTAL_AMOUNT", 'missing') AS ACTUAL,  -- what the procedure returned
       IFF(g."INVOICE_COUNT" = e.invoice_count AND g."TOTAL_AMOUNT" = e.total_amount, 'PASS', 'FAIL') AS OUTCOME  -- verdict
FROM expected e LEFT JOIN got g ON g."CURRENCY_CODE" = e.currency_code  -- match by currency
ORDER BY CHECK_NAME;                                                  -- stable order

-- ── scope = all at the default date equals a plain SUM on Silver ──
CALL agent.invoice_totals(NULL, 'all', NULL);                         -- every invoice issued by 2025-06-30
WITH got AS (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))),      -- rows from the CALL above
plain AS (                                                            -- independent total straight from Silver
    SELECT currency_code, COUNT(*) AS invoice_count, SUM(invoice_amount)::NUMBER(18,2) AS total_amount
    FROM coco.silver.dt_silver_ap_invoices GROUP BY currency_code     -- all 50 invoices, by currency
)
SELECT 'all scope ' || p.currency_code AS CHECK_NAME,                  -- one check per currency
       p.invoice_count || ' / ' || p.total_amount AS EXPECTED,        -- plain SUM
       COALESCE(g."INVOICE_COUNT" || ' / ' || g."TOTAL_AMOUNT", 'missing') AS ACTUAL,  -- procedure result
       IFF(g."INVOICE_COUNT" = p.invoice_count AND g."TOTAL_AMOUNT" = p.total_amount, 'PASS', 'FAIL') AS OUTCOME  -- verdict
FROM plain p LEFT JOIN got g ON g."CURRENCY_CODE" = p.currency_code    -- match by currency
UNION ALL
SELECT 'all scope covers 50 invoices', '50', TO_VARCHAR(SUM(g."INVOICE_COUNT")),  -- every invoice is counted once
       IFF(SUM(g."INVOICE_COUNT") = 50, 'PASS', 'FAIL')               -- verdict
FROM got g;

-- ── No arguments = the reporting as-of date 2025-06-30 ───────────
CALL agent.invoice_totals();                                          -- all defaults
CREATE OR REPLACE TEMPORARY TABLE agent.default_call AS                           -- keep the default result for comparison
    SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));                -- rows from the CALL above
CALL agent.invoice_totals('2025-06-30', 'overdue', NULL);             -- the same date spelled out
WITH spelled AS (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())))   -- rows from that CALL
SELECT 'default date = 2025-06-30' AS CHECK_NAME,                     -- one check
       'identical rows' AS EXPECTED,                                  -- what we want
       (SELECT COUNT(*) FROM (SELECT * FROM agent.default_call MINUS SELECT * FROM spelled)) || ' differing rows' AS ACTUAL,  -- rows only in one result
       IFF((SELECT COUNT(*) FROM (SELECT * FROM agent.default_call MINUS SELECT * FROM spelled)) = 0
           AND (SELECT COUNT(*) FROM agent.default_call) = (SELECT COUNT(*) FROM spelled)
           AND (SELECT MAX("AS_OF_DATE") FROM agent.default_call) = '2025-06-30'::DATE, 'PASS', 'FAIL') AS OUTCOME;  -- verdict

-- ── An as-of date before any invoice returns no rows, not an error ─
CALL agent.invoice_totals('2024-01-01', 'overdue', NULL);             -- before the first invoice (2025-01-10)
SELECT 'date before the data → 0 rows' AS CHECK_NAME, '0' AS EXPECTED,  -- one check
       TO_VARCHAR(COUNT(*)) AS ACTUAL,                                -- rows returned
       IFF(COUNT(*) = 0, 'PASS', 'FAIL') AS OUTCOME                   -- verdict
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));                             -- rows from the CALL above

-- ── Part of a vendor name finds the vendor (q08: 'Acme') ─────────
CALL agent.invoice_totals(NULL, 'all', 'Acme');                       -- what the agent may send for "spend with Acme"
SELECT 'vendor Acme → Acme Industrial Supply' AS CHECK_NAME,          -- one check
       'USD 3 / 40700.00 / Acme Industrial Supply' AS EXPECTED,       -- q08 key
       COALESCE(MAX("CURRENCY_CODE") || ' ' || MAX("INVOICE_COUNT") || ' / ' || MAX("TOTAL_AMOUNT") || ' / ' || MAX("MATCHED_VENDORS"), 'missing') AS ACTUAL,  -- returned
       IFF(COUNT(*) = 1 AND MAX("CURRENCY_CODE") = 'USD' AND MAX("INVOICE_COUNT") = 3 AND MAX("TOTAL_AMOUNT") = 40700.00
           AND MAX("MATCHED_VENDORS") = 'Acme Industrial Supply', 'PASS', 'FAIL') AS OUTCOME  -- verdict
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));                             -- rows from the CALL above

-- ── Empty strings mean "not given" (a model may send '') ─────────
CALL agent.invoice_totals('', '', '');                                -- every input empty
WITH empties AS (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())))   -- rows from that CALL
SELECT 'empty strings = defaults' AS CHECK_NAME,                      -- one check
       'identical rows' AS EXPECTED,                                  -- same as the no-argument call
       (SELECT COUNT(*) FROM (SELECT * FROM agent.default_call MINUS SELECT * FROM empties)) || ' differing rows' AS ACTUAL,  -- rows only in one result
       IFF((SELECT COUNT(*) FROM (SELECT * FROM agent.default_call MINUS SELECT * FROM empties)) = 0
           AND (SELECT COUNT(*) FROM agent.default_call) = (SELECT COUNT(*) FROM empties), 'PASS', 'FAIL') AS OUTCOME;  -- verdict

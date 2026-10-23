-- ══════════════════════════════════════════════════════════════════
-- 07_agent_tools / 91 — check invoice_totals against the answer keys
-- ══════════════════════════════════════════════════════════════════
-- No lasting changes (one session-only temporary table). Run: python scripts/run_sql_checks.py sql/07_agent_tools/91_check_invoice_totals.sql
-- One row per check: OUTCOME PASS / FAIL (exit 1 on any FAIL).
-- Warehouse seconds only, no AI credit. The procedure returns one VARIANT
-- cell; each check flattens its "totals" array into rows.

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- procedure owner
USE DATABASE coco;                                                    -- project database

-- ── q11: overdue as of 30 April 2025 (golden answer key) ─────────
CALL agent.invoice_totals('2025-04-30', 'overdue', NULL);             -- the call the agent makes for q11
WITH cell AS (SELECT $1 AS result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))),  -- the single cell from the CALL above
got AS (                                                              -- one row per currency
    SELECT f.value:currency_code::VARCHAR AS currency_code, f.value:invoice_count::NUMBER AS invoice_count,
           f.value:total_amount::NUMBER(18,2) AS total_amount
    FROM cell, LATERAL FLATTEN(input => cell.result:totals) f         -- unpack the totals array
),
expected AS (                                                         -- q11 key: 22 invoices
    SELECT column1 AS currency_code, column2 AS invoice_count, column3 AS total_amount FROM VALUES
        ('EUR', 5, 101450.50), ('GBP', 3, 30600.00), ('USD', 14, 469300.00)
)
SELECT 'q11 overdue 2025-04-30 ' || e.currency_code AS CHECK_NAME,     -- one check per currency
       e.invoice_count || ' / ' || e.total_amount AS EXPECTED,        -- count / total from the key
       COALESCE(g.invoice_count || ' / ' || g.total_amount, 'missing') AS ACTUAL,  -- what the procedure returned
       IFF(g.invoice_count = e.invoice_count AND g.total_amount = e.total_amount, 'PASS', 'FAIL') AS OUTCOME  -- verdict
FROM expected e LEFT JOIN got g ON g.currency_code = e.currency_code  -- match by currency
UNION ALL
SELECT 'q11 returns exactly 3 currencies', '3', TO_VARCHAR(COUNT(*)), IFF(COUNT(*) = 3, 'PASS', 'FAIL') FROM got  -- no extra rows
ORDER BY CHECK_NAME;                                                  -- stable order

-- ── scope = all at the default date equals a plain SUM on Silver ──
CALL agent.invoice_totals(NULL, 'all', NULL);                         -- every invoice issued by 2025-06-30
WITH cell AS (SELECT $1 AS result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))),  -- the single cell from the CALL above
got AS (                                                              -- one row per currency
    SELECT f.value:currency_code::VARCHAR AS currency_code, f.value:invoice_count::NUMBER AS invoice_count,
           f.value:total_amount::NUMBER(18,2) AS total_amount
    FROM cell, LATERAL FLATTEN(input => cell.result:totals) f         -- unpack the totals array
),
plain AS (                                                            -- independent total straight from Silver
    SELECT currency_code, COUNT(*) AS invoice_count, SUM(invoice_amount)::NUMBER(18,2) AS total_amount
    FROM coco.silver.dt_silver_ap_invoices GROUP BY currency_code     -- all 50 invoices, by currency
)
SELECT 'all scope ' || p.currency_code AS CHECK_NAME,                  -- one check per currency
       p.invoice_count || ' / ' || p.total_amount AS EXPECTED,        -- plain SUM
       COALESCE(g.invoice_count || ' / ' || g.total_amount, 'missing') AS ACTUAL,  -- procedure result
       IFF(g.invoice_count = p.invoice_count AND g.total_amount = p.total_amount, 'PASS', 'FAIL') AS OUTCOME  -- verdict
FROM plain p LEFT JOIN got g ON g.currency_code = p.currency_code      -- match by currency
UNION ALL
SELECT 'all scope covers 50 invoices', '50', TO_VARCHAR(SUM(g.invoice_count)),  -- every invoice is counted once
       IFF(SUM(g.invoice_count) = 50, 'PASS', 'FAIL')                 -- verdict
FROM got g;

-- ── No arguments = the reporting as-of date 2025-06-30 ───────────
CALL agent.invoice_totals();                                          -- all defaults
CREATE OR REPLACE TEMPORARY TABLE agent.default_call AS               -- keep the default cell for comparison
    SELECT $1 AS result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));     -- the single cell from the CALL above
CALL agent.invoice_totals('2025-06-30', 'overdue', NULL);             -- the same date spelled out
SELECT 'default date = 2025-06-30' AS CHECK_NAME,                     -- one check
       'identical result, as_of_date 2025-06-30' AS EXPECTED,         -- what we want
       (SELECT result:as_of_date::VARCHAR FROM agent.default_call) AS ACTUAL,  -- date the default call used
       IFF((SELECT result FROM agent.default_call) = $1
           AND (SELECT result:as_of_date::VARCHAR FROM agent.default_call) = '2025-06-30', 'PASS', 'FAIL') AS OUTCOME  -- verdict
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));                             -- the spelled-out call's cell

-- ── An as-of date before any invoice returns no totals, not an error ─
CALL agent.invoice_totals('2024-01-01', 'overdue', NULL);             -- before the first invoice (2025-01-10)
SELECT 'date before the data → empty totals' AS CHECK_NAME, '0' AS EXPECTED,  -- one check
       TO_VARCHAR(ARRAY_SIZE($1:totals)) AS ACTUAL,                   -- entries returned
       IFF(ARRAY_SIZE($1:totals) = 0, 'PASS', 'FAIL') AS OUTCOME      -- verdict
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));                             -- the cell from the CALL above

-- ── Part of a vendor name finds the vendor (q08: 'Acme') ─────────
CALL agent.invoice_totals(NULL, 'all', 'Acme');                       -- what the agent sends for "spend with Acme" (seen live)
WITH cell AS (SELECT $1 AS result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))),  -- the single cell from the CALL above
got AS (                                                              -- one row per currency
    SELECT f.value:currency_code::VARCHAR AS currency_code, f.value:invoice_count::NUMBER AS invoice_count,
           f.value:total_amount::NUMBER(18,2) AS total_amount, f.value:matched_vendors::VARCHAR AS matched_vendors
    FROM cell, LATERAL FLATTEN(input => cell.result:totals) f         -- unpack the totals array
)
SELECT 'vendor Acme → Acme Industrial Supply' AS CHECK_NAME,          -- one check
       'USD 3 / 40700.00 / Acme Industrial Supply' AS EXPECTED,       -- q08 key
       COALESCE(MAX(currency_code) || ' ' || MAX(invoice_count) || ' / ' || MAX(total_amount) || ' / ' || MAX(matched_vendors), 'missing') AS ACTUAL,  -- returned
       IFF(COUNT(*) = 1 AND MAX(currency_code) = 'USD' AND MAX(invoice_count) = 3 AND MAX(total_amount) = 40700.00
           AND MAX(matched_vendors) = 'Acme Industrial Supply', 'PASS', 'FAIL') AS OUTCOME  -- verdict
FROM got;

-- ── Empty strings mean "not given" (a model may send '') ─────────
CALL agent.invoice_totals('', '', '');                                -- every input empty
SELECT 'empty strings = defaults' AS CHECK_NAME,                      -- one check
       'identical result' AS EXPECTED,                                -- same as the no-argument call
       IFF((SELECT result FROM agent.default_call) = $1, 'identical', 'different') AS ACTUAL,  -- compared cells
       IFF((SELECT result FROM agent.default_call) = $1, 'PASS', 'FAIL') AS OUTCOME  -- verdict
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));                             -- the cell from the CALL above

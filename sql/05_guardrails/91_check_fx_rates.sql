-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 91 — checks for guardrails.fx_rates
-- ══════════════════════════════════════════════════════════════════
-- Expected values verified live on 2026-10-03 against the free FX dataset.

-- ── Rates used by the seeded test cases ──────────────────────────
SELECT 'eur_2025_03_03' AS check_name, 1.0465 AS expected,                                     -- ECB EUR→USD, Mon 2025-03-03
       (SELECT usd_per_unit FROM coco.guardrails.fx_rates WHERE currency_code = 'EUR' AND rate_date = '2025-03-03') AS actual,  -- view lookup
       IFF(ROUND(actual, 4) = expected, 'PASS', 'FAIL') AS outcome;                            -- compare at 4 dp
SELECT 'gbp_2025_02_28' AS check_name, 1.2603 AS expected,                                     -- GBP→USD, Fri 2025-02-28
       (SELECT usd_per_unit FROM coco.guardrails.fx_rates WHERE currency_code = 'GBP' AND rate_date = '2025-02-28') AS actual,  -- view lookup
       IFF(ROUND(actual, 4) = expected, 'PASS', 'FAIL') AS outcome;                            -- compare at 4 dp
SELECT 'gbp_2025_03_03' AS check_name, 1.268 AS expected,                                      -- GBP→USD, Mon 2025-03-03
       (SELECT usd_per_unit FROM coco.guardrails.fx_rates WHERE currency_code = 'GBP' AND rate_date = '2025-03-03') AS actual,  -- view lookup
       IFF(ROUND(actual, 4) = expected, 'PASS', 'FAIL') AS outcome;                            -- compare at 4 dp

-- ── Precision: weak currencies use 1 ÷ (USD→X), not the 4-dp-rounded X→USD ──
SELECT 'jpy_2025_03_03_full_precision' AS check_name, 0.006609695 AS expected,                 -- 1 ÷ 151.2929 (stored jpy_usd is 0.0066)
       (SELECT usd_per_unit FROM coco.guardrails.fx_rates WHERE currency_code = 'JPY' AND rate_date = '2025-03-03') AS actual,  -- view lookup
       IFF(ROUND(actual, 9) = expected, 'PASS', 'FAIL') AS outcome;                            -- compare at 9 dp
SELECT 'cop_2025_03_03_full_precision' AS check_name, 0.000241894 AS expected,                 -- 1 ÷ 4134.04 (stored cop_usd is 0.0002, 17% off)
       (SELECT usd_per_unit FROM coco.guardrails.fx_rates WHERE currency_code = 'COP' AND rate_date = '2025-03-03') AS actual,  -- view lookup
       IFF(ROUND(actual, 9) = expected, 'PASS', 'FAIL') AS outcome;                            -- compare at 9 dp

-- ── Shape guarantees the DMF relies on ───────────────────────────
SELECT 'one_row_per_currency_and_date' AS check_name, 0 AS expected,                           -- no duplicate dates per currency
       (SELECT COUNT(*) FROM (SELECT currency_code, rate_date FROM coco.guardrails.fx_rates
                              GROUP BY 1, 2 HAVING COUNT(*) > 1)) AS actual,                   -- duplicate (currency, date) pairs
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- PASS when unique
SELECT 'no_gbp_weekend_rate_2025_03_02' AS check_name, 0 AS expected,                          -- the GBP weekend fallback test needs a gap
       (SELECT COUNT(*) FROM coco.guardrails.fx_rates
         WHERE currency_code = 'GBP' AND rate_date = '2025-03-02') AS actual,                  -- GBP Sunday rows (COP/AED/BAM do publish on Sundays)
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- PASS when absent
SELECT 'no_xts_rates' AS check_name, 0 AS expected,                                            -- fail-safe test currency must be absent
       (SELECT COUNT(*) FROM coco.guardrails.fx_rates WHERE currency_code = 'XTS') AS actual,  -- XTS rows
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- PASS when absent

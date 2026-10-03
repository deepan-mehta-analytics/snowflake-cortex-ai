-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 92 — direct DMF calls (not billed) on fixture, Silver, edge cases
-- ══════════════════════════════════════════════════════════════════

-- ── Seeded fixture: cases 1, 3, 6 flagged ────────────────────────
SELECT 'dmf_fixture_count' AS check_name, 3 AS expected,
       coco.guardrails.count_invoices_over_usd_500k(
           (SELECT source_system, invoice_id, invoice_amount, currency_code, invoice_date
              FROM coco.guardrails_test.silver_invoices_test_synthetic),                      -- invoices argument
           (SELECT currency_code, rate_date, usd_per_unit FROM coco.guardrails.fx_rates)       -- rates argument
       ) AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- PASS when exactly 3

-- ── Real Silver: nothing over 500K today ─────────────────────────
SELECT 'dmf_silver_count' AS check_name, 0 AS expected,
       coco.guardrails.count_invoices_over_usd_500k(
           (SELECT source_system, invoice_id, invoice_amount, currency_code, invoice_date
              FROM coco.silver.dt_silver_ap_invoices),                                         -- 50 real invoices
           (SELECT currency_code, rate_date, usd_per_unit FROM coco.guardrails.fx_rates)       -- rates argument
       ) AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- PASS when 0

-- ── Review Focus 1: dated after the last free rate (2026-07-03) uses the older rate ──
SELECT 'stale_rate_not_treated_as_missing' AS check_name, 0 AS expected,
       coco.guardrails.count_invoices_over_usd_500k(
           (SELECT source_system, invoice_id, invoice_amount, currency_code, invoice_date
              FROM coco.guardrails_test.edge_rf_1),                        -- small EUR invoice, recent date
           (SELECT currency_code, rate_date, usd_per_unit FROM coco.guardrails.fx_rates)
       ) AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- 0 = a rate was found (not fail-safe)

-- ── Review Focus 2: non-ISO casing has no rate → fail-safe flags it ──
SELECT 'lowercase_currency_flagged' AS check_name, 1 AS expected,
       coco.guardrails.count_invoices_over_usd_500k(
           (SELECT source_system, invoice_id, invoice_amount, currency_code, invoice_date
              FROM coco.guardrails_test.edge_rf_2),                         -- 'eur' ≠ 'EUR'
           (SELECT currency_code, rate_date, usd_per_unit FROM coco.guardrails.fx_rates)
       ) AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- PASS when flagged

-- ── Review Focus 3: missing amount → fail-safe flags it ──────────
SELECT 'null_amount_flagged' AS check_name, 1 AS expected,
       coco.guardrails.count_invoices_over_usd_500k(
           (SELECT source_system, invoice_id, invoice_amount, currency_code, invoice_date
              FROM coco.guardrails_test.edge_rf_3),                         -- amount unknown
           (SELECT currency_code, rate_date, usd_per_unit FROM coco.guardrails.fx_rates)
       ) AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- PASS when flagged

-- ── Review Focus 4: large credit note is not "> 500,000" ─────────
SELECT 'credit_note_not_flagged' AS check_name, 0 AS expected,
       coco.guardrails.count_invoices_over_usd_500k(
           (SELECT source_system, invoice_id, invoice_amount, currency_code, invoice_date
              FROM coco.guardrails_test.edge_rf_4),                      -- negative amount
           (SELECT currency_code, rate_date, usd_per_unit FROM coco.guardrails.fx_rates)
       ) AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- documented limitation

-- ── Review Focus 5: same invoice_id in two sources counts twice ──
SELECT 'same_id_two_sources_counted_twice' AS check_name, 2 AS expected,
       coco.guardrails.count_invoices_over_usd_500k(
           (SELECT source_system, invoice_id, invoice_amount, currency_code, invoice_date
              FROM coco.guardrails_test.edge_dup_1),                    -- same id, two systems
           (SELECT currency_code, rate_date, usd_per_unit FROM coco.guardrails.fx_rates)
       ) AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- PASS when 2

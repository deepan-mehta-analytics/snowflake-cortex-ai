-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 93 — review-queue rule on the fixture; real view on Silver
-- ══════════════════════════════════════════════════════════════════
-- The view below is a copy of the body of 04_review_queue_view.sql with the
-- source table swapped for the fixture. Keep the two in sync.

-- ── Rule applied to the fixture ──────────────────────────────────
CREATE OR REPLACE TEMPORARY VIEW coco.guardrails_test.review_rule_on_fixture AS                -- session-only copy
WITH latest_rate_date AS (
    SELECT i.source_system, i.invoice_id, i.invoice_number, i.vendor_name,                     -- identifying columns
           i.invoice_date, i.invoice_amount, i.currency_code,                                  -- amount and currency
           MAX(r.rate_date) AS fx_rate_date                                                    -- latest rate on or before the invoice date
    FROM coco.guardrails_test.silver_invoices_test_synthetic i                                  -- fixture instead of Silver
    LEFT JOIN coco.guardrails.fx_rates r
           ON r.currency_code = i.currency_code AND r.rate_date <= i.invoice_date              -- on or before
    GROUP BY i.source_system, i.invoice_id, i.invoice_number, i.vendor_name,
             i.invoice_date, i.invoice_amount, i.currency_code                                  -- one row per invoice
),
matched AS (
    SELECT l.source_system, l.invoice_id, l.invoice_number, l.vendor_name,                     -- identifying columns
           l.invoice_date, l.invoice_amount, l.currency_code,                                  -- amount and currency
           IFF(l.currency_code = 'USD', 1, r.usd_per_unit)                   AS usd_per_unit,  -- rate used
           IFF(l.currency_code = 'USD', l.invoice_date, l.fx_rate_date)      AS rate_date,     -- date of that rate
           IFF(l.currency_code = 'USD', 'USD (no conversion)', r.rate_source) AS rate_source   -- provider
    FROM latest_rate_date l
    LEFT JOIN coco.guardrails.fx_rates r
           ON r.currency_code = l.currency_code AND r.rate_date = l.fx_rate_date               -- the rate for that date
)
SELECT *,
       DATEDIFF('day', rate_date, invoice_date)    AS rate_age_days,                           -- staleness of the rate
       ROUND(invoice_amount * usd_per_unit, 2)     AS usd_equivalent_amount,                   -- amount in USD
       CASE WHEN invoice_amount IS NULL THEN 'missing invoice amount'                          -- fail-safe reason 1
            WHEN usd_per_unit IS NULL   THEN 'no FX rate for ' || currency_code                -- fail-safe reason 2
            ELSE 'over USD 500,000' END            AS review_reason                            -- threshold reason
FROM matched
WHERE invoice_amount IS NULL OR usd_per_unit IS NULL OR invoice_amount * usd_per_unit > 500000;  -- flagged only

SELECT 'review_rule_flagged_ids' AS check_name, 'TEST-1,TEST-3,TEST-6' AS expected,            -- cases 1, 3, 6
       (SELECT LISTAGG(invoice_id, ',') WITHIN GROUP (ORDER BY invoice_id)
          FROM coco.guardrails_test.review_rule_on_fixture) AS actual,                         -- flagged ids
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;
SELECT 'review_rule_eur_usd_amount' AS check_name, 502320.00 AS expected,                      -- 480,000 × 1.0465
       (SELECT usd_equivalent_amount FROM coco.guardrails_test.review_rule_on_fixture WHERE invoice_id = 'TEST-3') AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;
SELECT 'review_rule_xts_reason' AS check_name, 'no FX rate for XTS' AS expected,               -- fail-safe reason text
       (SELECT review_reason FROM coco.guardrails_test.review_rule_on_fixture WHERE invoice_id = 'TEST-6') AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;
SELECT 'review_rule_usd_rate_fields' AS check_name, 'USD (no conversion)|0' AS expected,       -- USD conventions
       (SELECT rate_source || '|' || rate_age_days FROM coco.guardrails_test.review_rule_on_fixture WHERE invoice_id = 'TEST-1') AS actual,
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;

-- ── Real view on Silver: empty today ─────────────────────────────
SELECT 'review_view_silver_rows' AS check_name, 0 AS expected,
       (SELECT COUNT(*) FROM coco.guardrails.high_value_invoices_for_review) AS actual,        -- flagged Silver invoices
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;

-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 04 — review queue: every invoice BR-004 flags
-- ══════════════════════════════════════════════════════════════════
-- Same rule as the DMF (02). Finance works through this list; it is
-- expected work, not an alert. Silver itself is never filtered.
-- 93_check_review_rule.sql holds a copy of this body run on the fixture: keep them in sync.

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of the guardrails schema
USE DATABASE coco;                                                    -- project database

-- ── Review queue view ────────────────────────────────────────────
CREATE OR REPLACE VIEW guardrails.high_value_invoices_for_review
    COMMENT = 'BR-004 review queue: invoices > USD 500,000 at invoice-date FX, or unassessable (fail-safe)'
AS
WITH latest_rate_date AS (
    SELECT i.source_system, i.invoice_id, i.invoice_number, i.vendor_name,                     -- identifying columns
           i.invoice_date, i.invoice_amount, i.currency_code,                                  -- amount and currency
           MAX(r.rate_date) AS fx_rate_date                                                    -- latest rate on or before the invoice date
    FROM coco.silver.dt_silver_ap_invoices i                                                   -- the real Silver invoices
    LEFT JOIN guardrails.fx_rates r
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
    LEFT JOIN guardrails.fx_rates r
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

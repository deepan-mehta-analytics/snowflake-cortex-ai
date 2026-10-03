-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 02 — DMF: invoices over USD 500,000 (BR-004)
-- ══════════════════════════════════════════════════════════════════
-- Counts invoices that are high-value OR cannot be assessed (fail-safe):
--   * amount missing                          → flagged
--   * no FX rate on or before the invoice date → flagged
--   * amount × USD rate > 500,000 (strict)    → flagged
-- USD converts at 1. Other currencies use the latest rate on or before
-- invoice_date (weekend/holiday fallback). Key = (source_system, invoice_id).

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of the guardrails schema
USE DATABASE coco;                                                    -- project database

-- ── Data Metric Function ─────────────────────────────────────────
CREATE OR REPLACE DATA METRIC FUNCTION guardrails.count_invoices_over_usd_500k(
    invoices TABLE(source_system VARCHAR, invoice_id VARCHAR, invoice_amount NUMBER,
                   currency_code VARCHAR, invoice_date DATE),         -- the table the DMF is attached to
    rates    TABLE(currency_code VARCHAR, rate_date DATE, usd_per_unit FLOAT)  -- guardrails.fx_rates
)
RETURNS NUMBER                                                        -- DMFs must return a single NUMBER
COMMENT = 'BR-004: count of invoices > USD 500,000 at invoice-date FX, plus unassessable invoices (fail-safe)'
AS
$$
    SELECT COUNT_IF(m.invoice_amount IS NULL                         -- fail-safe: amount unknown
                    OR IFF(m.currency_code = 'USD', 1, r.usd_per_unit) IS NULL  -- fail-safe: no usable FX rate
                    OR m.invoice_amount * IFF(m.currency_code = 'USD', 1, r.usd_per_unit) > 500000)  -- strictly over the line
    FROM (
        SELECT i.source_system,                                      -- part of the invoice key
               i.invoice_id,                                         -- part of the invoice key
               i.invoice_amount,                                     -- original-currency amount
               i.currency_code,                                      -- currency to convert
               MAX(r.rate_date) AS rate_date                         -- latest rate date on or before the invoice date
        FROM invoices i
        LEFT JOIN rates r                                            -- keep invoices with no matching rate
               ON r.currency_code = i.currency_code                  -- same currency
              AND r.rate_date <= i.invoice_date                      -- on or before the invoice date
        GROUP BY i.source_system, i.invoice_id, i.invoice_amount, i.currency_code  -- one row per invoice
    ) m
    LEFT JOIN rates r                                                -- fetch the rate for that date (MAX_BY is not allowed in a DMF)
           ON r.currency_code = m.currency_code                      -- same currency
          AND r.rate_date = m.rate_date                              -- unique per (currency, date) — checked in 91
$$;

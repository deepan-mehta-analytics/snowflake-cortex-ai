-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 01 — Guardrails Pack schema + FX rates view (BR-004)
-- ══════════════════════════════════════════════════════════════════
-- FX rates come from Snowflake's free public dataset (ECB/BIS daily rates).
-- They are INDICATIVE market rates, a stand-in for Treasury's corporate
-- rates (BR-002). Replace this view's source when Treasury's table exists.

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of the coco pipeline schemas
USE DATABASE coco;                                                    -- project database

-- ── Schema ───────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS guardrails                                -- the "Guardrails Pack" BR-004 asks for
    COMMENT = 'BR-004 data-quality guardrails: high-value invoice checks, review queue, alert';  -- purpose

-- ── FX rates (USD per 1 unit of currency_code) ───────────────────
-- The dataset stores rates rounded to 4 decimal places. For currencies worth
-- less than 1 USD that loses precision (COP→USD 0.0002 vs true 0.000241894,
-- 17% off), so those use 1 ÷ (USD→currency), which keeps the digits.
CREATE OR REPLACE VIEW guardrails.fx_rates                            -- single swap point for Treasury rates later
    COMMENT = 'Indicative USD rates from SNOWFLAKE_PUBLIC_DATA_FREE (ECB/BIS); one row per currency per date'  -- purpose
AS
WITH candidates AS (
    SELECT base_currency_id                  AS currency_code,        -- currency being converted (EUR, GBP, ...)
           date                              AS rate_date,            -- publication date
           value                             AS usd_per_unit,         -- direct quote: USD per 1 unit
           provenance:source::VARCHAR        AS rate_source,          -- e.g. 'ECB'
           IFF(value >= 1, 0, 1)             AS precision_rank        -- direct is precise when the value is >= 1
    FROM snowflake_public_data_free.public_data_free.fx_rates_timeseries  -- free Snowflake Public Data listing
    WHERE quote_currency_id = 'USD' AND base_currency_id <> 'USD'     -- currency → USD quotes
    UNION ALL
    SELECT quote_currency_id                 AS currency_code,        -- currency being converted
           date                              AS rate_date,            -- publication date
           1 / value                         AS usd_per_unit,         -- inverted: 1 ÷ (USD → currency)
           provenance:source::VARCHAR || ' (inverse)' AS rate_source, -- e.g. 'BIS (inverse)'
           IFF(value > 1, 0, 1)              AS precision_rank        -- inverse is precise when USD→X is > 1
    FROM snowflake_public_data_free.public_data_free.fx_rates_timeseries  -- same listing
    WHERE base_currency_id = 'USD' AND quote_currency_id <> 'USD' AND value > 0  -- USD → currency quotes
)
SELECT currency_code, rate_date, usd_per_unit, rate_source            -- the 4 columns the DMF and review view read
FROM candidates
QUALIFY ROW_NUMBER() OVER (                                           -- keep one row per currency and date
    PARTITION BY currency_code, rate_date                             -- the uniqueness the DMF relies on
    ORDER BY precision_rank,                                          -- most significant digits first
             IFF(rate_source LIKE 'ECB%', 0, 1)                       -- then prefer ECB
) = 1;

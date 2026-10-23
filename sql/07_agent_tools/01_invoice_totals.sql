-- ══════════════════════════════════════════════════════════════════
-- 07_agent_tools / 01 — invoice_totals: exact totals per currency
-- ══════════════════════════════════════════════════════════════════
-- Registered as a custom (generic) tool on coco.agent.ap_invoice_agent
-- (04_mcp/00b). Why it exists: in v1.0.0 the agent sometimes added a
-- long list of amounts in its own answer text and got the total wrong
-- (q11: USD 709,300 instead of 469,300). This procedure returns the
-- totals from the data, and the amount checks in eval/ and
-- cortex_agent/ treat its output as the trusted source.
--
-- Overdue = issued on or before the as-of date AND due before it (no
-- paid/unpaid flag in the sample data). Default as-of date comes from
-- silver.reporting_calendar (2025-06-30). Amounts are never converted
-- or summed across currencies (BR-002).
-- Grants live in sql/90_grants.sql, never here (deploy files hold no grants).

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of the agent schema objects
USE DATABASE coco;                                                    -- project database

-- ── Procedure ────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE agent.invoice_totals(
    as_of_date  VARCHAR DEFAULT NULL,                                 -- ISO date 'YYYY-MM-DD'; NULL or '' = reporting as-of date
    scope       VARCHAR DEFAULT 'overdue',                            -- 'overdue' or 'all' (every invoice issued by the date); NULL or '' = overdue
    vendor_name VARCHAR DEFAULT NULL                                  -- whole or part of a vendor name, any case ('Acme'); NULL or '' = all vendors
)
RETURNS TABLE (currency_code VARCHAR, invoice_count NUMBER, total_amount NUMBER(18,2), as_of_date DATE, scope VARCHAR,
               matched_vendors VARCHAR)                               -- one row per currency, naming the vendor(s) counted
LANGUAGE SQL                                                          -- Snowflake Scripting
COMMENT = 'Agent tool: exact invoice counts and amount totals per currency, overdue or all, as of a date, optionally one vendor'  -- shown in SHOW PROCEDURES
EXECUTE AS OWNER                                                      -- callers need only USAGE on the procedure
AS
$$
DECLARE
    report_date    DATE;                                              -- the as-of date actually used
    chosen_date    VARCHAR;                                           -- as_of_date with '' treated as not given
    chosen_scope   VARCHAR;                                           -- normalised scope
    chosen_vendor  VARCHAR;                                           -- vendor filter with '' treated as not given
    bad_scope      EXCEPTION (-20001, 'scope must be overdue or all');  -- clear error for a wrong scope
    bad_date       EXCEPTION (-20002, 'as_of_date must be an ISO date like 2025-04-30');  -- clear error for an unreadable date
    totals         RESULTSET;                                         -- the rows returned to the agent
BEGIN
    chosen_date   := NULLIF(TRIM(:as_of_date), '');                   -- a model may send '' for "not given"
    chosen_scope  := LOWER(COALESCE(NULLIF(TRIM(:scope), ''), 'overdue'));  -- NULL or '' means the default
    chosen_vendor := NULLIF(TRIM(:vendor_name), '');                  -- '' must not filter everything out
    IF (chosen_scope NOT IN ('overdue', 'all')) THEN                  -- only two scopes exist
        RAISE bad_scope;                                              -- stop with the clear message
    END IF;
    IF (chosen_date IS NULL) THEN                                     -- no date given
        SELECT MAX(as_of_date) INTO :report_date                      -- the one reporting as-of date
        FROM coco.silver.reporting_calendar;                          -- 2025-06-30 for this snapshot
    ELSE
        report_date := TRY_TO_DATE(chosen_date);                      -- parse the caller's date
        IF (report_date IS NULL) THEN                                 -- unreadable date: never fall back silently
            RAISE bad_date;                                           -- stop with the clear message
        END IF;
    END IF;
    totals := (
        SELECT currency_code,                                         -- USD, EUR or GBP
               COUNT(*)                         AS invoice_count,     -- invoices in scope
               SUM(invoice_amount)::NUMBER(18,2) AS total_amount,     -- exact total in that currency
               :report_date                     AS as_of_date,        -- echo the date used
               :chosen_scope                    AS scope,             -- echo the scope used
               LISTAGG(DISTINCT vendor_name, ', ') WITHIN GROUP (ORDER BY vendor_name) AS matched_vendors  -- who was counted
        FROM coco.silver.dt_silver_ap_invoices                        -- same Silver table as the semantic view
        WHERE invoice_date <= :report_date                            -- issued by the as-of date
          AND (:chosen_scope = 'all' OR due_date < :report_date)      -- overdue: due before the as-of date
          AND (:chosen_vendor IS NULL OR vendor_name ILIKE '%' || :chosen_vendor || '%')  -- optional vendor filter, part of the name is enough
        GROUP BY currency_code                                        -- never sum across currencies
        ORDER BY currency_code                                        -- stable order: EUR, GBP, USD
    );
    RETURN TABLE(totals);                                             -- hand the rows to the caller
END;
$$;

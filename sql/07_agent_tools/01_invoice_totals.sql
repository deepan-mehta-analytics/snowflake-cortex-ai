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
    as_of_date  VARCHAR DEFAULT NULL,                                 -- ISO date 'YYYY-MM-DD'; NULL = reporting as-of date
    scope       VARCHAR DEFAULT 'overdue',                            -- 'overdue' or 'all' (every invoice issued by the date)
    vendor_name VARCHAR DEFAULT NULL                                  -- exact vendor name, any case; NULL = all vendors
)
RETURNS TABLE (currency_code VARCHAR, invoice_count NUMBER, total_amount NUMBER(18,2), as_of_date DATE, scope VARCHAR)  -- one row per currency
LANGUAGE SQL                                                          -- Snowflake Scripting
EXECUTE AS OWNER                                                      -- callers need only USAGE on the procedure
COMMENT = 'Agent tool: exact invoice counts and amount totals per currency, overdue or all, as of a date'  -- shown in SHOW PROCEDURES
AS
$$
DECLARE
    report_date  DATE;                                                -- the as-of date actually used
    chosen_scope VARCHAR;                                             -- normalised scope
    bad_scope    EXCEPTION (-20001, 'scope must be overdue or all');  -- clear error for a wrong scope
    bad_date     EXCEPTION (-20002, 'as_of_date must be an ISO date like 2025-04-30');  -- clear error for an unreadable date
    totals       RESULTSET;                                           -- the rows returned to the agent
BEGIN
    chosen_scope := LOWER(COALESCE(:scope, 'overdue'));               -- NULL scope means the default
    IF (chosen_scope NOT IN ('overdue', 'all')) THEN                  -- only two scopes exist
        RAISE bad_scope;                                              -- stop with the clear message
    END IF;
    IF (:as_of_date IS NULL) THEN                                     -- no date given
        SELECT MAX(as_of_date) INTO :report_date                      -- the one reporting as-of date
        FROM coco.silver.reporting_calendar;                          -- 2025-06-30 for this snapshot
    ELSE
        report_date := TRY_TO_DATE(:as_of_date);                      -- parse the caller's date
        IF (report_date IS NULL) THEN                                 -- unreadable date: never fall back silently
            RAISE bad_date;                                           -- stop with the clear message
        END IF;
    END IF;
    totals := (
        SELECT currency_code,                                         -- USD, EUR or GBP
               COUNT(*)                         AS invoice_count,     -- invoices in scope
               SUM(invoice_amount)::NUMBER(18,2) AS total_amount,     -- exact total in that currency
               :report_date                     AS as_of_date,        -- echo the date used
               :chosen_scope                    AS scope              -- echo the scope used
        FROM coco.silver.dt_silver_ap_invoices                        -- same Silver table as the semantic view
        WHERE invoice_date <= :report_date                            -- issued by the as-of date
          AND (:chosen_scope = 'all' OR due_date < :report_date)      -- overdue: due before the as-of date
          AND (:vendor_name IS NULL OR UPPER(vendor_name) = UPPER(:vendor_name))  -- optional vendor filter
        GROUP BY currency_code                                        -- never sum across currencies
        ORDER BY currency_code                                        -- stable order: EUR, GBP, USD
    );
    RETURN TABLE(totals);                                             -- hand the rows to the caller
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- 05_guardrails / 90 — seeded boundary cases for BR-004 (test only)
-- ══════════════════════════════════════════════════════════════════
-- Rates (verified 2026-10-03): 2025-03-03 eur_usd 1.0465, gbp_usd 1.268;
-- 2025-02-28 (Fri) gbp_usd 1.2603. XTS = ISO 4217 test code (no rates).
-- Expected flagged: cases 1, 3, 6 → 3 (> tolerance 2 → expectation violated).

-- ── Context ──────────────────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- same owner as the real guardrails
USE DATABASE coco;                                                    -- project database
CREATE SCHEMA IF NOT EXISTS guardrails_test                           -- isolated from the real pipeline
    COMMENT = 'BR-004 test fixtures; dropped after verification (rebuild with 90_test_fixture.sql)';  -- purpose

-- ── Empty copy of Silver's columns ───────────────────────────────
CREATE OR REPLACE TABLE guardrails_test.silver_invoices_test_synthetic AS  -- regular table, same columns as Silver
    SELECT * FROM coco.silver.dt_silver_ap_invoices WHERE FALSE;      -- structure only, no rows

-- ── Seed the 6 boundary cases ────────────────────────────────────
INSERT INTO guardrails_test.silver_invoices_test_synthetic            -- only the columns the guardrail reads
    (invoice_id, invoice_number, vendor_name, invoice_date, invoice_amount, currency_code, source_system)
VALUES
    ('TEST-1', 'TEST-INV-1', 'Test Vendor A', '2025-03-03', 600000, 'USD', 'TEST'),  -- 1: 600,000 USD → flagged
    ('TEST-2', 'TEST-INV-2', 'Test Vendor B', '2025-03-03', 500000, 'USD', 'TEST'),  -- 2: exactly 500,000 → not (strict >)
    ('TEST-3', 'TEST-INV-3', 'Test Vendor C', '2025-03-03', 480000, 'EUR', 'TEST'),  -- 3: ×1.0465 = 502,320 → flagged
    ('TEST-4', 'TEST-INV-4', 'Test Vendor D', '2025-03-03', 477000, 'EUR', 'TEST'),  -- 4: ×1.0465 = 499,180.50 → not
    ('TEST-5', 'TEST-INV-5', 'Test Vendor E', '2025-03-02', 396000, 'GBP', 'TEST'),  -- 5: Sun → Fri 1.2603 = 499,078.80 → not
    ('TEST-6', 'TEST-INV-6', 'Test Vendor F', '2025-03-03',   1000, 'XTS', 'TEST');  -- 6: no rate → flagged (fail-safe)

-- ── Edge cases (plan Review Focus 1–5), one invoice_id per case ──
-- A manual DMF call only accepts a plain "SELECT cols FROM object" argument:
-- inline VALUES or a WHERE filter fails with a misleading "Invalid argument
-- types". So the cases live in a table, with one unfiltered view per case.
CREATE OR REPLACE TABLE guardrails_test.edge_cases_synthetic AS       -- same columns as Silver
    SELECT * FROM coco.silver.dt_silver_ap_invoices WHERE FALSE;      -- structure only, no rows
INSERT INTO guardrails_test.edge_cases_synthetic
    (invoice_id, invoice_number, vendor_name, invoice_date, invoice_amount, currency_code, source_system)
VALUES
    ('RF-1',  'RF-INV-1', 'Edge Vendor', '2026-10-01',    1000, 'EUR', 'TEST'),     -- 1: after the last free rate → uses older rate, not flagged
    ('RF-2',  'RF-INV-2', 'Edge Vendor', '2025-03-03',    1000, 'eur', 'TEST'),     -- 2: lowercase code → no rate → flagged
    ('RF-3',  'RF-INV-3', 'Edge Vendor', '2025-03-03',    NULL, 'USD', 'TEST'),     -- 3: missing amount → flagged
    ('RF-4',  'RF-INV-4', 'Edge Vendor', '2025-03-03', -600000, 'USD', 'TEST'),     -- 4: credit note → not flagged
    ('DUP-1', 'DUP-INV-1', 'Edge Vendor', '2025-03-03', 600000, 'USD', 'SAP'),      -- 5a: same id …
    ('DUP-1', 'DUP-INV-1', 'Edge Vendor', '2025-03-03', 600000, 'USD', 'ORACLE');   -- 5b: … other system → counted twice

-- ── One unfiltered view per edge case (the shape a DMF call accepts) ──
CREATE OR REPLACE VIEW guardrails_test.edge_rf_1  AS SELECT * FROM guardrails_test.edge_cases_synthetic WHERE invoice_id = 'RF-1';   -- stale rate
CREATE OR REPLACE VIEW guardrails_test.edge_rf_2  AS SELECT * FROM guardrails_test.edge_cases_synthetic WHERE invoice_id = 'RF-2';   -- lowercase code
CREATE OR REPLACE VIEW guardrails_test.edge_rf_3  AS SELECT * FROM guardrails_test.edge_cases_synthetic WHERE invoice_id = 'RF-3';   -- null amount
CREATE OR REPLACE VIEW guardrails_test.edge_rf_4  AS SELECT * FROM guardrails_test.edge_cases_synthetic WHERE invoice_id = 'RF-4';   -- credit note
CREATE OR REPLACE VIEW guardrails_test.edge_dup_1 AS SELECT * FROM guardrails_test.edge_cases_synthetic WHERE invoice_id = 'DUP-1';  -- same id, two systems

-- ── Fixture self-checks ──────────────────────────────────────────
SELECT 'fixture_row_count' AS check_name, 6 AS expected,                                       -- six seeded rows
       (SELECT COUNT(*) FROM guardrails_test.silver_invoices_test_synthetic) AS actual,        -- rows present
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;                                      -- PASS when seeded once
SELECT 'edge_case_row_count' AS check_name, 6 AS expected,                                     -- 4 single rows + 2 DUP-1 rows
       (SELECT COUNT(*) FROM guardrails_test.edge_cases_synthetic) AS actual,                  -- rows present
       IFF(actual = expected, 'PASS', 'FAIL') AS outcome;

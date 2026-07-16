USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA bronze;                                        -- bronze landing schema

-- ── Bronze table: Baan AP invoices ───────────────────────────────
-- Source: Baan IV, onboarded per SRC-2025-003 (see docs/business_requirements/
-- sample_business_requirements_source_onboarding.csv). Runs on-prem in
-- Rotterdam; nightly CSV batch to S3, arrives ~02:00 UTC. Column names/shapes
-- and the 10 sample rows below are taken verbatim from the reference
-- workshop's synthetic dataset.
CREATE OR REPLACE TABLE baan_ap_invoices (
    ban_invoice_id      VARCHAR(20),                       -- Baan-native invoice key, format BAN-NNN
    ban_invoice_ref     VARCHAR(30),                        -- business-facing invoice number, format BN-YYYY-NNNN — used for dedup (BR-003)
    ban_vendor_code     VARCHAR(15),                         -- Baan vendor code, format BV-NNN
    ban_vendor_desc     VARCHAR(100),                         -- vendor display name; may contain non-ASCII (ü, é, etc.)
    ban_inv_date        DATE,                                 -- date invoice was issued (always YYYY-MM-DD)
    ban_pay_date        DATE,                                  -- payment due date
    ban_amount          NUMBER(18,2),                           -- total invoice amount; credit memos arrive as separate negative rows
    ban_curr            VARCHAR(3),                             -- ISO currency code; only EUR/GBP observed
    ban_pay_terms       VARCHAR(20),                             -- Baan-format terms, e.g. N30/N60 (BR-005: left as-is at Silver)
    ban_po_ref          VARCHAR(20),                              -- linked purchase order; ~15% of Baan invoices have none (service invoices)
    ban_line_desc       VARCHAR(200),                              -- free-text line description, sometimes in Dutch
    ban_gl_code         VARCHAR(20),                               -- Baan GL account code, format GL-NNN
    ban_cost_ctr        VARCHAR(20),                               -- cost center; format changed Jan 2025 (old BC-XX, new BC-XXX) — both may appear
    ban_status          VARCHAR(20),                               -- Baan status: POSTED/APPROVED/PENDING
    ban_created         TIMESTAMP_NTZ,                             -- record creation timestamp, UTC
    ban_company         VARCHAR(10)                                -- Baan-specific, dropped at Silver per BR-008
)
COMMENT = 'Bronze Baan AP invoices — synthetic demo data, 10 rows, EUR/GBP only';

-- ── Sample data load (synthetic demo data, 10 rows) ──────────────
-- NOTE: this sample batch has no duplicates, but the real Baan nightly
-- extract is known to occasionally re-send an invoice under a new
-- ban_invoice_id with the same ban_invoice_ref (BR-003) — the Silver
-- Dynamic Table dedups defensively on ban_invoice_ref regardless.
INSERT INTO baan_ap_invoices VALUES
('BAN-001', 'BN-2025-1001', 'BV-301', 'Nordic Metals AB', '2025-02-01', '2025-03-03', 27500.00, 'EUR', 'N30', 'BP-8001', 'Aluminum extrusions Feb shipment', 'GL-510', 'BC-MFG', 'POSTED', '2025-02-01 06:00:00', 'BN-100'),
('BAN-002', 'BN-2025-1002', 'BV-302', 'Rotterdam Port Services', '2025-02-15', '2025-03-17', 14200.00, 'EUR', 'N30', 'BP-8002', 'Port handling and customs Feb', 'GL-610', 'BC-LOG', 'POSTED', '2025-02-15 08:30:00', 'BN-100'),
('BAN-003', 'BN-2025-1003', 'BV-303', 'Manchester Engineering Ltd', '2025-03-01', '2025-04-30', 38900.00, 'GBP', 'N60', 'BP-8003', 'Custom fabrication project Alpha', 'GL-520', 'BC-ENG', 'POSTED', '2025-03-01 09:00:00', 'BN-200'),
('BAN-004', 'BN-2025-1004', 'BV-301', 'Nordic Metals AB', '2025-03-10', '2025-04-09', 31200.00, 'EUR', 'N30', 'BP-8004', 'Steel plate order March', 'GL-510', 'BC-MFG', 'APPROVED', '2025-03-10 07:15:00', 'BN-100'),
('BAN-005', 'BN-2025-1005', 'BV-304', 'Belgian Chemicals NV', '2025-03-20', '2025-05-19', 9600.00, 'EUR', 'N60', 'BP-8005', 'Industrial lubricants Q1', 'GL-540', 'BC-OPS', 'POSTED', '2025-03-20 10:00:00', 'BN-100'),
('BAN-006', 'BN-2025-1006', 'BV-305', 'Zurich Consulting AG', '2025-04-01', '2025-05-01', 55000.00, 'EUR', 'N30', 'BP-8006', 'ERP optimization consulting Apr', 'GL-620', 'BC-IT', 'POSTED', '2025-04-01 08:00:00', 'BN-100'),
('BAN-007', 'BN-2025-1007', 'BV-302', 'Rotterdam Port Services', '2025-04-15', '2025-05-15', 16800.00, 'EUR', 'N30', 'BP-8007', 'Port handling and customs Apr', 'GL-610', 'BC-LOG', 'PENDING', '2025-04-15 08:30:00', 'BN-100'),
('BAN-008', 'BN-2025-1008', 'BV-303', 'Manchester Engineering Ltd', '2025-05-01', '2025-06-30', 22100.00, 'GBP', 'N60', 'BP-8008', 'Fabrication project Alpha phase 2', 'GL-520', 'BC-ENG', 'POSTED', '2025-05-01 09:00:00', 'BN-200'),
('BAN-009', 'BN-2025-1009', 'BV-306', 'Amsterdam IT Services BV', '2025-05-10', '2025-06-09', 12500.00, 'EUR', 'N30', 'BP-8009', 'Network infrastructure upgrade', 'GL-620', 'BC-IT', 'POSTED', '2025-05-10 11:00:00', 'BN-100'),
('BAN-010', 'BN-2025-1010', 'BV-301', 'Nordic Metals AB', '2025-06-01', '2025-07-01', 29800.00, 'EUR', 'N30', 'BP-8010', 'Aluminum extrusions Jun shipment', 'GL-510', 'BC-MFG', 'APPROVED', '2025-06-01 06:00:00', 'BN-100');

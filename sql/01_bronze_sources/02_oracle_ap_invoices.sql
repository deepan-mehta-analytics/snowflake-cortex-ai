USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA bronze;                                        -- bronze landing schema

-- ── Bronze table: Oracle AP invoices ─────────────────────────────
-- Source: Oracle Financials AP module export. Column names/shapes and the
-- 15 sample rows below are taken verbatim from the reference workshop's
-- synthetic dataset (see docs/business_requirements/ for provenance).
CREATE OR REPLACE TABLE oracle_ap_invoices (
    inv_id              VARCHAR(20),                       -- Oracle-native invoice key, format ORA-NNN
    inv_num              VARCHAR(30),                       -- business-facing invoice number, format ORA-INV-NNNNN
    supplier_id          VARCHAR(15),                       -- Oracle supplier ID, format S-NNNN
    supplier_name        VARCHAR(100),                       -- supplier display name (Oracle calls vendors "suppliers")
    inv_date             DATE,                               -- date invoice was issued
    payment_due_date     DATE,                                -- payment due date per Oracle terms
    total_amount         NUMBER(18,2),                        -- total invoice amount, source currency
    currency             VARCHAR(3),                          -- ISO currency code (USD, EUR, GBP)
    terms_code           VARCHAR(20),                          -- Oracle-format terms, e.g. N30/N60
    purchase_order        VARCHAR(20),                          -- linked purchase order, Oracle format OP-NNNNNNN
    description           VARCHAR(200),                          -- free-text line description
    account_code           VARCHAR(20),                          -- Oracle GL account code
    dept_code               VARCHAR(20),                          -- Oracle department code
    status                   VARCHAR(20),                          -- Oracle status: VALIDATED/APPROVED/PENDING
    creation_date            TIMESTAMP_NTZ,                        -- Oracle record creation timestamp
    oracle_org_id            VARCHAR(10),                          -- Oracle-specific, dropped at Silver per BR-008
    oracle_source             VARCHAR(20)                           -- Oracle-specific, dropped at Silver per BR-008
)
COMMENT = 'Bronze Oracle AP invoices — synthetic demo data, 15 rows across 3 currencies';

-- ── Sample data load (synthetic demo data, 15 rows) ──────────────
INSERT INTO oracle_ap_invoices VALUES
('ORA-001', 'ORA-INV-50001', 'S-2001', 'Midwest Tool & Die Co', '2025-01-10', '2025-02-09', 34200.00, 'USD', 'N30', 'OP-7100001', 'Custom tooling for Line 3', 'A5100-40', 'D-ENG', 'VALIDATED', '2025-01-10 07:00:00', 'ORG-101', 'AP_IMPORT'),
('ORA-002', 'ORA-INV-50002', 'S-2002', 'Deutsche Industrie Werke', '2025-01-20', '2025-03-21', 19800.00, 'EUR', 'N60', 'OP-7100002', 'CNC machine calibration service', 'A6200-20', 'D-MFG', 'VALIDATED', '2025-01-20 08:30:00', 'ORG-102', 'AP_IMPORT'),
('ORA-003', 'ORA-INV-50003', 'S-2003', 'Summit Energy Corp', '2025-02-05', '2025-03-07', 67500.00, 'USD', 'N30', 'OP-7100003', 'Natural gas supply Feb', 'A6400-10', 'D-FAC', 'VALIDATED', '2025-02-05 06:00:00', 'ORG-101', 'AP_IMPORT'),
('ORA-004', 'ORA-INV-50004', 'S-2001', 'Midwest Tool & Die Co', '2025-02-18', '2025-03-20', 15600.00, 'USD', 'N30', 'OP-7100004', 'Replacement dies for stamping press', 'A5100-40', 'D-ENG', 'APPROVED', '2025-02-18 11:00:00', 'ORG-101', 'MANUAL'),
('ORA-005', 'ORA-INV-50005', 'S-2004', 'Yorkshire Chemical Ltd', '2025-02-25', '2025-04-26', 8900.00, 'GBP', 'N60', 'OP-7100005', 'Industrial solvents quarterly', 'A5400-10', 'D-OPS', 'VALIDATED', '2025-02-25 09:15:00', 'ORG-103', 'AP_IMPORT'),
('ORA-006', 'ORA-INV-50006', 'S-2005', 'Apex Staffing Solutions', '2025-03-01', '2025-03-31', 52000.00, 'USD', 'N30', 'OP-7100006', 'Contract labor March - assembly', 'A6500-10', 'D-HR', 'VALIDATED', '2025-03-01 07:00:00', 'ORG-101', 'AP_IMPORT'),
('ORA-007', 'ORA-INV-50007', 'S-2002', 'Deutsche Industrie Werke', '2025-03-12', '2025-05-11', 42300.00, 'EUR', 'N60', 'OP-7100007', 'Spare parts for robotic welders', 'A5100-50', 'D-MFG', 'PENDING', '2025-03-12 10:45:00', 'ORG-102', 'AP_IMPORT'),
('ORA-008', 'ORA-INV-50008', 'S-2006', 'National Insurance Brokers', '2025-03-15', '2025-04-14', 125000.00, 'USD', 'N30', 'OP-7100008', 'Property insurance renewal Q2', 'A6600-10', 'D-FIN', 'VALIDATED', '2025-03-15 14:30:00', 'ORG-101', 'MANUAL'),
('ORA-009', 'ORA-INV-50009', 'S-2003', 'Summit Energy Corp', '2025-04-01', '2025-05-01', 71200.00, 'USD', 'N30', 'OP-7100009', 'Natural gas supply Apr', 'A6400-10', 'D-FAC', 'VALIDATED', '2025-04-01 06:00:00', 'ORG-101', 'AP_IMPORT'),
('ORA-010', 'ORA-INV-50010', 'S-2007', 'Consolidated Packaging', '2025-04-08', '2025-05-08', 11800.00, 'USD', 'N30', 'OP-7100010', 'Shipping materials April', 'A5500-10', 'D-LOG', 'VALIDATED', '2025-04-08 08:00:00', 'ORG-101', 'AP_IMPORT'),
('ORA-011', 'ORA-INV-50011', 'S-2004', 'Yorkshire Chemical Ltd', '2025-04-22', '2025-06-21', 9500.00, 'GBP', 'N60', 'OP-7100011', 'Adhesives and coatings batch', 'A5400-10', 'D-OPS', 'APPROVED', '2025-04-22 09:00:00', 'ORG-103', 'AP_IMPORT'),
('ORA-012', 'ORA-INV-50012', 'S-2005', 'Apex Staffing Solutions', '2025-05-01', '2025-05-31', 48000.00, 'USD', 'N30', 'OP-7100012', 'Contract labor May - assembly', 'A6500-10', 'D-HR', 'VALIDATED', '2025-05-01 07:00:00', 'ORG-101', 'AP_IMPORT'),
('ORA-013', 'ORA-INV-50013', 'S-2008', 'Precision Instruments AG', '2025-05-10', '2025-07-09', 16700.00, 'EUR', 'N60', 'OP-7100013', 'Quality testing equipment', 'A5200-20', 'D-QA', 'PENDING', '2025-05-10 11:30:00', 'ORG-102', 'AP_IMPORT'),
('ORA-014', 'ORA-INV-50014', 'S-2006', 'National Insurance Brokers', '2025-05-20', '2025-06-19', 8500.00, 'USD', 'N30', 'OP-7100014', 'Workers comp adjustment', 'A6600-10', 'D-FIN', 'VALIDATED', '2025-05-20 15:00:00', 'ORG-101', 'MANUAL'),
('ORA-015', 'ORA-INV-50015', 'S-2003', 'Summit Energy Corp', '2025-06-01', '2025-07-01', 58900.00, 'USD', 'N30', 'OP-7100015', 'Natural gas supply Jun', 'A6400-10', 'D-FAC', 'VALIDATED', '2025-06-01 06:00:00', 'ORG-101', 'AP_IMPORT');

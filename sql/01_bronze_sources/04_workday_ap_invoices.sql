USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA bronze;                                        -- bronze landing schema

-- ── Bronze table: Workday AP invoices ────────────────────────────
-- Source: Workday Financial Management, onboarded per SRC-2025-004 (see
-- docs/business_requirements/sample_business_requirements_source_onboarding.csv).
-- Tenant WD-T2 is the London entity (GBP/EUR); WD-T1 is US (mostly USD).
-- Column names/shapes and the 10 sample rows below are taken verbatim from
-- the reference workshop's synthetic dataset.
CREATE OR REPLACE TABLE workday_ap_invoices (
    wd_invoice_id       VARCHAR(20),                       -- Workday-native invoice key, format WD-NNN
    wd_invoice_num      VARCHAR(30),                        -- business-facing invoice number, format WD-AP-NNNNN
    wd_supplier_id      VARCHAR(15),                         -- Workday supplier ID, format WS-NNN (Workday calls vendors "suppliers")
    wd_supplier_name    VARCHAR(100),                         -- supplier display name
    wd_invoice_date     DATE,                                  -- date invoice was issued
    wd_due_date         DATE,                                   -- payment due date
    wd_amount           NUMBER(18,2),                            -- total invoice amount, always positive
    wd_currency         VARCHAR(3),                               -- ISO currency code; USD ~70% of volume, plus GBP/EUR
    wd_pay_terms        VARCHAR(20),                                -- Workday-format terms, e.g. "Net 30"/"Net 60" (with space)
    wd_po_number        VARCHAR(20),                                 -- linked purchase order, format WPO-NNNN (~90% coverage)
    wd_memo             VARCHAR(200),                                 -- free-text memo, same purpose as line_description elsewhere
    wd_ledger_account   VARCHAR(20),                                  -- Workday GL account code, format LA-NNNN
    wd_cost_center      VARCHAR(20),                                   -- Workday cost center, format WCC-XXXX
    wd_approval_status  VARCHAR(20),                                    -- Workday status: "Approved"/"In Review"
    wd_created_date     TIMESTAMP_NTZ,                                  -- record creation timestamp, UTC (cloud-native, no TZ conversion needed)
    wd_tenant_id        VARCHAR(10)                                     -- Workday-specific, dropped at Silver per BR-008 (WD-T1=US, WD-T2=London)
)
COMMENT = 'Bronze Workday AP invoices — synthetic demo data, 10 rows across 2 tenants';

-- ── Sample data load (synthetic demo data, 10 rows) ──────────────
INSERT INTO workday_ap_invoices VALUES
('WD-001', 'WD-AP-90001', 'WS-401', 'CloudScale Analytics', '2025-01-20', '2025-02-19', 22000.00, 'USD', 'Net 30', 'WPO-6001', 'Data platform subscription Jan', 'LA-6200', 'WCC-TECH', 'Approved', '2025-01-20 10:00:00', 'WD-T1'),
('WD-002', 'WD-AP-90002', 'WS-402', 'Premier Office Solutions', '2025-02-01', '2025-03-03', 5600.00, 'USD', 'Net 30', 'WPO-6002', 'Office supplies and furniture Q1', 'LA-6800', 'WCC-ADMIN', 'Approved', '2025-02-01 09:00:00', 'WD-T1'),
('WD-003', 'WD-AP-90003', 'WS-403', 'Talent Bridge HR', '2025-02-10', '2025-03-12', 35000.00, 'USD', 'Net 30', 'WPO-6003', 'Executive recruiting services Feb', 'LA-6500', 'WCC-HR', 'Approved', '2025-02-10 14:00:00', 'WD-T1'),
('WD-004', 'WD-AP-90004', 'WS-404', 'London Legal Partners LLP', '2025-02-20', '2025-04-21', 18500.00, 'GBP', 'Net 60', 'WPO-6004', 'Legal advisory services Q1', 'LA-6700', 'WCC-LEGAL', 'In Review', '2025-02-20 11:30:00', 'WD-T2'),
('WD-005', 'WD-AP-90005', 'WS-401', 'CloudScale Analytics', '2025-03-01', '2025-03-31', 22000.00, 'USD', 'Net 30', 'WPO-6005', 'Data platform subscription Mar', 'LA-6200', 'WCC-TECH', 'Approved', '2025-03-01 10:00:00', 'WD-T1'),
('WD-006', 'WD-AP-90006', 'WS-405', 'Frankfurt Marketing Agentur', '2025-03-15', '2025-05-14', 42000.00, 'EUR', 'Net 60', 'WPO-6006', 'Brand campaign spring launch', 'LA-6900', 'WCC-MKT', 'Approved', '2025-03-15 08:00:00', 'WD-T2'),
('WD-007', 'WD-AP-90007', 'WS-402', 'Premier Office Solutions', '2025-04-01', '2025-05-01', 3200.00, 'USD', 'Net 30', 'WPO-6007', 'Office supplies April', 'LA-6800', 'WCC-ADMIN', 'Approved', '2025-04-01 09:00:00', 'WD-T1'),
('WD-008', 'WD-AP-90008', 'WS-406', 'CyberShield Security Inc', '2025-04-10', '2025-05-10', 67000.00, 'USD', 'Net 30', 'WPO-6008', 'Annual security audit + pen test', 'LA-6200', 'WCC-TECH', 'Approved', '2025-04-10 13:00:00', 'WD-T1'),
('WD-009', 'WD-AP-90009', 'WS-403', 'Talent Bridge HR', '2025-05-01', '2025-05-31', 28000.00, 'USD', 'Net 30', 'WPO-6009', 'Recruiting services May', 'LA-6500', 'WCC-HR', 'In Review', '2025-05-01 14:00:00', 'WD-T1'),
('WD-010', 'WD-AP-90010', 'WS-401', 'CloudScale Analytics', '2025-05-15', '2025-06-14', 22000.00, 'USD', 'Net 30', 'WPO-6010', 'Data platform subscription May', 'LA-6200', 'WCC-TECH', 'Approved', '2025-05-15 10:00:00', 'WD-T1');

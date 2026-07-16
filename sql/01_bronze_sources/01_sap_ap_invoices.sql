USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA bronze;                                        -- bronze landing schema

-- ── Bronze table: SAP AP invoices ────────────────────────────────
-- Source: SAP AP module export. Column names/shapes and the 15 sample rows
-- below are taken verbatim from the reference workshop's synthetic dataset
-- (see docs/business_requirements/ for provenance) so the pipeline has
-- real, runnable data rather than invented placeholders.
CREATE OR REPLACE TABLE sap_ap_invoices (
    invoice_id          VARCHAR(20),                       -- SAP-native invoice key, format SAP-NNN
    invoice_number      VARCHAR(30),                        -- business-facing invoice number, format INV-YYYY-NNNN
    vendor_id           VARCHAR(15),                        -- SAP vendor master ID, format V-NNNN
    vendor_name         VARCHAR(100),                       -- vendor display name
    invoice_date        DATE,                               -- date invoice was issued
    due_date            DATE,                               -- payment due date per SAP terms
    invoice_amount      NUMBER(18,2),                       -- total invoice amount, source currency
    currency_code       VARCHAR(3),                          -- ISO currency code (USD, EUR, GBP)
    payment_terms       VARCHAR(20),                         -- SAP-format terms, e.g. NET30/NET60
    po_number           VARCHAR(20),                         -- linked purchase order
    line_description    VARCHAR(200),                        -- free-text line description
    gl_account          VARCHAR(20),                          -- SAP general ledger account code
    cost_center         VARCHAR(20),                          -- SAP cost center code
    approval_status     VARCHAR(20),                          -- SAP status: APPROVED or PENDING
    created_at          TIMESTAMP_NTZ,                        -- SAP record creation timestamp
    sap_company_code    VARCHAR(10),                          -- SAP-specific, dropped at Silver per BR-008
    sap_document_type   VARCHAR(10)                           -- SAP-specific, dropped at Silver per BR-008
)
COMMENT = 'Bronze SAP AP invoices — synthetic demo data, 15 rows across 3 currencies';

-- ── Sample data load (synthetic demo data, 15 rows) ──────────────
INSERT INTO sap_ap_invoices VALUES
('SAP-001', 'INV-2025-0001', 'V-1001', 'Acme Industrial Supply', '2025-01-15', '2025-02-14', 12500.00, 'USD', 'NET30', 'PO-4500001', 'Hydraulic pumps Q1 order', '5100-10', 'CC-ENG-01', 'APPROVED', '2025-01-15 08:30:00', '1000', 'KR'),
('SAP-002', 'INV-2025-0002', 'V-1002', 'Global Parts GmbH', '2025-01-22', '2025-03-22', 8750.50, 'EUR', 'NET60', 'PO-4500002', 'Precision bearings batch', '5100-20', 'CC-MFG-02', 'APPROVED', '2025-01-22 09:15:00', '2000', 'KR'),
('SAP-003', 'INV-2025-0003', 'V-1003', 'TechServ Solutions', '2025-02-01', '2025-03-03', 45000.00, 'USD', 'NET30', 'PO-4500003', 'IT consulting services Feb', '6200-10', 'CC-IT-01', 'PENDING', '2025-02-01 10:00:00', '1000', 'KR'),
('SAP-004', 'INV-2025-0004', 'V-1001', 'Acme Industrial Supply', '2025-02-10', '2025-03-12', 7200.00, 'USD', 'NET30', 'PO-4500004', 'Replacement valve assemblies', '5100-10', 'CC-ENG-01', 'APPROVED', '2025-02-10 14:20:00', '1000', 'KR'),
('SAP-005', 'INV-2025-0005', 'V-1004', 'UK Safety Supplies Ltd', '2025-02-15', '2025-04-16', 3200.00, 'GBP', 'NET60', 'PO-4500005', 'PPE quarterly restock', '5300-10', 'CC-OPS-03', 'APPROVED', '2025-02-15 11:45:00', '3000', 'KR'),
('SAP-006', 'INV-2025-0006', 'V-1005', 'CleanTech Environmental', '2025-03-01', '2025-03-31', 18900.00, 'USD', 'NET30', 'PO-4500006', 'Waste disposal services Q1', '6300-20', 'CC-FAC-01', 'APPROVED', '2025-03-01 08:00:00', '1000', 'KR'),
('SAP-007', 'INV-2025-0007', 'V-1002', 'Global Parts GmbH', '2025-03-10', '2025-05-09', 15400.75, 'EUR', 'NET60', 'PO-4500007', 'Motor assemblies spring batch', '5100-20', 'CC-MFG-02', 'PENDING', '2025-03-10 09:30:00', '2000', 'KR'),
('SAP-008', 'INV-2025-0008', 'V-1006', 'Express Logistics Inc', '2025-03-15', '2025-04-14', 6800.00, 'USD', 'NET30', 'PO-4500008', 'Freight charges March', '6100-10', 'CC-LOG-01', 'APPROVED', '2025-03-15 16:10:00', '1000', 'KR'),
('SAP-009', 'INV-2025-0009', 'V-1003', 'TechServ Solutions', '2025-04-01', '2025-05-01', 45000.00, 'USD', 'NET30', 'PO-4500009', 'IT consulting services Apr', '6200-10', 'CC-IT-01', 'APPROVED', '2025-04-01 10:00:00', '1000', 'KR'),
('SAP-010', 'INV-2025-0010', 'V-1007', 'Pacific Raw Materials', '2025-04-05', '2025-05-05', 92000.00, 'USD', 'NET30', 'PO-4500010', 'Steel alloy shipment Q2', '5000-10', 'CC-MFG-01', 'APPROVED', '2025-04-05 07:45:00', '1000', 'KR'),
('SAP-011', 'INV-2025-0011', 'V-1004', 'UK Safety Supplies Ltd', '2025-04-20', '2025-06-19', 4100.00, 'GBP', 'NET60', 'PO-4500011', 'Fire safety equipment', '5300-10', 'CC-OPS-03', 'PENDING', '2025-04-20 13:00:00', '3000', 'KR'),
('SAP-012', 'INV-2025-0012', 'V-1005', 'CleanTech Environmental', '2025-05-01', '2025-05-31', 18900.00, 'USD', 'NET30', 'PO-4500012', 'Waste disposal services Q2-M1', '6300-20', 'CC-FAC-01', 'APPROVED', '2025-05-01 08:00:00', '1000', 'KR'),
('SAP-013', 'INV-2025-0013', 'V-1008', 'Schneider Electric AG', '2025-05-10', '2025-07-09', 28500.00, 'EUR', 'NET60', 'PO-4500013', 'PLC controllers upgrade', '5200-10', 'CC-ENG-02', 'APPROVED', '2025-05-10 10:30:00', '2000', 'KR'),
('SAP-014', 'INV-2025-0014', 'V-1006', 'Express Logistics Inc', '2025-05-15', '2025-06-14', 7350.00, 'USD', 'NET30', 'PO-4500014', 'Freight charges May', '6100-10', 'CC-LOG-01', 'APPROVED', '2025-05-15 16:00:00', '1000', 'KR'),
('SAP-015', 'INV-2025-0015', 'V-1001', 'Acme Industrial Supply', '2025-06-01', '2025-07-01', 21000.00, 'USD', 'NET30', 'PO-4500015', 'Hydraulic pumps Q2 order', '5100-10', 'CC-ENG-01', 'PENDING', '2025-06-01 08:30:00', '1000', 'KR');

USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA silver;                                        -- Silver Dynamic Tables live in their own schema

-- ── Dynamic Table: Silver AP invoices, conformed across 4 sources ──
-- Unions SAP, Oracle, Baan, and Workday bronze invoices into one common
-- shape. Business rules below are BR-001..BR-010 from
-- docs/business_requirements/sample_business_requirements_business_rules.csv
-- (the reference workshop's finance-approved decisions for this pipeline).
CREATE OR REPLACE DYNAMIC TABLE dt_silver_ap_invoices
    TARGET_LAG = DOWNSTREAM                               -- BR-009: sources refresh at different cadences (SAP CDC, Oracle hourly,
                                                           -- Baan nightly ~02:00 UTC, Workday hourly) — let consumers set the pace
    WAREHOUSE = wh_coco_pipeline                           -- compute pool used to refresh this table
    REFRESH_MODE = AUTO                                    -- let Snowflake choose incremental vs full refresh
    AS
    SELECT
        invoice_id,                                         -- SAP-native invoice key
        invoice_number,                                      -- business-facing invoice number
        vendor_id,                                            -- SAP vendor master ID
        vendor_name,                                           -- vendor display name
        invoice_date,                                           -- invoice issue date
        due_date,                                                -- payment due date
        invoice_amount,                                           -- BR-002: original transaction currency, no FX conversion here
        currency_code,                                             -- ISO currency code
        payment_terms,                                              -- BR-005: left in native SAP format (NET30/NET60); normalize at Gold
        po_number,                                                   -- linked purchase order
        line_description,                                            -- free-text line description
        gl_account,                                                   -- BR-006: original GL code, no cross-source mapping at Silver
        cost_center,                                                   -- original cost center code
        approval_status,                                               -- BR-001: SAP already uses APPROVED/PENDING, no mapping needed
        created_at,                                                     -- record creation timestamp
        'SAP' AS source_system                                          -- BR-007: hard-coded source tag
    FROM bronze.sap_ap_invoices                                          -- BR-008: sap_company_code, sap_document_type dropped here

    UNION ALL

    SELECT
        inv_id,                                              -- Oracle-native invoice key
        inv_num,                                              -- business-facing invoice number
        supplier_id,                                           -- Oracle supplier ID (Oracle calls vendors "suppliers")
        supplier_name,                                          -- supplier display name
        inv_date,                                                -- invoice issue date
        payment_due_date,                                         -- payment due date
        total_amount,                                              -- BR-002: original transaction currency, no FX conversion here
        currency,                                                   -- ISO currency code
        terms_code,                                                  -- BR-005: left in native Oracle format (N30/N60); normalize at Gold
        purchase_order,                                               -- linked purchase order
        description,                                                   -- free-text line description
        account_code,                                                   -- BR-006: original GL code, no cross-source mapping at Silver
        dept_code,                                                       -- original department/cost-center code
        CASE status                                                       -- BR-001: normalize Oracle status to the Silver standard
            WHEN 'VALIDATED' THEN 'APPROVED'
            WHEN 'APPROVED'  THEN 'APPROVED'
            ELSE 'PENDING'
        END AS approval_status,
        creation_date,                                                     -- record creation timestamp
        'ORACLE' AS source_system                                          -- BR-007: hard-coded source tag
    FROM bronze.oracle_ap_invoices                                          -- BR-008: oracle_org_id, oracle_source dropped here

    UNION ALL

    SELECT
        ban_invoice_id,                                       -- Baan-native invoice key
        ban_invoice_ref,                                        -- business-facing invoice number, dedup key per BR-003
        ban_vendor_code,                                          -- Baan vendor code
        ban_vendor_desc,                                           -- vendor display name (may contain non-ASCII characters)
        ban_inv_date,                                                -- invoice issue date
        ban_pay_date,                                                 -- payment due date
        ban_amount,                                                    -- BR-002: original transaction currency, no FX conversion here
        ban_curr,                                                       -- ISO currency code
        ban_pay_terms,                                                   -- BR-005: left in native Baan format (N30/N60); normalize at Gold
        ban_po_ref,                                                       -- linked purchase order (~15% of Baan invoices have none)
        ban_line_desc,                                                     -- free-text line description, sometimes in Dutch
        ban_gl_code,                                                        -- BR-006: original GL code, no cross-source mapping at Silver
        ban_cost_ctr,                                                        -- cost center (format changed Jan 2025; both old/new may appear)
        CASE ban_status                                                       -- BR-001: normalize Baan status to the Silver standard
            WHEN 'POSTED'   THEN 'APPROVED'
            WHEN 'APPROVED' THEN 'APPROVED'
            ELSE 'PENDING'
        END AS approval_status,
        ban_created,                                                          -- record creation timestamp, UTC
        'BAAN' AS source_system                                               -- BR-007: hard-coded source tag
    FROM bronze.baan_ap_invoices                                              -- BR-008: ban_company dropped here
    QUALIFY ROW_NUMBER() OVER (                                               -- BR-003: Baan's nightly extract occasionally re-sends
        PARTITION BY ban_invoice_ref ORDER BY ban_created DESC               -- an invoice under a new ban_invoice_id; keep only the
    ) = 1                                                                     -- most recently created row per ban_invoice_ref

    UNION ALL

    SELECT
        wd_invoice_id,                                        -- Workday-native invoice key
        wd_invoice_num,                                         -- business-facing invoice number
        wd_supplier_id,                                          -- Workday supplier ID (Workday calls vendors "suppliers")
        wd_supplier_name,                                          -- supplier display name
        wd_invoice_date,                                             -- invoice issue date
        wd_due_date,                                                  -- payment due date
        wd_amount,                                                     -- BR-002: original transaction currency, no FX conversion here
        wd_currency,                                                    -- ISO currency code
        wd_pay_terms,                                                    -- BR-005: left in native Workday format ("Net 30"/"Net 60"); normalize at Gold
        wd_po_number,                                                     -- linked purchase order (~90% coverage)
        wd_memo,                                                           -- free-text memo, same purpose as line_description elsewhere
        wd_ledger_account,                                                  -- BR-006: original GL code, no cross-source mapping at Silver
        wd_cost_center,                                                      -- cost center
        CASE wd_approval_status                                               -- BR-001: normalize Workday status to the Silver standard
            WHEN 'Approved'  THEN 'APPROVED'
            WHEN 'In Review' THEN 'PENDING'
            ELSE 'PENDING'
        END AS approval_status,
        wd_created_date,                                                       -- record creation timestamp, UTC (cloud-native, no TZ conversion)
        'WORKDAY' AS source_system                                             -- BR-007: hard-coded source tag
    FROM bronze.workday_ap_invoices;                                           -- BR-008: wd_tenant_id dropped here

-- ── Proof query: record counts by source, rerun after every change ──
-- SELECT source_system, COUNT(*) AS invoice_count
-- FROM dt_silver_ap_invoices
-- GROUP BY source_system
-- ORDER BY source_system;

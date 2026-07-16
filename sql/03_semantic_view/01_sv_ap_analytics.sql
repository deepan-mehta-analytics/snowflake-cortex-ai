USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA semantic;                                      -- semantic views live in their own schema

-- ── Semantic view: AP analytics ───────────────────────────────────
-- Grounds Cortex Analyst / the Cortex Agent in business vocabulary rather
-- than raw table/column names. Facts/dimensions/metrics below are chosen
-- to answer the 15 golden questions in eval/golden_dataset.jsonl (ported
-- from the reference workshop's AGENT_EVAL_SET).
-- NOTE: native CREATE SEMANTIC VIEW syntax; adjust table/column names if
-- your account's Cortex Analyst feature set differs.
CREATE OR REPLACE SEMANTIC VIEW sv_ap_analytics

    TABLES (
        invoices AS silver.dt_silver_ap_invoices
            PRIMARY KEY (invoice_id)                        -- one row per invoice across all 4 sources
            WITH SYNONYMS ('invoice', 'AP invoice', 'bill')
            COMMENT = 'Header-level accounts-payable invoices, conformed across SAP, Oracle, Baan, and Workday',
        vendor_summary AS silver.dt_vendor_invoice_summary
            PRIMARY KEY (vendor_name)                       -- one row per vendor
            WITH SYNONYMS ('vendor', 'supplier')
            COMMENT = 'Pre-aggregated vendor-level invoice totals, pending and overdue exposure'
    )

    FACTS (
        invoices.invoice_amount AS invoice_amount
            COMMENT = 'Total amount on the invoice, in its original transaction currency (no FX conversion — BR-002)',
        vendor_summary.vendor_total_spend AS total_spend
            COMMENT = 'Lifetime invoiced amount for the vendor across all sources',
        vendor_summary.vendor_total_overdue_amount AS total_overdue_amount
            COMMENT = 'Amount on the vendor''s invoices past their due date'
    )

    DIMENSIONS (
        invoices.vendor_name AS vendor_name WITH SYNONYMS ('supplier name') COMMENT = 'Vendor the invoice was billed by',
        invoices.source_system AS source_system COMMENT = 'Originating system: SAP, ORACLE, BAAN, or WORKDAY',
        invoices.approval_status AS approval_status COMMENT = 'Normalized status: APPROVED or PENDING (BR-001)',
        invoices.currency_code AS currency_code COMMENT = 'ISO currency code of the original transaction (USD, EUR, GBP)',
        invoices.invoice_date AS invoice_date COMMENT = 'Date the invoice was issued',
        invoices.due_date AS due_date COMMENT = 'Date payment is due — an invoice is overdue when this is in the past'
    )

    METRICS (
        invoices.total_spend AS SUM(invoice_amount) COMMENT = 'Total invoiced amount over the selected invoices',
        invoices.invoice_count AS COUNT(invoice_id) COMMENT = 'Number of invoices in the selected scope',
        invoices.avg_invoice_amount AS AVG(invoice_amount) COMMENT = 'Average invoice amount over the selected invoices',
        vendor_summary.spend_by_vendor AS SUM(vendor_total_spend) COMMENT = 'Total spend grouped by vendor',
        vendor_summary.overdue_by_vendor AS SUM(vendor_total_overdue_amount) COMMENT = 'Total overdue balance grouped by vendor'
    )

    COMMENT = 'Business-friendly semantic layer over the AP invoice pipeline, used to ground the Cortex Agent';

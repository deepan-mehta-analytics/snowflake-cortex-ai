USE DATABASE coco;                                        -- ensure we're in the right database
USE SCHEMA semantic;                                      -- semantic views live in their own schema

-- ── Semantic view: AP invoices ────────────────────────────────────
-- Grounds Cortex Analyst / the Cortex Agent in business vocabulary rather
-- than raw table/column names, so natural-language questions like "which
-- vendors are overdue" translate into correct, governed SQL.
-- NOTE: native CREATE SEMANTIC VIEW syntax; adjust table/column names if
-- your account's Cortex Analyst feature set differs.
CREATE OR REPLACE SEMANTIC VIEW sv_ap_invoices

    TABLES (
        invoices AS conformed.dt_invoices_conformed
            PRIMARY KEY (invoice_id)                        -- one row per invoice across all 3 sources
            WITH SYNONYMS ('invoice', 'bill', 'AP invoice')
            COMMENT = 'Header-level accounts-payable invoices, conformed across ERP, vendor portal, and OCR sources',
        vendor_summary AS conformed.dt_vendor_invoice_summary
            PRIMARY KEY (vendor_name)                       -- one row per vendor
            WITH SYNONYMS ('vendor', 'supplier')
            COMMENT = 'Pre-aggregated vendor-level invoice totals and overdue exposure',
        line_items AS conformed.dt_invoice_line_items
            PRIMARY KEY (invoice_id, line_number)            -- one row per invoice line
            WITH SYNONYMS ('line item', 'invoice line')
            COMMENT = 'Line-item detail available for vendor-portal-submitted invoices'
    )

    RELATIONSHIPS (
        line_items_to_invoices AS
            line_items (invoice_id) REFERENCES invoices (invoice_id) -- link line items back to their parent invoice
    )

    FACTS (
        invoices.invoice_amount AS invoice_amount COMMENT = 'Total amount on the invoice, in source currency',
        vendor_summary.total_outstanding_amount AS total_outstanding_amount
            COMMENT = 'Sum of unpaid invoice amounts for the vendor',
        vendor_summary.total_overdue_amount AS total_overdue_amount
            COMMENT = 'Sum of unpaid invoice amounts past their due date'
    )

    DIMENSIONS (
        invoices.vendor_name AS vendor_name WITH SYNONYMS ('supplier name') COMMENT = 'Vendor the invoice was billed by',
        invoices.source_system AS source_system COMMENT = 'Originating system: ERP, VENDOR_PORTAL, or OCR_EMAIL',
        invoices.payment_status AS payment_status COMMENT = 'Payment status of the invoice',
        invoices.invoice_date AS invoice_date COMMENT = 'Date the invoice was issued',
        invoices.due_date AS due_date COMMENT = 'Date payment is due'
    )

    METRICS (
        invoices.total_invoiced AS SUM(invoice_amount) COMMENT = 'Total invoiced amount over the selected invoices',
        invoices.invoice_count AS COUNT(invoice_id) COMMENT = 'Number of invoices in the selected scope',
        vendor_summary.outstanding_by_vendor AS SUM(total_outstanding_amount)
            COMMENT = 'Total outstanding balance grouped by vendor',
        vendor_summary.overdue_by_vendor AS SUM(total_overdue_amount)
            COMMENT = 'Total overdue balance grouped by vendor'
    )

    COMMENT = 'Business-friendly semantic layer over the AP invoice pipeline, used to ground the Cortex Agent';

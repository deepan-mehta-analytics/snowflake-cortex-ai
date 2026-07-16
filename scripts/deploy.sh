#!/usr/bin/env bash
set -euo pipefail                                          # exit on error, unset var, or failed pipe stage

# ── Config ────────────────────────────────────────────────────
CONNECTION_NAME="coco"                                      # name of the [connections.coco] block in connection.toml
SQL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../sql" && pwd)"  # absolute path to the sql/ directory

# ── Ordered list of SQL files to apply ───────────────────────
FILES=(
    "00_setup/00_database_schema_warehouse.sql"              # warehouse, database, schemas, grants
    "01_raw_sources/01_erp_invoices.sql"                      # raw ERP landing table
    "01_raw_sources/02_vendor_portal_invoices.sql"            # raw vendor portal landing table
    "01_raw_sources/03_ocr_email_invoices.sql"                # raw OCR email landing table
    "02_dynamic_tables/01_dt_invoices_conformed.sql"          # conformed union Dynamic Table
    "02_dynamic_tables/02_dt_invoice_line_items.sql"          # flattened line-item Dynamic Table
    "02_dynamic_tables/03_dt_vendor_invoice_summary.sql"      # vendor rollup Dynamic Table
    "03_semantic_view/01_sv_ap_invoices.sql"                  # semantic view grounding the Cortex Agent
)

# ── Apply each file in order via the Snowflake CLI ──────────
for relative_path in "${FILES[@]}"; do                        # walk the ordered file list
    full_path="${SQL_ROOT}/${relative_path}"                   # resolve to an absolute path
    echo "Applying ${relative_path}..."                        # progress message per file
    snow sql -c "${CONNECTION_NAME}" -f "${full_path}"          # run the file through the Snowflake CLI
done

echo "Deployment complete."                                    # final confirmation once every file has applied

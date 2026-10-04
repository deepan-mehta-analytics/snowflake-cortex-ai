#!/usr/bin/env bash
set -euo pipefail                                          # exit on error, unset var, or failed pipe stage

# ── Config ────────────────────────────────────────────────────
CONNECTION_NAME="coco"                                      # name of the [connections.coco] block in connection.toml
SQL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../sql" && pwd)"  # absolute path to the sql/ directory

# ── Ordered list of SQL files to apply ───────────────────────
FILES=(
    "00_setup/00_database_schema_warehouse.sql"              # warehouse, database, schemas, grants
    "01_bronze_sources/01_sap_ap_invoices.sql"                # bronze SAP landing table + sample data
    "01_bronze_sources/02_oracle_ap_invoices.sql"             # bronze Oracle landing table + sample data
    "01_bronze_sources/03_baan_ap_invoices.sql"                # bronze Baan landing table + sample data
    "01_bronze_sources/04_workday_ap_invoices.sql"             # bronze Workday landing table + sample data
    "02_silver/01_dt_silver_ap_invoices.sql"                    # conformed Silver Dynamic Table (BR-001..BR-009)
    "02_silver/02_dt_vendor_invoice_summary.sql"                # vendor rollup Dynamic Table
    "03_semantic_view/01_sv_ap_analytics.sql"                    # semantic view grounding Cortex Analyst
    "03_semantic_view/02_cs_ap_invoice_search.sql"               # Cortex Search service grounding free-text lookup
    "05_guardrails/01_schema_and_fx_rates.sql"                   # BR-004: guardrails schema + indicative FX rates view (needs 05_guardrails/00 grants)
    "05_guardrails/02_high_value_dmf.sql"                        # BR-004: high-value invoice Data Metric Function
    "05_guardrails/03_attach_to_silver.sql"                      # BR-004: attach DMF + tolerance expectation to Silver
    "05_guardrails/04_review_queue_view.sql"                     # BR-004: review queue of flagged invoices
    "06_ci/01_eval_objects.sql"                                  # v0.4.0: eval schema, golden-question table, config stage
)

# ── Apply each file in order via the Snowflake CLI ──────────
for relative_path in "${FILES[@]}"; do                        # walk the ordered file list
    full_path="${SQL_ROOT}/${relative_path}"                   # resolve to an absolute path
    echo "Applying ${relative_path}..."                        # progress message per file
    snow sql -c "${CONNECTION_NAME}" -f "${full_path}"          # run the file through the Snowflake CLI
done

echo "Deployment complete."                                    # final confirmation once every file has applied

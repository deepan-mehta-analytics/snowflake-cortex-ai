# 🧾 Snowflake COCO — Multi-Source AP Invoice Intelligence Pipeline

## ⚡ Quick Summary

COCO ingests accounts-payable invoices from three disconnected sources — a nightly ERP export, a vendor self-service portal API, and OCR'd PDF attachments pulled from AP inbox emails — and conforms them into a single, always-fresh view of what the business owes. Snowflake Dynamic Tables handle the incremental transformation from raw landing tables through to vendor-level rollups, so there is no orchestration tool or scheduler to babysit.

On top of that pipeline sits a Snowflake Cortex Agent grounded in a native Semantic View: it can answer quantitative questions ("which vendors are overdue, and by how much") via text-to-SQL against governed business metrics, and free-text questions ("does any invoice mention a late fee") via Cortex Search over the OCR'd document text. An evaluation harness runs a hand-written golden Q&A set against the live agent on every change, so answer quality is measured rather than assumed.

### Dynamic Tables + Semantic View + Cortex Agent + an evaluation harness that actually checks the answers

---

## 🏷️ Project Badges

[![Snowflake](https://img.shields.io/badge/Snowflake-Data_Cloud-29B5E8?style=for-the-badge&logo=snowflake&logoColor=white)](https://www.snowflake.com/)
[![SQL](https://img.shields.io/badge/SQL-Dynamic_Tables-4479A1?style=for-the-badge&logo=snowflake&logoColor=white)](https://docs.snowflake.com/en/user-guide/dynamic-tables-about)
[![Cortex AI](https://img.shields.io/badge/Cortex-Agents_%2B_Analyst-6E56CF?style=for-the-badge)](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
[![Python](https://img.shields.io/badge/Python-3.11-blue?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Status](https://img.shields.io/badge/Status-In_Development-yellow?style=for-the-badge)](https://github.com/deepan-mehta-analytics/snowflake-coco)

---

## 📌 Project Overview

This project implements **a governed, agent-queryable accounts-payable data platform entirely inside Snowflake** — no external orchestrator, no separate vector database, no copy of the data outside the warehouse.

It implements:

- **Multi-source ingestion** — raw landing tables for ERP batch exports, vendor portal API pulls, and OCR'd email attachments, each keeping its native shape and a full raw-payload column for lineage
- **Incremental conformance via Dynamic Tables** — a union/normalize layer, a flattened line-item table, and a vendor-level rollup, all auto-refreshed off the raw tables with no manual scheduling
- **A native Semantic View** — business-friendly facts, dimensions, and metrics (`total_outstanding`, `overdue_by_vendor`, etc.) that ground natural-language questions in governed SQL instead of ad hoc joins
- **A Cortex Agent with two tools** — Cortex Analyst (text-to-SQL over the semantic view) for quantitative questions, and Cortex Search over OCR'd invoice text for free-text questions
- **An evaluation harness** — a golden question/answer set scored against the live agent with pass/fail heuristics, so changes to the pipeline or agent config are checked against a fixed bar

---

## ⚙️ Tech Stack

| Layer | Tool | Purpose |
|---|---|---|
| Warehouse / Storage | Snowflake | Single platform for storage, transformation, and AI serving |
| Transformation | Dynamic Tables | Declarative, auto-refreshed incremental pipeline (no dbt/Airflow needed) |
| Semantic layer | Snowflake Semantic View | Governed facts/dimensions/metrics grounding the agent's text-to-SQL tool |
| Structured Q&A | Cortex Analyst | Text-to-SQL tool bound to the semantic view |
| Unstructured Q&A | Cortex Search | Text retrieval over OCR'd invoice documents |
| Orchestrating agent | Cortex Agents (REST API) | Combines both tools into one conversational interface |
| Agent client / eval | Python 3.11, `requests`, `pyyaml` | Calls the Agents REST API and scores answers |
| Deployment | Bash + Snowflake CLI (`snow sql`) | Applies all SQL in order against a target account |

---

## 🎯 Business Problem

AP teams routinely receive invoices through three or more disconnected channels — an ERP that only reflects what's been keyed in, a vendor portal vendors submit to directly, and PDFs that arrive by email and get OCR'd by hand or by a side tool. Answering "what do we currently owe, and to whom, and is any of it overdue" means manually reconciling across systems that don't share a vendor ID or a common schema.

> **Can accounts-payable invoice data from disconnected sources be unified into a single governed view — one that a non-technical user can query in plain English and trust the answer to?**

---

## 🏗️ Architecture

```
 [ERP Export]        [Vendor Portal API]        [OCR'd Email PDFs]
      │                      │                          │
      ▼                      ▼                          ▼
 raw.raw_erp_invoices   raw.raw_vendor_portal_invoices   raw.raw_ocr_email_invoices
      │                      │                          │
      └──────────────────────┼──────────────────────────┘
                              ▼
              conformed.dt_invoices_conformed   (Dynamic Table — union + normalize)
                    │                    │
                    ▼                    ▼
  conformed.dt_invoice_line_items   conformed.dt_vendor_invoice_summary
                    │                    │
                    └─────────┬──────────┘
                              ▼
                  semantic.sv_ap_invoices   (native Semantic View)
                              │
                 ┌────────────┴─────────────┐
                 ▼                          ▼
     Cortex Analyst (text-to-SQL)   Cortex Search (cs_invoice_documents)
                 │                          │
                 └────────────┬─────────────┘
                              ▼
               Cortex Agent — coco_ap_invoice_agent
                              │
                              ▼
                eval/ harness (golden_dataset.jsonl)
```

| Component | Role |
|---|---|
| `raw.*` tables | One landing table per source system, minimally transformed, full raw payload retained |
| `dt_invoices_conformed` | Dynamic Table unioning all 3 sources into one invoice-header shape |
| `dt_invoice_line_items` | Dynamic Table flattening vendor-portal line-item JSON |
| `dt_vendor_invoice_summary` | Dynamic Table rolling invoices up to one row per vendor, incl. overdue calc |
| `sv_ap_invoices` | Semantic View exposing facts/dimensions/metrics to Cortex Analyst |
| `cs_invoice_documents` | Cortex Search service indexing OCR'd invoice text |
| `coco_ap_invoice_agent` | Cortex Agent combining both tools behind one conversational interface |

---

## 📁 Repository Structure

```
snowflake-coco/
│
├── sql/
│   ├── 00_setup/
│   │   └── 00_database_schema_warehouse.sql   ← warehouse, database, schema creation + grants
│   ├── 01_raw_sources/
│   │   ├── 01_erp_invoices.sql                ← raw ERP landing table
│   │   ├── 02_vendor_portal_invoices.sql      ← raw vendor portal landing table
│   │   └── 03_ocr_email_invoices.sql          ← raw OCR email landing table
│   ├── 02_dynamic_tables/
│   │   ├── 01_dt_invoices_conformed.sql       ← unions all 3 sources into one shape
│   │   ├── 02_dt_invoice_line_items.sql       ← flattens vendor portal line items
│   │   └── 03_dt_vendor_invoice_summary.sql   ← vendor-level rollup + overdue calc
│   └── 03_semantic_view/
│       └── 01_sv_ap_invoices.sql              ← semantic view grounding the Cortex Agent
│
├── cortex_agent/
│   ├── 01_cortex_search_service.sql           ← Cortex Search over OCR'd invoice text
│   ├── agent_spec.yaml                        ← agent tool spec (semantic view + search)
│   └── run_agent.py                           ← REST client to run the agent interactively
│
├── eval/
│   ├── golden_dataset.jsonl                   ← hand-written Q&A evaluation set
│   ├── run_eval.py                            ← runs the golden set through the agent + scores it
│   ├── metrics.py                             ← scoring heuristics per question type
│   └── results/                               ← timestamped eval run outputs (gitignored)
│
├── config/
│   └── connection.example.toml                ← Snowflake connection template (copy → connection.toml)
│
├── scripts/
│   └── deploy.sh                               ← applies all sql/ files in order via the Snowflake CLI
│
├── requirements.txt                            ← Python deps for the agent client + eval harness
└── .gitignore
```

---

## ▶️ How to Run

### 📌 Option 1 — Local

#### 1. Clone the repository
```bash
git clone https://github.com/deepan-mehta-analytics/snowflake-coco.git
cd snowflake-coco
```

#### 2. Create and activate a virtual environment
```bash
python -m venv .venv
.venv\Scripts\activate      # Windows
source .venv/bin/activate    # macOS/Linux
```

#### 3. Install Python dependencies
```bash
pip install -r requirements.txt
```

#### 4. Configure your Snowflake connection
```bash
copy config\connection.example.toml config\connection.toml   # Windows
cp config/connection.example.toml config/connection.toml      # macOS/Linux
# then edit config/connection.toml with your account/user
```

#### 5. Deploy the pipeline
```bash
bash scripts/deploy.sh
```
This applies, in order: warehouse/database/schema setup → the 3 raw landing tables → the 3 Dynamic Tables → the semantic view.

#### 6. Create the Cortex Agent objects
```bash
snow sql -c coco -f cortex_agent/01_cortex_search_service.sql
```
Then register `cortex_agent/agent_spec.yaml` as an agent via Snowsight or the Cortex Agents API.

#### 7. Ask the agent a question
```bash
python cortex_agent/run_agent.py "Which vendors have overdue invoices right now?"
```

#### 8. Run the evaluation harness
```bash
python eval/run_eval.py
```

---

## 🧪 Tests

No automated unit/integration test suite yet — see Roadmap. Correctness today is checked via `eval/run_eval.py`, which runs the golden Q&A set (`eval/golden_dataset.jsonl`) against the live agent and applies heuristic pass/fail checks per question (`eval/metrics.py`).

---

## 📊 Results / Performance

Not yet populated — no data has been loaded into a live Snowflake account and no eval run has been executed against this scaffold. Once `scripts/deploy.sh` has been run against real invoice data, `eval/run_eval.py` output (pass rate + per-question notes) will be captured here.

---

## ⚠️ Known Limitations

- No real data has been loaded yet — all DDL is scaffolded and unexecuted against a live account
- Vendor identity resolution across sources (ERP `vendor_id` vs. OCR'd `vendor_name_raw`) is not implemented — OCR rows currently join on raw name text only
- `eval/metrics.py` checks are heuristic (keyword/shape-based), not semantic — a good answer can fail a check and vice versa
- No CI pipeline runs `eval/run_eval.py` automatically on change

## 🔜 Roadmap

- `v0.1.0` — First successful `scripts/deploy.sh` run against a live Snowflake trial account with sample data
- `v0.2.0` — Vendor identity resolution (fuzzy match OCR vendor names to ERP vendor master)
- `v0.3.0` — GitHub Actions workflow running `eval/run_eval.py` on every push
- `v1.0.0` — Documented, reproducible end-to-end demo with sample invoice data included in-repo

---

## 📂 Dataset

No public dataset is used — the pipeline is designed against synthetic/sample AP invoice data representative of ERP exports, vendor portal API responses, and OCR'd PDF extractions. Sample data has not yet been added to this repository (see Roadmap, `v0.1.0`).

---

## 👤 Author

**Deepan Mehta**

- Data Analytics → Data Engineering → AI/ML Engineering
- Focused on building end-to-end data and ML systems combining analytics, automation, and deployment
- Experience in ETL pipelines, predictive modelling, and analytical databases

🔗 GitHub: [deepan-mehta-analytics](https://github.com/deepan-mehta-analytics)

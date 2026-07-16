# 🧾 Snowflake COCO — Multi-Source AP Invoice Intelligence Pipeline

## ⚡ Quick Summary

COCO ingests accounts-payable invoices from four disconnected ERP/AP systems — SAP, Oracle, Baan, and Workday — and conforms them into a single, always-fresh Silver view of what the business owes. Snowflake Dynamic Tables handle the incremental transformation from bronze landing tables through to a vendor-level rollup, with source-specific quirks (status vocabularies, a known Baan duplicate-extract issue, dropped system-specific columns) handled per a set of documented, finance-approved business rules rather than ad hoc judgment calls.

On top of that pipeline sits a Snowflake Cortex Agent grounded in a native Semantic View: it answers quantitative questions ("which vendors have the most overdue invoices, and how much") via text-to-SQL against governed business metrics. A 15-question evaluation harness — covering core questions, rephrasings, edge cases, and deliberately ambiguous questions the agent should push back on — runs against the live agent so answer quality is measured, not assumed.

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

- **4-source bronze ingestion** — SAP, Oracle, Baan, and Workday AP invoice tables, each keeping its native column shape and loaded with realistic synthetic sample data (50 invoices total, 3 currencies)
- **Rule-driven Silver conformance via Dynamic Tables** — a single union/normalize layer implementing 9 documented business rules (status normalization, no currency conversion, Baan duplicate handling, dropped system-specific columns, `TARGET_LAG = DOWNSTREAM`), plus a vendor-level rollup
- **A native Semantic View** — business-friendly facts, dimensions, and metrics (`total_spend`, `overdue_by_vendor`, etc.) that ground natural-language questions in governed SQL instead of ad hoc joins
- **A Cortex Agent** — Cortex Analyst (text-to-SQL over the semantic view) answering quantitative AP questions
- **An evaluation harness** — a 15-question golden set (core / rephrasings / edge cases / deliberately ambiguous / data-validation) scored against the live agent with pass/fail heuristics

---

## ⚙️ Tech Stack

| Layer | Tool | Purpose |
|---|---|---|
| Warehouse / Storage | Snowflake | Single platform for storage, transformation, and AI serving |
| Transformation | Dynamic Tables | Declarative, auto-refreshed incremental pipeline (no dbt/Airflow needed) |
| Semantic layer | Snowflake Semantic View | Governed facts/dimensions/metrics grounding the agent's text-to-SQL tool |
| Structured Q&A | Cortex Analyst | Text-to-SQL tool bound to the semantic view |
| Orchestrating agent | Cortex Agents (REST API) | Wraps the Analyst tool in one conversational interface |
| Agent client / eval | Python 3.11, `requests`, `pyyaml` | Calls the Agents REST API and scores answers |
| Deployment | Bash + Snowflake CLI (`snow sql`) | Applies all SQL in order against a target account |

---

## 🎯 Business Problem

AP teams routinely receive invoices through four or more disconnected ERP/AP systems, each with its own vendor ID scheme, status vocabulary, GL account format, and payment-terms notation. Answering "what do we currently owe, and to whom, and is any of it overdue" means manually reconciling across systems that don't share a common schema — and doing it consistently enough that finance trusts the answer.

> **Can accounts-payable invoice data from four disconnected ERP/AP systems be unified into a single governed view — one that a non-technical user can query in plain English and trust the answer to?**

---

## 🏗️ Architecture

```
   [SAP]         [Oracle]         [Baan]          [Workday]
     │               │               │                │
     ▼               ▼               ▼                ▼
bronze.sap_ap_   bronze.oracle_   bronze.baan_    bronze.workday_
  invoices       ap_invoices      ap_invoices      ap_invoices
     │               │               │                │
     └───────────────┼───────────────┼────────────────┘
                              ▼
              silver.dt_silver_ap_invoices   (Dynamic Table — union + BR-001..BR-009)
                              │
                              ▼
                 silver.dt_vendor_invoice_summary   (Dynamic Table — vendor rollup)
                              │
                              ▼
                  semantic.sv_ap_analytics   (native Semantic View)
                              │
                              ▼
                  Cortex Analyst (text-to-SQL)
                              │
                              ▼
                   Cortex Agent — ap_invoice_agent
                              │
                              ▼
                eval/ harness (15-question golden set)
```

| Component | Role |
|---|---|
| `bronze.*_ap_invoices` | One landing table per source system (SAP, Oracle, Baan, Workday), native column shapes preserved |
| `dt_silver_ap_invoices` | Dynamic Table unioning all 4 sources into one invoice-header shape, per BR-001..BR-009 |
| `dt_vendor_invoice_summary` | Dynamic Table rolling invoices up to one row per vendor, incl. pending/overdue exposure |
| `sv_ap_analytics` | Semantic View exposing facts/dimensions/metrics to Cortex Analyst |
| `ap_invoice_agent` | Cortex Agent wrapping the Analyst tool behind one conversational interface |

---

## 📁 Repository Structure

```
snowflake-coco/
│
├── sql/
│   ├── 00_setup/
│   │   └── 00_database_schema_warehouse.sql   ← warehouse, bronze/silver/semantic schema creation + grants
│   ├── 01_bronze_sources/
│   │   ├── 01_sap_ap_invoices.sql             ← bronze SAP table + 15 sample invoices
│   │   ├── 02_oracle_ap_invoices.sql          ← bronze Oracle table + 15 sample invoices
│   │   ├── 03_baan_ap_invoices.sql            ← bronze Baan table + 10 sample invoices
│   │   └── 04_workday_ap_invoices.sql         ← bronze Workday table + 10 sample invoices
│   ├── 02_silver/
│   │   ├── 01_dt_silver_ap_invoices.sql       ← unions all 4 sources per BR-001..BR-009
│   │   └── 02_dt_vendor_invoice_summary.sql   ← vendor-level rollup + pending/overdue calc
│   └── 03_semantic_view/
│       └── 01_sv_ap_analytics.sql             ← semantic view grounding the Cortex Agent
│
├── cortex_agent/
│   ├── agent_spec.yaml                        ← agent tool spec (Cortex Analyst over sv_ap_analytics)
│   └── run_agent.py                           ← REST client to run the agent interactively
│
├── eval/
│   ├── golden_dataset.jsonl                   ← 15-question golden set (core/variation/edge/ambiguous/validation)
│   ├── run_eval.py                            ← runs the golden set through the agent + scores it
│   ├── metrics.py                             ← scoring heuristics per question type
│   └── results/                               ← timestamped eval run outputs (gitignored)
│
├── docs/
│   └── business_requirements/                 ← source CSVs behind the Silver DT's design decisions
│       ├── README.md                          ← BR-### → implementation cross-reference
│       ├── sample_business_requirements_source_onboarding.csv
│       ├── sample_business_requirements_column_mapping.csv
│       └── sample_business_requirements_business_rules.csv
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
This applies, in order: warehouse/database/schema setup → the 4 bronze source tables (with sample data) → the 2 Silver Dynamic Tables → the semantic view.

#### 6. Register the Cortex Agent
Register `cortex_agent/agent_spec.yaml` as an agent via Snowsight or the Cortex Agents API.

#### 7. Ask the agent a question
```bash
python cortex_agent/run_agent.py "Which vendors have the most overdue invoices?"
```

#### 8. Run the evaluation harness
```bash
python eval/run_eval.py
```

---

## 🧪 Tests

No automated unit/integration test suite yet — see Roadmap. Correctness today is checked via `eval/run_eval.py`, which runs the 15-question golden set (`eval/golden_dataset.jsonl`) against the live agent and applies heuristic pass/fail checks per question (`eval/metrics.py`).

---

## 📊 Results / Performance

Not yet populated — no data has been loaded into a live Snowflake account and no eval run has been executed. Once `scripts/deploy.sh` has been run, `eval/run_eval.py` output (pass rate + per-question notes) will be captured here.

---

## ⚠️ Known Limitations

- No live Snowflake account has run this yet — all DDL/sample data is unexecuted against a real account
- Payment-terms formats differ per source (`NET30` vs `N30` vs `Net 30`) and are intentionally left unnormalized at Silver — an open decision per BR-005, deferred to a future Gold layer
- GL account codes are not cross-mapped across sources (BR-006) — a unified chart of accounts is a Phase 2 concern, not implemented here
- The source data has no paid/unpaid flag — "overdue" is approximated as `due_date < CURRENT_DATE()`, not a true payment-settled indicator
- `eval/metrics.py` checks are heuristic (keyword/shape-based), not semantic — a good answer can fail a check and vice versa
- No CI pipeline runs `eval/run_eval.py` automatically on change
- No unstructured/OCR document search — this repo's scope was narrowed to match the real reference dataset (structured ERP/AP sources only); Cortex Search over scanned invoice text is a possible future extension, not implemented

## 🔜 Roadmap

- `v0.1.0` — First successful `scripts/deploy.sh` run against a live Snowflake trial account
- `v0.2.0` — BR-004 data-quality guardrail: flag invoices > $500K USD-equivalent via a Data Metric Function
- `v0.3.0` — GitHub Actions workflow running `eval/run_eval.py` on every push
- `v1.0.0` — Documented, reproducible end-to-end demo with a captured eval run in this README

---

## 📂 Dataset

Synthetic AP invoice data (50 invoices across SAP, Oracle, Baan, and Workday; USD/EUR/GBP) plus the accompanying business-requirements CSVs and 15-question evaluation set are sourced from Snowflake's official **[Cortex Code Foundations](https://github.com/hindcraig3/cortex-code-foundations)** workshop — a hands-on lab for Snowflake's Cortex Code (CoCo) AI coding agent. This repo implements the pipeline that workshop describes (Dynamic Tables → Semantic View → Cortex Agent → evaluation framework) as a standalone, version-controlled project. See `docs/business_requirements/README.md` for the rule-by-rule mapping from that workshop's requirements to this repo's SQL.

---

## 👤 Author

**Deepan Mehta**

- Data Analytics → Data Engineering → AI/ML Engineering
- Focused on building end-to-end data and ML systems combining analytics, automation, and deployment
- Experience in ETL pipelines, predictive modelling, and analytical databases

🔗 GitHub: [deepan-mehta-analytics](https://github.com/deepan-mehta-analytics)

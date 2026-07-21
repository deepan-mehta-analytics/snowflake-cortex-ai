# 🧾 Snowflake Cortex AI

## ⚡ Quick Summary

This pipeline ingests accounts-payable invoices from four disconnected ERP/AP systems — SAP, Oracle, Baan, and Workday — and conforms them into a single, always-fresh Silver view of what the business owes. Snowflake Dynamic Tables handle the incremental transformation from bronze landing tables through to a vendor-level rollup, with source-specific quirks (status vocabularies, a known Baan duplicate-extract issue, dropped system-specific columns) handled per a set of documented, finance-approved business rules rather than ad hoc judgment calls.

On top of that pipeline sits a Snowflake Cortex Agent grounded in a native Semantic View: it answers quantitative questions ("which vendors have the most overdue invoices, and how much") via text-to-SQL against governed business metrics. A 15-question evaluation harness — covering core questions, rephrasings, edge cases, and deliberately ambiguous questions the agent should push back on — runs against the live agent so answer quality is measured, not assumed.

### Multi-source AP invoices → Dynamic Tables → Semantic View → Cortex Agent

---

## 🏷️ Project Badges

[![Snowflake](https://img.shields.io/badge/Snowflake-Data_Cloud-29B5E8?style=for-the-badge&logo=snowflake&logoColor=white)](https://www.snowflake.com/)
[![SQL](https://img.shields.io/badge/SQL-Dynamic_Tables-4479A1?style=for-the-badge&logo=snowflake&logoColor=white)](https://docs.snowflake.com/en/user-guide/dynamic-tables-about)
[![Cortex AI](https://img.shields.io/badge/Cortex-Agents_%2B_Analyst-6E56CF?style=for-the-badge)](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
[![Python](https://img.shields.io/badge/Python-3.11-blue?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Status](https://img.shields.io/badge/Status-Live_on_Snowflake-brightgreen?style=for-the-badge)](https://github.com/deepan-mehta-analytics/snowflake-cortex-ai)

---

## 📌 Project Overview

This project implements **a governed, agent-queryable accounts-payable data platform entirely inside Snowflake** — no external orchestrator, no separate vector database, no copy of the data outside the warehouse.

It implements:

- **4-source bronze ingestion** — SAP, Oracle, Baan, and Workday AP invoice tables, each keeping its native column shape and loaded with realistic synthetic sample data (50 invoices total, 3 currencies)
- **Rule-driven Silver conformance via Dynamic Tables** — a single union/normalize layer implementing 9 documented business rules (status normalization, no currency conversion, Baan duplicate handling, dropped system-specific columns, `TARGET_LAG = DOWNSTREAM`), plus a vendor-level rollup
- **A native Semantic View** — business-friendly facts, dimensions, and metrics (`total_spend`, `overdue_by_vendor`, etc.) that ground natural-language questions in governed SQL instead of ad hoc joins
- **A Cortex Search service** — semantic search over free-text invoice line descriptions (`ap_invoice_search`), for fuzzy lookups that don't map cleanly to a `WHERE` clause
- **A Cortex Agent** — Cortex Analyst (text-to-SQL over the semantic view) plus Cortex Search, answering both quantitative and free-text AP questions
- **An evaluation harness** — a 15-question golden set (core / rephrasings / edge cases / deliberately ambiguous / data-validation) scored against the live agent with pass/fail heuristics

---

## ⚙️ Tech Stack

| Layer | Tool | Purpose |
|---|---|---|
| Warehouse / Storage | Snowflake | Single platform for storage, transformation, and AI serving |
| Transformation | Dynamic Tables | Declarative, auto-refreshed incremental pipeline (no dbt/Airflow needed) |
| Semantic layer | Snowflake Semantic View | Governed facts/dimensions/metrics grounding the agent's text-to-SQL tool |
| Structured Q&A | Cortex Analyst | Text-to-SQL tool bound to the semantic view |
| Unstructured Q&A | Cortex Search | Semantic search over free-text invoice line descriptions |
| Orchestrating agent | Cortex Agents (REST API) | Wraps the Analyst and Search tools in one conversational interface |
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
                 ┌────────────┴────────────┐
                 ▼                          ▼
     semantic.sv_ap_analytics    agent.ap_invoice_search
     (native Semantic View)      (Cortex Search service)
                 │                          │
                 ▼                          ▼
     Cortex Analyst (text-to-SQL)   Cortex Search (semantic lookup)
                 │                          │
                 └────────────┬─────────────┘
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
| `ap_invoice_search` | Cortex Search service over `line_description`, for fuzzy/semantic invoice lookup |
| `ap_invoice_agent` | Cortex Agent wrapping the Analyst and Search tools behind one conversational interface |

---

## 📁 Repository Structure

```
snowflake-cortex-ai/
│
├── sql/
│   ├── 00_setup/
│   │   ├── 00_database_schema_warehouse.sql   ← warehouse, bronze/silver/semantic schema creation + grants
│   │   └── 01_github_git_integration.sql      ← optional: SECRET + API INTEGRATION + GIT REPOSITORY for Snowflake Workspaces
│   ├── 01_bronze_sources/
│   │   ├── 01_sap_ap_invoices.sql             ← bronze SAP table + 15 sample invoices
│   │   ├── 02_oracle_ap_invoices.sql          ← bronze Oracle table + 15 sample invoices
│   │   ├── 03_baan_ap_invoices.sql            ← bronze Baan table + 10 sample invoices
│   │   └── 04_workday_ap_invoices.sql         ← bronze Workday table + 10 sample invoices
│   ├── 02_silver/
│   │   ├── 01_dt_silver_ap_invoices.sql       ← unions all 4 sources per BR-001..BR-009
│   │   └── 02_dt_vendor_invoice_summary.sql   ← vendor-level rollup + pending/overdue calc
│   └── 03_semantic_view/
│       ├── 01_sv_ap_analytics.sql             ← semantic view grounding Cortex Analyst
│       └── 02_cs_ap_invoice_search.sql        ← Cortex Search service grounding free-text lookup
│
├── cortex_agent/
│   ├── agent_spec.yaml                        ← agent tool spec (Cortex Analyst + Cortex Search)
│   └── run_agent.py                           ← REST client to run the agent interactively
│
├── eval/
│   ├── golden_dataset.jsonl                   ← 15-question golden set (core/variation/edge/ambiguous/validation)
│   ├── run_eval.py                            ← runs the golden set through the agent + scores it
│   ├── metrics.py                             ← scoring heuristics per question type
│   └── results/                               ← timestamped eval run outputs (gitignored)
│
├── docs/
│   ├── business_requirements/                 ← source CSVs behind the Silver DT's design decisions
│   │   ├── README.md                          ← BR-### → implementation cross-reference
│   │   ├── sample_business_requirements_source_onboarding.csv
│   │   ├── sample_business_requirements_column_mapping.csv
│   │   └── sample_business_requirements_business_rules.csv
│   └── dynamic-tables-reference/              ← Dynamic Tables best-practice reference material (plain docs)
│
├── labs/                                       ← Snowflake Northstar badge lab materials (separate from the pipeline above)
│   ├── coco-foundations/                       ← CoCo Foundations lab assets + how-to-run README
│   ├── from-zero-to-agents/                    ← From Zero to Agents lab assets + how-to-run README
│   └── northstar-data-engineering/             ← Data Engineering with Snowflake lab assets + how-to-run README
│
├── cortex_project/                              ← Snowflake CLI declarative project definition, auto-generated by Snowsight Agent Studio
│   ├── cortex-project.yaml                      ← project manifest (artifact → deployment target)
│   └── ap_invoice_agent.agent.yaml              ← CLI-deployable equivalent of cortex_agent/agent_spec.yaml
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
git clone https://github.com/deepan-mehta-analytics/snowflake-cortex-ai.git
cd snowflake-cortex-ai
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
This applies, in order: warehouse/database/schema setup → the 4 bronze source tables (with sample data) → the 2 Silver Dynamic Tables → the semantic view → the Cortex Search service.

#### 6. Set your Snowflake REST API credentials
`run_agent.py` calls the Cortex Agents and SQL APIs directly with a Personal Access Token — it does not require registering a saved agent object first.
```bash
# PowerShell
$env:SNOWFLAKE_ACCOUNT = "<org>-<account>"     # e.g. from your Snowsight URL: app.snowflake.com/<org>/<account>/...
$env:SNOWFLAKE_PAT = "<your PAT>"              # generate via ALTER USER <you> ADD PROGRAMMATIC ACCESS TOKEN ...
```
Note: PATs require `PROGRAMMATIC_ACCESS_TOKEN` to be listed in your account's authentication policy, and a network policy must be attached to the user (Snowflake enforces this for PATs even with an unrestricted `0.0.0.0/0` policy) — see `ALTER AUTHENTICATION POLICY` / `ALTER USER ... SET NETWORK_POLICY` if token creation is rejected.

#### 7. Ask the agent a question
```bash
python cortex_agent/run_agent.py "Which vendors have the most overdue invoices?"
```
The `cortex_analyst_text_to_sql` tool returns governed SQL rather than executed results, so `run_agent.py` runs that SQL itself via the SQL API and prints the interpretation plus real rows.

#### 8. Run the evaluation harness
```bash
python eval/run_eval.py
```

---

## 🧪 Tests

No automated unit/integration test suite yet — see Roadmap. Correctness today is checked via `eval/run_eval.py`, which runs the 15-question golden set (`eval/golden_dataset.jsonl`) against the live agent and applies heuristic pass/fail checks per question (`eval/metrics.py`).

---

## 📊 Results / Performance

Deployed and evaluated end-to-end against a live Snowflake trial account (2026-07-16).

**Pipeline row counts** (bronze → silver, all verified via `SHOW`/`SELECT` after each step, not just a bare success message):

| Table | Rows |
|---|---|
| `bronze.sap_ap_invoices` | 15 |
| `bronze.oracle_ap_invoices` | 15 |
| `bronze.baan_ap_invoices` | 10 |
| `bronze.workday_ap_invoices` | 10 |
| `silver.dt_silver_ap_invoices` | 50 (union of all 4 sources) |

**Evaluation harness — 13/15 checks passed** (`eval/run_eval.py` against the live agent):

| Category | Result |
|---|---|
| Core (6 questions) | 6/6 passed |
| Rephrasings/variation (4 questions) | 4/4 passed |
| Edge cases (2 questions) | 2/2 passed |
| Deliberately ambiguous (2 questions) | 0/2 passed |
| Data validation (1 question) | 1/1 passed |

The 2 ambiguous-category failures are heuristic-scoring gaps, not agent defects: one question ("Which vendors are problematic?") correctly triggered a refusal for a subjective/discriminatory framing, and the other ("Show me recent invoices") got a reasonable default interpretation — `eval/metrics.py`'s keyword-based grounding check just doesn't recognize either phrasing style. See Known Limitations.

Sample query, run live via `python cortex_agent/run_agent.py "Which vendors have the most overdue invoices?"`:
```
This is our interpretation of your question:

Which vendors have the most overdue invoices, ranked by total overdue amount in descending order?

VENDOR_NAME, VENDOR_TOTAL_OVERDUE_AMOUNT
Summit Energy Corp, 197600.00
National Insurance Brokers, 133500.00
Apex Staffing Solutions, 100000.00
...
```

---

## ⚠️ Known Limitations

- Payment-terms formats differ per source (`NET30` vs `N30` vs `Net 30`) and are intentionally left unnormalized at Silver — an open decision per BR-005, deferred to a future Gold layer
- GL account codes are not cross-mapped across sources (BR-006) — a unified chart of accounts is a Phase 2 concern, not implemented here
- The source data has no paid/unpaid flag — "overdue" is approximated as `due_date < CURRENT_DATE()` — since the sample data is dated 2025, this approximation drifts further from reality the longer the demo sits unrefreshed
- `eval/metrics.py` checks are heuristic (keyword/shape-based), not semantic — a good answer can fail a check and vice versa; the 2 failing "ambiguous" checks in the results above are scorer gaps, not agent defects
- No CI pipeline runs `eval/run_eval.py` automatically on change
- Snowsight's Agent Studio UI and the `DATA_AGENT_RUN` SQL function were both unreliable for testing the registered agent object during development (hung/incomplete tool configuration); `cortex_agent/run_agent.py`'s direct REST client sidesteps this by embedding the full tool spec in each call rather than depending on the registered agent object, and is the supported path for this repo
- The `cortex_analyst_text_to_sql` tool returns governed SQL, not executed results — `run_agent.py` executes that SQL itself via the SQL API rather than relying on the orchestration model to do so
- `ap_invoice_search` (Cortex Search over `line_description`) is wired into `agent_spec.yaml`, but `run_agent.py`'s result formatting has only been exercised against `cortex_analyst_text_to_sql` responses — its `cortex_search` result handling is an untested generic JSON fallback, not a confirmed-working formatter, until it's actually run live

## 🔜 Roadmap

- `v0.2.0` — BR-004 data-quality guardrail: flag invoices > $500K USD-equivalent via a Data Metric Function
- `v0.3.0` — GitHub Actions workflow running `eval/run_eval.py` on every push
- `v1.0.0` — Documented, reproducible end-to-end demo with CI-verified eval results

---

## 📂 Dataset

Synthetic AP invoice data (50 invoices across SAP, Oracle, Baan, and Workday; USD/EUR/GBP) plus the accompanying business-requirements CSVs and 15-question evaluation set are sourced from Snowflake's official **[Cortex Code Foundations](https://github.com/hindcraig3/cortex-code-foundations)** workshop — a hands-on lab for Snowflake's Cortex Code (CoCo) AI coding agent. This repo implements the pipeline that workshop describes (Dynamic Tables → Semantic View → Cortex Agent → evaluation framework) as a standalone, version-controlled project. See `docs/business_requirements/README.md` for the rule-by-rule mapping from that workshop's requirements to this repo's SQL, and `docs/dynamic-tables-reference/README.md` for the Dynamic Tables best-practice reference the Silver layer's design follows.

---

## 👤 Author

**Deepan Mehta**

- Data Analytics → Data Engineering → AI/ML Engineering
- Focused on building end-to-end data and ML systems combining analytics, automation, and deployment
- Experience in ETL pipelines, predictive modelling, and analytical databases

🔗 GitHub: [deepan-mehta-analytics](https://github.com/deepan-mehta-analytics)

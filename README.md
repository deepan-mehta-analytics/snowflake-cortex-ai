# 🧾 Snowflake Cortex AI

## ⚡ Quick Summary

This pipeline ingests accounts-payable invoices from four disconnected ERP/AP systems — SAP, Oracle, Baan, and Workday — and conforms them into a single, always-fresh Silver view of what the business owes. Snowflake Dynamic Tables handle the incremental transformation from bronze landing tables through to a vendor-level rollup, with source-specific quirks (status vocabularies, a known Baan duplicate-extract issue, dropped system-specific columns) handled per a set of documented, finance-approved business rules rather than ad hoc judgment calls.

On top of that pipeline sits a Snowflake Cortex Agent grounded in a native Semantic View: it answers quantitative questions ("which vendors have the most overdue invoices, and how much") via text-to-SQL against governed business metrics. A 15-question evaluation harness — covering core questions, rephrasings, edge cases, and deliberately ambiguous questions the agent should push back on — runs against the live agent so answer quality is measured, not assumed. The same agent is also published through a Snowflake-managed MCP server, so Claude can query it directly over OAuth as a least-privilege Snowflake user.

### Multi-source AP invoices → Dynamic Tables → Semantic View → Cortex Agent → MCP for Claude

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
- **A Snowflake-managed MCP server** — `coco.mcp.ap_invoice_mcp` exposes the agent, Cortex Analyst and Cortex Search as 3 MCP tools, connected to Claude (claude.ai custom connector) via Snowflake OAuth as a dedicated user pinned to a narrow read-only role
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
| AI client access | Snowflake-managed MCP server + Snowflake OAuth | Exposes agent / Analyst / Search as MCP tools to Claude under a least-privilege role |
| Agent client / eval | Python 3.11 (project `.venv`), `requests`, `pyyaml` | Calls the Agents REST API and scores answers |
| Direct SQL checks (dev) | `snowflake-connector-python` with PAT auth | Live verification queries; installed via `requirements-dev.txt` |
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
                 ┌────────────┴────────────┐
                 ▼                          ▼
   eval/ harness (15-question     mcp.ap_invoice_mcp  (Snowflake-managed MCP server:
   golden set, REST client)        agent + analyst + search tools)
                                            │  Snowflake OAuth, claude_mcp_user → mcp_claude_role
                                            ▼
                                  Claude (claude.ai custom connector)
```

| Component | Role |
|---|---|
| `bronze.*_ap_invoices` | One landing table per source system (SAP, Oracle, Baan, Workday), native column shapes preserved |
| `dt_silver_ap_invoices` | Dynamic Table unioning all 4 sources into one invoice-header shape, per BR-001..BR-009 |
| `dt_vendor_invoice_summary` | Dynamic Table rolling invoices up to one row per vendor, incl. pending/overdue exposure |
| `sv_ap_analytics` | Semantic View exposing facts/dimensions/metrics to Cortex Analyst |
| `ap_invoice_search` | Cortex Search service over `line_description`, for fuzzy/semantic invoice lookup |
| `ap_invoice_agent` | Cortex Agent wrapping the Analyst and Search tools behind one conversational interface |
| `ap_invoice_mcp` | Snowflake-managed MCP server publishing the agent, Analyst and Search as tools for Claude |
| `mcp_claude_oauth` / `mcp_claude_role` | OAuth integration + least-privilege role the Claude connector signs in with (read access to Silver + semantic view only) |

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
│   ├── 03_semantic_view/
│   │   ├── 01_sv_ap_analytics.sql             ← semantic view grounding Cortex Analyst
│   │   └── 02_cs_ap_invoice_search.sql        ← Cortex Search service grounding free-text lookup
│   └── 04_mcp/                                ← manual, run in Snowsight (not part of deploy.sh)
│       ├── 00_mcp_role_and_user.sql           ← least-privilege role + dedicated Claude user (placeholders only)
│       ├── 00b_fix_ap_invoice_agent.sql       ← rebuilds the registered agent spec (both tools, MCP-usable warehouse)
│       ├── 01_mcp_server.sql                  ← Snowflake-managed MCP server with 3 tools
│       ├── 02_oauth_security_integration.sql  ← Snowflake OAuth client for the claude.ai connector
│       ├── 03_optional_readonly_sql_server.sql ← optional separate read-only SQL MCP server (not deployed)
│       ├── 04_verify.sql                      ← read-only checks + builds the connector URL
│       └── 99_teardown.sql                    ← removes all MCP access
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
├── cortex_project/                              ← Snowflake CLI declarative project definition (first generated by Agent Studio, now hand-synced)
│   ├── cortex-project.yaml                      ← project manifest (artifact → deployment target)
│   └── ap_invoice_agent.agent.yaml              ← live spec of the registered agent (matches sql/04_mcp/00b)
│
├── config/
│   └── connection.example.toml                ← Snowflake connection template (copy → connection.toml)
│
├── scripts/
│   └── deploy.sh                               ← applies all sql/ files in order via the Snowflake CLI
│
├── requirements.txt                            ← Python deps for the agent client + eval harness
├── requirements-dev.txt                        ← adds the Snowflake Python connector for direct SQL checks
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
pip install -r requirements.txt        # agent client + eval harness (requests, pyyaml)
pip install -r requirements-dev.txt    # optional: adds snowflake-connector-python for direct SQL checks
```
Install into the project's `.venv`, not your global Python. The connector pulls in many transitive packages, and a shared global environment makes dependency conflicts hard to attribute. `pip check` inside the venv should report no broken requirements.

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

#### 9. (Optional) Connect the agent to Claude via MCP
Run the `sql/04_mcp/` scripts in a Snowsight worksheet in order — `00` → `00b` → `01` → `02` → `04` (skip `03`). Fill the password/email placeholders in the worksheet only, never in the file. Then in claude.ai → Settings → Connectors → *Add custom connector*, paste the URL printed by `04_verify.sql` (`https://<account>.snowflakecomputing.com/api/v2/databases/COCO/schemas/MCP/mcp-servers/AP_INVOICE_MCP`) and the OAuth client ID/secret from `02`, then sign in as `claude_mcp_user`. `99_teardown.sql` removes everything.

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

**MCP smoke test — 3/3 tools working from Claude** (2026-10-02, via the claude.ai connector):

| MCP tool | Test question | Result |
|---|---|---|
| `ap-invoice-search` | "hydraulic equipment" | Top hits "Hydraulic pumps Q1/Q2 order" |
| `ap-invoice-analyst` | "Which vendors have the highest total invoice amount?" | Correct `SEMANTIC_VIEW(... METRICS total_spend DIMENSIONS vendor_name)` SQL |
| `ap-invoice-agent` | "How many invoices per source system, and total spend for each?" | Executed SQL: SAP 15 / Oracle 15 / Baan 10 / Workday 10 = 50; spend kept per currency (BR-002) |

---

## ⚠️ Known Limitations

- Payment-terms formats differ per source (`NET30` vs `N30` vs `Net 30`) and are intentionally left unnormalized at Silver — an open decision per BR-005, deferred to a future Gold layer
- GL account codes are not cross-mapped across sources (BR-006) — a unified chart of accounts is a Phase 2 concern, not implemented here
- The source data has no paid/unpaid flag — "overdue" is approximated as `due_date < CURRENT_DATE()` — since the sample data is dated 2025, this approximation drifts further from reality the longer the demo sits unrefreshed. By 2026-10-03 it had fully drifted: the live agent counted all 50 invoices as overdue, so overdue-based answers no longer separate vendors meaningfully until the dates are refreshed or a paid flag is added
- `eval/metrics.py` checks are heuristic (keyword/shape-based), not semantic — a good answer can fail a check and vice versa; the 2 failing "ambiguous" checks in the results above are scorer gaps, not agent defects
- No CI pipeline runs `eval/run_eval.py` automatically on change
- Snowsight's Agent Studio UI and the `DATA_AGENT_RUN` SQL function were both unreliable for testing the registered agent object during development (hung/incomplete tool configuration); `cortex_agent/run_agent.py`'s direct REST client sidesteps this by embedding the full tool spec in each call rather than depending on the registered agent object, and is the path the eval harness uses. The registered agent object itself was later rebuilt in SQL (`sql/04_mcp/00b_fix_ap_invoice_agent.sql`) and is now exercised live through the MCP server
- The `cortex_analyst_text_to_sql` tool returns governed SQL, not executed results — `run_agent.py` executes that SQL itself via the SQL API rather than relying on the orchestration model to do so
- `ap_invoice_search` (Cortex Search over `line_description`) is confirmed working live through the MCP server, but `run_agent.py`'s own result formatting has only been exercised against `cortex_analyst_text_to_sql` responses — its `cortex_search` handling is still an untested generic JSON fallback
- The MCP connector runs as a dedicated `claude_mcp_user`, because Claude always requests the `session:role:all` OAuth scope and so uses the signed-in user's default role; Cortex usage through the connector is billed to the account like any other Cortex call

---

## 🔜 Roadmap

- [x] `v0.2.0` — Snowflake-managed MCP server exposing the agent, Analyst and Search to Claude (shipped 2026-10-02)
- `v0.3.0` — BR-004 data-quality guardrail: flag invoices > $500K USD-equivalent via a Data Metric Function
- `v0.4.0` — GitHub Actions workflow running `eval/run_eval.py` on every push
- `v1.0.0` — Documented, reproducible end-to-end demo with CI-verified eval results

---

## 📂 Dataset

**Source:** Snowflake's official **[Cortex Code Foundations](https://github.com/hindcraig3/cortex-code-foundations)** workshop, a hands-on lab for Snowflake's Cortex Code (CoCo) AI coding agent. All data is synthetic.

**What's included**
- **AP invoices** — 50 synthetic invoices, each source system keeping its native column shape:

  | Source | Invoices |
  |---|---|
  | SAP | 15 |
  | Oracle | 15 |
  | Baan | 10 |
  | Workday | 10 |

- **Currencies** — USD, EUR and GBP, deliberately not converted (BR-002)
- **Business requirements** — 3 CSVs (source onboarding, column mapping, business rules) that drive the Silver layer's design, in `docs/business_requirements/`
- **Evaluation set** — 15 golden questions (core, rephrasings, edge cases, deliberately ambiguous, data validation) in `eval/golden_dataset.jsonl`

**How this repo uses it**
- Implements the pipeline the workshop describes (Dynamic Tables → Semantic View → Cortex Agent → evaluation framework) as a standalone, version-controlled project
- `docs/business_requirements/README.md` maps each workshop requirement (BR-###) to the SQL that implements it
- `docs/dynamic-tables-reference/README.md` holds the Dynamic Tables best-practice reference the Silver layer follows

**Caveat**
- The invoices are dated 2025, so the "overdue" approximation (`due_date < CURRENT_DATE()`) now counts all 50 as overdue (see Known Limitations)

**Related**
- The workshop itself, alongside the other Snowflake badge labs, is documented separately in [`snowflake-workshop-labs`](https://github.com/deepan-mehta-analytics/snowflake-workshop-labs)

---

## 👤 Author

**Deepan Mehta**

- Data Analytics → Data Engineering → AI/ML Engineering
- Focused on building end-to-end data and ML systems combining analytics, automation, and deployment
- Experience in ETL pipelines, predictive modelling, and analytical databases

🔗 GitHub: [deepan-mehta-analytics](https://github.com/deepan-mehta-analytics)

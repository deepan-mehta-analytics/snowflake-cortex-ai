# 🧾 Snowflake Cortex AI

## ⚡ Quick Summary

This pipeline ingests accounts-payable invoices from four disconnected ERP/AP systems — SAP, Oracle, Baan, and Workday — and conforms them into a single, always-fresh Silver view of what the business owes. Snowflake Dynamic Tables handle the incremental transformation from bronze landing tables through to a vendor-level rollup, with source-specific quirks (status vocabularies, a known Baan duplicate-extract issue, dropped system-specific columns) handled per a set of documented, finance-approved business rules rather than ad hoc judgment calls.

On top of that pipeline sits a Snowflake Cortex Agent grounded in a native Semantic View: it answers quantitative questions ("which vendors have the most overdue invoices, and how much") via text-to-SQL against governed business metrics. A 15-question evaluation harness — covering core questions, rephrasings, edge cases, and deliberately ambiguous questions the agent should push back on — runs against the live agent so answer quality is measured, not assumed. The same agent is also published through a Snowflake-managed MCP server, so Claude can query it directly over OAuth as a least-privilege Snowflake user. A data-quality guardrail (BR-004) watches the Silver invoices for anything over USD 500,000 at the invoice-date exchange rate: a Data Metric Function with a Finance-owned tolerance, a review queue of flagged invoices, and a daily email alert — proven against seeded boundary cases before being trusted.

### Multi-source AP invoices → Dynamic Tables → Semantic View → Cortex Agent → MCP for Claude, guarded by data-quality checks

---

## 🏷️ Project Badges

[![Snowflake](https://img.shields.io/badge/Snowflake-Data_Cloud-29B5E8?style=for-the-badge&logo=snowflake&logoColor=white)](https://www.snowflake.com/)
[![SQL](https://img.shields.io/badge/SQL-Dynamic_Tables-4479A1?style=for-the-badge&logo=snowflake&logoColor=white)](https://docs.snowflake.com/en/user-guide/dynamic-tables-about)
[![Cortex AI](https://img.shields.io/badge/Cortex-Agents_%2B_Analyst-6E56CF?style=for-the-badge)](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
[![Data Quality](https://img.shields.io/badge/Data_Quality-DMF_%2B_Alerts-29B5E8?style=for-the-badge&logo=snowflake&logoColor=white)](https://docs.snowflake.com/en/user-guide/data-quality-intro)
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
- **A BR-004 data-quality guardrail** — a Data Metric Function on Silver counts invoices over USD 500,000 at the invoice-date FX rate (Snowflake's free ECB/BIS dataset, latest rate on or before the invoice date), plus any it can't assess (fail-safe); an expectation fails above a Finance-owned tolerance of 2; a review-queue view lists every flagged invoice; a serverless alert emails when the tolerance is breached; a one-off task stops it all after a 10-day run
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
| Agent client / eval | Python 3.11 (project `.venv`), `requests`, `pytest` | Runs the registered agent over the Agents REST API, scores answers; offline parser tests |
| Data quality | Data Metric Function + expectation, Snowflake Alert, serverless Task | BR-004 high-value invoice guardrail, daily email, 10-day auto-stop |
| FX rates | Snowflake Public Data (free) — ECB/BIS daily rates | USD-equivalent amounts at the invoice-date rate |
| Direct SQL checks (dev) | `snowflake-connector-python` with PAT auth, `scripts/run_sql_checks.py` | Live verification queries and pass/fail SQL checks; installed via `requirements-dev.txt` |
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
                              ├──► guardrails (BR-004, read-only on Silver)
                              │      count_invoices_over_usd_500k  (DMF, daily 06:00 UTC, expectation VALUE <= 2)
                              │        ◄── guardrails.fx_rates  (free ECB/BIS FX, invoice-date rate)
                              │      high_value_invoices_for_review  (review queue view)
                              │      alert_high_value_invoice_volume  (07:00 UTC) ──► email
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
| `guardrails.fx_rates` | View over Snowflake's free FX dataset: one USD rate per currency per day (weak currencies use 1 ÷ USD→X to keep precision) |
| `guardrails.count_invoices_over_usd_500k` | Data Metric Function: invoices > USD 500,000 at the invoice-date rate, plus unassessable ones (no rate / no amount) |
| `guardrails.high_value_invoices_for_review` | Review queue: every flagged invoice with USD amount, rate, rate date/age and reason |
| `guardrails.alert_high_value_invoice_volume` | Serverless alert: emails when the expectation (`VALUE <= 2`) is violated |
| `guardrails.task_auto_stop_guardrail` | One-off task, 2026-10-13 07:30 UTC: suspends the alert, clears the DMF schedule, suspends itself |

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
│   ├── 04_mcp/                                ← manual, run in Snowsight (not part of deploy.sh)
│   │   ├── 00_mcp_role_and_user.sql           ← least-privilege role + dedicated Claude user (placeholders only)
│   │   ├── 00b_fix_ap_invoice_agent.sql       ← rebuilds the registered agent spec (both tools, MCP-usable warehouse)
│   │   ├── 01_mcp_server.sql                  ← Snowflake-managed MCP server with 3 tools
│   │   ├── 02_oauth_security_integration.sql  ← Snowflake OAuth client for the claude.ai connector
│   │   ├── 03_optional_readonly_sql_server.sql ← optional separate read-only SQL MCP server (not deployed)
│   │   ├── 04_verify.sql                      ← read-only checks + builds the connector URL
│   │   └── 99_teardown.sql                    ← removes all MCP access
│   └── 05_guardrails/                         ← BR-004 high-value invoice guardrail (v0.3.0)
│       ├── 00_account_grants_and_email.sql    ← ACCOUNTADMIN, manual: grants + email integration (email placeholder only)
│       ├── 01_schema_and_fx_rates.sql         ← guardrails schema + FX view over the free ECB/BIS dataset
│       ├── 02_high_value_dmf.sql              ← Data Metric Function: > USD 500,000 at invoice-date FX, fail-safe
│       ├── 03_attach_to_silver.sql            ← daily 06:00 UTC schedule + expectation VALUE <= 2 on Silver
│       ├── 04_review_queue_view.sql           ← every flagged invoice, with USD amount, rate and reason
│       ├── 05_email_alert.sql                 ← email procedure + serverless alert (manual, --set email)
│       ├── 06_auto_stop_after_10_days.sql     ← one-off task: stop everything on 2026-10-13 07:30 UTC
│       ├── 90_test_fixture.sql                ← seeded boundary + edge cases (test schema)
│       ├── 91…97_check_*.sql / 95,96_test_*.sql ← pass/fail checks run by scripts/run_sql_checks.py
│       ├── 98_drop_test_objects.sql           ← removes the test schema
│       └── 99_teardown.sql                    ← optional full removal
│
├── cortex_agent/
│   └── run_agent.py                           ← REST client: runs the registered agent object, prints text + result tables
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
│   └── ap_invoice_agent.agent.yaml              ← live spec of the registered agent (matches sql/04_mcp/00b; orchestration model `auto`)
│
├── tests/
│   └── test_run_agent_parse.py                  ← offline tests for the agent client's response parser
│
├── config/
│   └── connection.example.toml                ← Snowflake connection template (copy → connection.toml)
│
├── scripts/
│   ├── deploy.sh                               ← applies all sql/ files in order via the Snowflake CLI
│   └── run_sql_checks.py                       ← runs a .sql check file via the PAT; exits 1 on any FAIL row
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
pip install -r requirements.txt        # agent client + eval harness (requests)
pip install -r requirements-dev.txt    # optional: adds snowflake-connector-python for direct SQL checks, and pytest
```
Install into the project's `.venv`, not your global Python. The connector pulls in many transitive packages, and a shared global environment makes dependency conflicts hard to attribute. `pip check` inside the venv should report no broken requirements.

#### 4. Configure your Snowflake connection
```bash
copy config\connection.example.toml config\connection.toml   # Windows
cp config/connection.example.toml config/connection.toml      # macOS/Linux
# then edit config/connection.toml with your account/user
```

#### 5. Run the guardrail account grants (once, as ACCOUNTADMIN)
In a Snowsight worksheet, run `sql/05_guardrails/00_account_grants_and_email.sql` one statement at a time, replacing `<your_verified_email>` **in the worksheet only**. It grants `SYSADMIN` what the BR-004 guardrail needs (create schemas in `coco`, run Data Metric Functions and read their results, run serverless alerts/tasks) and creates the `email_finance_alerts` integration. The guardrail's FX rates also need Snowflake's free **Snowflake Public Data** Marketplace listing installed as `SNOWFLAKE_PUBLIC_DATA_FREE`, with `GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_PUBLIC_DATA_FREE TO ROLE SYSADMIN`.

#### 6. Deploy the pipeline
```bash
bash scripts/deploy.sh
```
This applies, in order: warehouse/database/schema setup → the 4 bronze source tables (with sample data) → the 2 Silver Dynamic Tables → the semantic view → the Cortex Search service → the BR-004 guardrail (FX view, DMF, attachment to Silver, review queue).

Then turn on the alert and the 10-day auto-stop (the email address is substituted at run time and never written to a file):
```bash
python scripts/run_sql_checks.py sql/05_guardrails/05_email_alert.sql --set your_verified_email=<you@example.com>
python scripts/run_sql_checks.py sql/05_guardrails/06_auto_stop_after_10_days.sql
```

#### 7. Set your Snowflake REST API credentials
`run_agent.py` runs the registered agent object `COCO.AGENT.AP_INVOICE_AGENT` (created by `sql/04_mcp/00b_fix_ap_invoice_agent.sql`, the same agent the MCP server exposes) over the Cortex Agents REST API, authenticated with a Personal Access Token.
```bash
# PowerShell
$env:SNOWFLAKE_ACCOUNT = "<org>-<account>"     # e.g. from your Snowsight URL: app.snowflake.com/<org>/<account>/...
$env:SNOWFLAKE_PAT = "<your PAT>"              # generate via ALTER USER <you> ADD PROGRAMMATIC ACCESS TOKEN ...
```
Note: PATs require `PROGRAMMATIC_ACCESS_TOKEN` to be listed in your account's authentication policy, and a network policy must be attached to the user (Snowflake enforces this for PATs even with an unrestricted `0.0.0.0/0` policy) — see `ALTER AUTHENTICATION POLICY` / `ALTER USER ... SET NETWORK_POLICY` if token creation is rejected.

#### 8. Ask the agent a question
```bash
python cortex_agent/run_agent.py "Which vendors have the most overdue invoices?"
```
The agent runs its governed SQL itself on `WH_COCO_PIPELINE`; `run_agent.py` prints the answer text plus the result tables from the agent's final message.

#### 9. Run the evaluation harness
```bash
python eval/run_eval.py
```

#### 10. (Optional) Connect the agent to Claude via MCP
Run the `sql/04_mcp/` scripts in a Snowsight worksheet in order — `00` → `00b` → `01` → `02` → `04` (skip `03`). Fill the password/email placeholders in the worksheet only, never in the file. Then in claude.ai → Settings → Connectors → *Add custom connector*, paste the URL printed by `04_verify.sql` (`https://<account>.snowflakecomputing.com/api/v2/databases/COCO/schemas/MCP/mcp-servers/AP_INVOICE_MCP`) and the OAuth client ID/secret from `02`, then sign in as `claude_mcp_user`. `99_teardown.sql` removes everything.

---

## 🧪 Tests

No CI yet — see Roadmap. Offline unit tests cover the agent client's response parser (no Snowflake needed):

```bash
python -m pytest tests/      # 4 tests: text + tables, epoch-day and ISO dates, empty message
```

Two kinds of live checks run against the real account:

- **Agent evaluation** — `eval/run_eval.py` runs the 15-question golden set (`eval/golden_dataset.jsonl`) against the live agent and applies heuristic pass/fail checks per question (`eval/metrics.py`).
- **BR-004 guardrail checks** — SQL files in `sql/05_guardrails/` return rows of `CHECK_NAME, EXPECTED, ACTUAL, OUTCOME`; `scripts/run_sql_checks.py` runs a file through the PAT and exits 1 if any row is `FAIL`:

  ```bash
  python scripts/run_sql_checks.py sql/05_guardrails/90_test_fixture.sql          # seeds 6 boundary + 6 edge cases (test schema)
  python scripts/run_sql_checks.py sql/05_guardrails/91_check_fx_rates.sql        # FX values, precision, uniqueness (8 checks)
  python scripts/run_sql_checks.py sql/05_guardrails/92_check_dmf_counts.sql      # DMF: fixture 3, Silver 0, 5 edge cases (7 checks)
  python scripts/run_sql_checks.py sql/05_guardrails/93_check_review_rule.sql     # review-queue rule + real view (5 checks)
  python scripts/run_sql_checks.py sql/05_guardrails/94_check_expectation_status.sql --repeat 8 --interval 120  # scheduled results
  python scripts/run_sql_checks.py sql/05_guardrails/97_check_pipeline_unaffected.sql  # Silver, refresh, MCP role untouched
  ```
  `95_test_email_alert.sql` sends one real email (run it once, never with `--repeat`); `96_test_auto_stop.sql` proves the auto-stop task on test objects. `98_drop_test_objects.sql` removes the test schema afterwards.

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

**Evaluation harness** (`eval/run_eval.py` against the live agent):

| Category | 2026-07-16 (embedded spec, `llama3.1-70b`) | 2026-10-04 (registered agent, model `auto`) |
|---|---|---|
| Core (6 questions) | 6/6 | 6/6 |
| Rephrasings/variation (4 questions) | 4/4 | 4/4 |
| Edge cases (2 questions) | 2/2 | 2/2 |
| Deliberately ambiguous (2 questions) | 0/2 | 1/2 |
| Data validation (1 question) | 1/1 | 1/1 |
| **Total** | **13/15** | **14/15** |

On 2026-10-04 the client moved from an embedded spec pinned to `llama3.1-70b` (Snowflake legacy since 2026-08-12, end-of-life no sooner than 2026-10-14) to the registered agent object on Snowflake's recommended `auto` model. "Which vendors are problematic?" now passes: the agent explains that "problematic" isn't defined and grounds its answer in overdue exposure. "Show me recent invoices" still fails the keyword check even though the answer is reasonable (the 20 most recent invoices, latest 2025-06-01). That is a scorer gap, not an agent defect; see Known Limitations.

Sample query, run live on 2026-10-04 via `python cortex_agent/run_agent.py "Which vendors have the most overdue invoices?"` (excerpt):
```
This covers invoices conformed across the SAP, Oracle, Baan, and Workday source systems. Amounts are shown
in their original currency and are not FX-converted, so the EUR and USD totals are not directly comparable.

Top 10 Vendors by Number of Overdue Invoices
VENDOR_NAME, OVERDUE_INVOICE_COUNT, OVERDUE_AMOUNT, CURRENCY_CODE
Nordic Metals AB, 3, 88500.00, EUR
Summit Energy Corp, 3, 197600.00, USD
CloudScale Analytics, 3, 66000.00, USD
...
```

**MCP smoke test — 3/3 tools working from Claude** (2026-10-02, via the claude.ai connector):

| MCP tool | Test question | Result |
|---|---|---|
| `ap-invoice-search` | "hydraulic equipment" | Top hits "Hydraulic pumps Q1/Q2 order" |
| `ap-invoice-analyst` | "Which vendors have the highest total invoice amount?" | Correct `SEMANTIC_VIEW(... METRICS total_spend DIMENSIONS vendor_name)` SQL |
| `ap-invoice-agent` | "How many invoices per source system, and total spend for each?" | Executed SQL: SAP 15 / Oracle 15 / Baan 10 / Workday 10 = 50; spend kept per currency (BR-002) |

**BR-004 guardrail — every check passed live** (2026-10-03 → 2026-10-04, via `scripts/run_sql_checks.py`):

| Check file | What it proves | Result |
|---|---|---|
| `90_test_fixture.sql` | 6 boundary invoices (600,000 USD; exactly 500,000; EUR just over/under; GBP on a Sunday → Friday rate; unknown currency) + 6 edge-case rows seeded | 6 + 6 rows |
| `91_check_fx_rates.sql` | Known EUR/GBP rates, no GBP rate on a Sunday (so the fallback is exercised), full-precision JPY/COP via 1 ÷ USD→X, one rate per currency per day, no rate for the test currency `XTS` | 8/8 PASS |
| `92_check_dmf_counts.sql` | DMF counts fixture **3** (600K USD, EUR over, no-rate fail-safe) and real Silver **0**; stale rate, lowercase code, null amount, credit note, same id in two systems | 7/7 PASS |
| `93_check_review_rule.sql` | Review rule flags the same fixture invoices as the DMF, with correct EUR→USD amount, rate fields and the no-rate reason; the real view over Silver lists 0 invoices | 5/5 PASS |
| `94_check_expectation_status.sql` | Scheduled results: fixture expectation **violated** (value 3 > 2); Silver's first daily run (2026-10-04 06:00 UTC) **passing** | 3/3 PASS |
| `95_test_email_alert.sql` | Test alert on the fixture fired and the email arrived (*"BR-004: 3 high-value invoices (tolerance 2)"*) | Confirmed in inbox |
| `96_test_auto_stop.sql` | One-off task suspended the test alert, cleared the DMF schedule, then suspended itself | 3/3 PASS |
| `97_check_pipeline_unaffected.sql` | Silver still 50 rows with exactly one DMF association and a healthy refresh; the MCP role has no access to `guardrails` | 4/4 PASS |

A test Dynamic Table over the fixture also proved that DMF results on a Dynamic Table are found with `REF_ENTITY_DOMAIN = 'TABLE'`, which is the lookup the real alert uses on Silver. A mutation test (both fail-safes removed) turned the null-amount, lowercase-code and fixture-count checks red before the logic was restored. The test schema was then dropped (`98_drop_test_objects.sql`).

---

## ⚠️ Known Limitations

- Payment-terms formats differ per source (`NET30` vs `N30` vs `Net 30`) and are intentionally left unnormalized at Silver — an open decision per BR-005, deferred to a future Gold layer
- GL account codes are not cross-mapped across sources (BR-006) — a unified chart of accounts is a Phase 2 concern, not implemented here
- The source data has no paid/unpaid flag — "overdue" is approximated as `due_date < CURRENT_DATE()` — since the sample data is dated 2025, this approximation drifts further from reality the longer the demo sits unrefreshed. By 2026-10-03 it had fully drifted: the live agent counted all 50 invoices as overdue, so overdue-based answers no longer separate vendors meaningfully until the dates are refreshed or a paid flag is added
- `eval/metrics.py` checks are heuristic (keyword/shape-based), not semantic — a good answer can fail a check and vice versa; the failing "ambiguous" check in the results above is a scorer gap, not an agent defect
- No CI pipeline runs `eval/run_eval.py` automatically on change
- Snowsight's Agent Studio UI was unreliable for the registered agent during development (a save bug left it with one tool on the wrong warehouse), so the agent is defined in SQL (`sql/04_mcp/00b_fix_ap_invoice_agent.sql`) with a synced copy in `cortex_project/`. Both `run_agent.py` and the MCP server now run that one object
- The orchestration model is `auto`, so Snowflake can switch to a newer model without a code change. That protects the client from model retirement, but it also means answer quality can shift silently. Re-running the evaluation harness is how changes are caught
- The MCP connector runs as a dedicated `claude_mcp_user`, because Claude always requests the `session:role:all` OAuth scope and so uses the signed-in user's default role; Cortex usage through the connector is billed to the account like any other Cortex call
- **BR-004 FX rates are indicative, not Treasury's.** They come from Snowflake's free public dataset (ECB/BIS); `guardrails.fx_rates` is the single place to swap in Treasury's corporate rates (BR-002). The free tier's latest rate was **2026-07-03** as of 2026-10-03, so a newly dated invoice converts at an older rate — the review queue shows `rate_age_days`. The dataset rounds rates to 4 decimal places, so currencies worth less than 1 USD use 1 ÷ (USD→currency) instead
- **BR-004 tolerance N = 2 is a placeholder** pending Finance (Tom Walsh) confirmation, counted over the current Silver snapshot rather than per month. A historical baseline is on the Roadmap
- **Credit notes are not flagged:** BR-004 says `amount > 500,000`, so a −600,000 credit note passes. Invoices with no amount or no usable FX rate are flagged (fail-safe)
- **The guardrail runs for 10 days only** (2026-10-03 → 2026-10-13 07:30 UTC), then a one-off task suspends the alert and clears the DMF schedule to save trial credits. Every object stays; restart with `ALTER TABLE coco.silver.dt_silver_ap_invoices SET DATA_METRIC_SCHEDULE = 'USING CRON 0 6 * * * UTC'` and `ALTER ALERT coco.guardrails.alert_high_value_invoice_volume RESUME`
- **Changing a DMF schedule is not instant:** after switching Silver's schedule, Snowflake left it `STARTED_AND_PENDING_SCHEDULE_UPDATE` with no runs for 30+ minutes; detaching, setting the schedule, then re-attaching gave a clean `STARTED`

---

## 🔜 Roadmap

- [x] `v0.2.0` — Snowflake-managed MCP server exposing the agent, Analyst and Search to Claude (shipped 2026-10-02)
- [x] `v0.3.0` — BR-004 data-quality guardrail: invoices > USD 500K at invoice-date FX via a Data Metric Function, review queue, email alert (shipped 2026-10-04)
- `v0.4.0` — GitHub Actions workflow running `eval/run_eval.py` on every push
- `v0.5.0` — BR-004 historical-baseline tolerance (rolling average with seasonality) once there is invoice history, replacing the fixed N = 2
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
- **FX rates (BR-004 only)** — Snowflake's free **Snowflake Public Data** listing (`FX_RATES_TIMESERIES`, sourced from the ECB and BIS), used read-only to convert amounts to USD for the guardrail; the Silver data itself stays in its original currencies

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

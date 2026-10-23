# Deploy checklist

`scripts/deploy.py --apply` runs every **deploy** file in `sql/deploy_manifest.txt` as SYSADMIN.
Everything below needs ACCOUNTADMIN, a secret, or a one-time action, so it is run by hand in a
Snowsight worksheet (role picker top right). Fill `<placeholders>` **in the worksheet only**, never in the file.

## A. Before the first deploy (empty account)

| # | Role | File / action | Expected result |
|---|---|---|---|
| A1 | ACCOUNTADMIN | `00_setup/00_database_schema_warehouse.sql` (Run All) | warehouse `WH_COCO_PIPELINE`, database `COCO`, schemas bronze/silver/semantic/agent owned by SYSADMIN |
| A2 | ACCOUNTADMIN | `05_guardrails/00_account_grants_and_email.sql`, one statement at a time; `<your_verified_email>` | SYSADMIN can create schemas in COCO and run DMFs/alerts/tasks; integration `EMAIL_FINANCE_ALERTS` |
| A3 | ACCOUNTADMIN | Install the free **Snowflake Public Data** listing as `SNOWFLAKE_PUBLIC_DATA_FREE`, then `GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_PUBLIC_DATA_FREE TO ROLE SYSADMIN;` | `05_guardrails/01` can read FX rates |
| A4 | ACCOUNTADMIN | `04_mcp/00_mcp_role_and_user.sql`; password + email placeholders | role `MCP_CLAUDE_ROLE`, user `CLAUDE_MCP_USER` |
| A5 | ACCOUNTADMIN | `06_ci/00_ci_eval_role_and_user.sql` | role `CI_EVAL_ROLE`, SERVICE user `CI_EVAL_USER`, network policy |

## B. Deploy

| # | Who | Command | Expected result |
|---|---|---|---|
| B1 | you | `python scripts/deploy.py --plan` | every deploy file listed with its statement count; nothing executed |
| B2 | you | `python scripts/deploy.py --apply` | `== deploy complete` (on failure it prints the file + statement number; fix and re-run — every deploy file is re-runnable) |

## C. After every deploy

| # | Role | File / action | Expected result |
|---|---|---|---|
| C1 | ACCOUNTADMIN | `90_grants.sql` (Run All) | object grants for both roles restored (CREATE OR REPLACE drops them). Until this runs, every agent question from the MCP or CI role fails, because the agent uses `tool_not_accessible: reject` |
| C2 | you | `python scripts/run_sql_checks.py sql/91_check_grants.sql` | every row PASS |
| C3 | you | `python scripts/run_sql_checks.py sql/02_silver/90_check_reporting_date.sql` | every row PASS |
| C4 | you | `python scripts/run_sql_checks.py sql/07_agent_tools/91_check_invoice_totals.sql` and `…/92_check_review_status.sql` | every row PASS (12 + 6) |

## D. First deploy only

| # | Role | File / action | Expected result |
|---|---|---|---|
| D1 | SYSADMIN → SECURITYADMIN | `04_mcp/01_mcp_server.sql` | MCP server `COCO.MCP.AP_INVOICE_MCP` + its grants |
| D2 | ACCOUNTADMIN | `04_mcp/02_oauth_security_integration.sql` | OAuth client for the claude.ai connector (copy ID/secret once) |
| D3 | you | `python scripts/run_sql_checks.py sql/05_guardrails/05_email_alert.sql --set your_verified_email=<you@example.com>` | BR-004 email procedure + alert (optional) |
| D4 | ACCOUNTADMIN | `00_setup/01_github_git_integration.sql`; GitHub PAT placeholder | Snowsight Workspace git link (optional) |
| D5 | ACCOUNTADMIN | **CI token** — `ALTER USER ci_eval_user ADD PROGRAMMATIC ACCESS TOKEN ci_eval_pat_<yyyy_mm> ROLE_RESTRICTION = 'CI_EVAL_ROLE' DAYS_TO_EXPIRY = <days>;` then paste `token_secret` into GitHub secret `SNOWFLAKE_PAT` (shown once) | `SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER ci_eval_user` → ACTIVE |
| D6 | you | GitHub repo variables `SNOWFLAKE_USER=CI_EVAL_USER`, `LIVE_EVAL_ENABLED=true`; secret `SNOWFLAKE_ACCOUNT` | `gh secret list`, `gh variable list` |

Not part of a deploy: `05_guardrails/06_auto_stop_after_10_days.sql` (one-off v0.3.0 schedule, 2026-10-13),
`04_mcp/03_optional_readonly_sql_server.sql`, and the check/test files (`05_guardrails/9*`, `91_check_grants.sql`).
The BR-004 DMF is attached with its schedule **off**; re-enable with
`ALTER TABLE coco.silver.dt_silver_ap_invoices SET DATA_METRIC_SCHEDULE = 'USING CRON 0 6 * * * UTC';`.

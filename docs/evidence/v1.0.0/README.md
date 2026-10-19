# v1.0.0 evidence — live Snowflake account, 2026-10-19

Every file here was produced against the live trial account before it ends (2026-11-11), so the results stay checkable afterwards.

| File | What it proves | Run / date |
|---|---|---|
| `gate_summary.md` | The gated native evaluation on `main` passed: answer_correctness 0.91, logical_consistency 0.93 vs baseline 0.91 / 0.98 (19 questions) | [run 39189340822](https://github.com/deepan-mehta-analytics/snowflake-cortex-ai/actions/runs/39189340822), 2026-10-19 |
| `native_ci-f1e32077-39189340822.json` | Per-question judge scores of that run (raw CI artifact) | run 39189340822 |
| `baseline.json` | The approved baseline the gate compares against | [run 39183731867](https://github.com/deepan-mehta-analytics/snowflake-cortex-ai/actions/runs/39183731867), 2026-10-19 |
| `q11_totals_record.md` | The per-currency totals issue the judge found, the instruction fix, and its measured success rate | 5 graded runs, 2026-10-19 |
| `deploy_plan.out` | The re-runnable deploy (`scripts/deploy.py --plan`): every file and statement it applies, plus the manual checklist files | 2026-10-19 |
| `grants_after.out` | All 34 grant checks PASS after the live deploy + `sql/90_grants.sql` (`sql/91_check_grants.sql`) | 2026-10-19 |
| `reporting_date.out` | One as-of date (2025-06-30), 50 invoices, 44 overdue, rollup matches Silver (`sql/02_silver/90_check_reporting_date.sql`) | 2026-10-19 |
| `agent_spotcheck.out` | The live agent answers from the 2025-06-30 as-of date and ranks overdue vendors correctly | 2026-10-19 |

The deploy was verified as a re-run over the existing account; a deploy into an empty account has not been run.

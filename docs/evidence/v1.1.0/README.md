# v1.1.0 evidence — live Snowflake account, 2026-10-23

Every file here was produced against the live trial account before it ends (2026-11-11), so the
results stay checkable afterwards. Plain-language guide:
[How the amounts in an answer are checked](../../explainers/how_answer_amounts_are_checked.md).

## Found → Fixed → Proven (q11)

| | v1.0.0 (`main` gate, run 39189340822) | v1.1.0 Run 1 (branch) | v1.1.0 Run 2 (`main` gate) |
|---|---|---|---|
| USD total in the answer | 709,300.00 ✗ | 469,300.00 ✓ | 469,300.00 ✓ |
| q11 answer_correctness | 0.67 | **1.00** | **1.00** |
| q11 logical_consistency | 0.67 | 0.67 ¹ | 0.67 ¹ |
| Check B (expected totals in the answer) | — | all PASS | all PASS |

¹ In both v1.1.0 runs the judge's note says the totals, SQL and tool choice were correct and marks the
answer down for leaked planning narration (for example "Need a list of invoices; use semantic view") — a
separate, already-known issue, not the totals.

## Gated runs

| Run | What | answer_correctness | logical_consistency | Outcome |
|---|---|---|---|---|
| [39917534812](https://github.com/deepan-mehta-analytics/snowflake-cortex-ai/actions/runs/39917534812), branch `v1.1-totals` | Baseline, 21 questions | 0.95 | 0.95 | recorded as `eval/baseline.json`; vs v1.0.0 on the 19 shared questions ✅ PASS |
| [39918230293](https://github.com/deepan-mehta-analytics/snowflake-cortex-ai/actions/runs/39918230293), `main` | Gate vs the 21-question baseline | 0.97 | 0.95 | ✅ PASS; vs v1.0.0 (19 shared) ✅ PASS; 0 errors |

## Files

| File | What it proves | Run / date |
|---|---|---|
| `gate_summary_run1_branch.md` | Run 1 per-question scores, the v1.0.0 comparison (19 shared questions, PASS) and check B — regenerated offline from the run's artifact with `eval/native_eval.py --scores-file … --compare-baseline eval/baseline_v1_0_0.json` | run 39917534812 |
| `gate_summary_run2_main.md` | Run 2 (the `main` gate) the same way | run 39918230293 |
| `native_ci-*.json` | Raw CI artifacts: per-question judge scores, the agent's answer text for every question, and check B verdicts | both runs |
| `baseline.json` | The 21-question v1.1.0 baseline | run 39917534812 |
| `spot_checks.md` | The live spot checks: the single-cell failure found in round 1, its fix, and the four correct round-2 answers with the tool calls the agent made | 2026-10-23 |
| `check_c_demo.out` | Check C on the real live q11 tool output with the v1.0.0 wrong sentence: flagged, with the true sum 469,300.00 (labelled reconstruction — no live v1.1.0 spot-check answer was flagged) | 2026-10-23 |
| `procedure_checks.out` | `invoice_totals` 12/12 and `review_status` 6/6 SQL checks PASS against the answer keys (`sql/07_agent_tools/91…92`) | 2026-10-23 |
| `grants_after.out` | All 38 grant checks PASS after the deploy + `sql/90_grants.sql`, incl. USAGE on both procedures for the MCP and CI roles | 2026-10-23 |
| `deploy_plan.out` | The 17 deploy files and 61 statements `scripts/deploy.py` applies, agent spec after the procedures it names | 2026-10-23 |

## Cost

Metered on 2026-10-23 before the two gated runs reached the usage views: 1.29 credits (warehouse
0.66 incl. three deploys, Cortex Agents 0.63 for the spot checks) ≈ $4.40. The two gated runs are
added once `METERING_DAILY_HISTORY` shows them (it lags by hours); v1.0.0 measured about $8 per
19-question run.

The deploy was verified as a re-run over the existing account; a deploy into an empty account has not been run.

# q11 — per-currency totals: what the judge found and what changed

**Question (q11):** "Which invoices were overdue as of 30 April 2025?"
**Answer key:** 22 invoices — USD 14 totalling 469,300.00 · EUR 5 totalling 101,450.50 · GBP 3 totalling 30,600.00.

## Graded runs (native evaluation, LLM judge)

| Run | Agent instruction | q11 correctness / consistency | USD total in the answer |
|---|---|---|---|
| [39183731867](https://github.com/deepan-mehta-analytics/snowflake-cortex-ai/actions/runs/39183731867) (baseline, branch) | original | 0.67 / 0.67 | 679,700.00 ✗ |
| [39185143387](https://github.com/deepan-mehta-analytics/snowflake-cortex-ai/actions/runs/39185143387) (gate, branch) | original | 0.67 / 0.33 | 657,600.00 ✗ |
| [39186725823](https://github.com/deepan-mehta-analytics/snowflake-cortex-ai/actions/runs/39186725823) (gate, branch) | `1b89293` — totals in SQL | 1.00 / 1.00 | 469,300.00 ✓ |
| [39188322522](https://github.com/deepan-mehta-analytics/snowflake-cortex-ai/actions/runs/39188322522) (gate, branch) | `f1e3207` — amount totals in SQL, scoped | 1.00 / 1.00 | 469,300.00 ✓ |
| [39189340822](https://github.com/deepan-mehta-analytics/snowflake-cortex-ai/actions/runs/39189340822) (gate, `main`) | `f1e3207` | 0.67 / 0.67 | 709,300.00 ✗ |

Ungraded spot checks of the same question after each instruction change (3 of 3) all returned 469,300.00.

## What the judge saw

- **Every run:** the count (22), the date handling (measured against 30 April 2025, not the 2025-06-30 as-of date) and the EUR and GBP totals were correct.
- **Wrong runs:** the SQL returned the 22 invoice rows only; the agent then added the 14 USD amounts in its own answer text and got the sum wrong. The judge's note on the `main` run: *"NO second SQL query was run to compute these totals … The agent appears to have computed these totals manually."*

## What changed and what it means

- `1b89293` → `f1e3207`: the agent instruction now requires SUM / AVG with GROUP BY currency_code for any amount total, tells the agent to run one more query if a total is missing, and forbids adding amounts by hand (small count sums allowed).
- The instruction lowers the error rate but cannot guarantee it: the agent decides per answer whether to run the totals query. A guaranteed fix (totals returned by the data itself, e.g. a semantic-view verified query) is on the README Roadmap.
- The gate scores this as partial credit (0.67), so it shows in the results instead of passing silently.

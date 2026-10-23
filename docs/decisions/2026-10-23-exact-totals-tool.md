# Decision: exact totals come from a tested procedure, and every answer amount is checked

**Date:** 2026-10-23 · **Status:** accepted (v1.1.0) · **Owner:** Deepan Mehta
**Plain-language version:** [How the amounts in an answer are checked](../explainers/how_answer_amounts_are_checked.md)

## Context

The v1.0.0 evaluation caught a real defect. For q11 ("Which invoices were overdue as of 30 April
2025?") the agent found the right 22 invoices, then added the 14 USD amounts in its own answer text
instead of asking SQL for the total. Across five graded runs the USD total was 679,700.00,
657,600.00, 469,300.00, 469,300.00 and 709,300.00 — the right answer is 469,300.00. Record:
[`q11_totals_record.md`](../evidence/v1.0.0/q11_totals_record.md).

Three rounds of instruction changes (`1b89293` → `5368a0a` → `f1e3207`) lowered the error rate but
could not remove it. **The root cause is a choice the model makes per answer** — whether to run the
totals query — not a missing SQL path: the semantic view could always compute the total.

## Options considered

| Option | What it gives | Why not on its own |
|---|---|---|
| More prompt rules | Cheap | Already tried three times; still a per-answer choice |
| Semantic-view verified query for "overdue as of a date" | A canned, correct SQL answer for one question shape | Still chosen by the model; covers one phrasing; not unit-testable outside Snowflake |
| **Stored-procedure tool `invoice_totals` + output checks** | Tested code returns exact totals; deterministic checks read what the model actually wrote | Chosen — see below |

## Decision

1. **`coco.agent.invoice_totals`** (stored procedure, registered as a Cortex Agent `generic` tool)
   returns per-currency counts and totals, overdue or all, as of a date, optionally for one vendor.
   It is checked against the answer keys by `sql/07_agent_tools/91_check_invoice_totals.sql`.
2. **`coco.agent.review_status`** answers BR-004 finance-review questions from the existing review
   queue view (rule not forked), plus the largest invoices and their share of the USD 500,000 limit.
3. Because the model can still skip the tool, the answer is checked **after** it is written:
   - **Check B** (`eval/native_eval.py`, warn-only): the expected per-currency totals must appear in
     each eval answer that has one.
   - **Check C** (`cortex_agent/run_agent.py`): every amount in the answer must be a value a tool
     returned, or the exact per-currency sum of a returned amount column; anything else is flagged
     with the true sum of the rows when it can be computed.
4. `orchestration.tool_not_accessible: reject` — a role that lacks a procedure grant fails the run
   instead of the agent silently skipping the tool (the documented default is `accept`).

**Promise wording:** "Every amount in an answer either comes from a query result or is flagged."
An earlier draft said "comes from tested code"; that was dropped because check C also accepts totals
computed by the semantic view's generated SQL, and only `invoice_totals` is tested code.

## Consequences

- **Check C runs only in this repo's client.** Snowflake Intelligence, CoWork and the Claude MCP
  connector call the agent directly and never pass through `run_agent.py`. The tool and its
  instructions still apply there; the after-the-fact check does not.
- **The LLM judge still varies between runs**, so gated runs are reported as "N of N", never as a
  guarantee.
- **Fallback (decided in advance):** if `generic` procedure tools had not worked on this account,
  totals would have moved to a semantic-view verified query and `review_status` to a view added to
  the semantic view; checks B and C do not depend on the procedures.
- Two more objects need grants after every deploy (`sql/90_grants.sql`, checked by
  `sql/91_check_grants.sql`).

## Evidence

Filled in at release: [`docs/evidence/v1.1.0/`](../evidence/v1.1.0/).

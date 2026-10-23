# v1.1.0 live spot checks — 2026-10-23

Run through the Cortex Agents REST API (the same call `cortex_agent/run_agent.py` makes), each answer
then checked by check C. Raw final messages for q11 and q21 are kept as test fixtures in
`tests/fixtures/agent_stream/`.

## Round 1 — procedures returned a table (failed, then fixed)

The agent chose the new tools and passed their inputs by name, but every procedure call came back as
an error:

```
"error": "expected a single cell result set, got 3 rows and 6 columns", "execution_type": "procedure"
```

A Cortex Agent procedure tool must return one cell. On q08, q11 and q20 the agent fell back to the
semantic view's SQL, so the totals were still right and check C stayed quiet (the figures came from a
query). q21 had no fallback and gave a hedged non-answer; check C flagged the "USD 500,000.00" it
quoted, because that number came from the instructions, not from any query result.

Fix (`8278705`): both procedures return one VARIANT object holding their rows, and `review_status`
also returns `threshold_usd`, so a quoted limit is backed by data.

## Round 2 — after the fix

| Question | Tool call the agent made | Answer | Answer key | Check C |
|---|---|---|---|---|
| q08 "How much did we spend with Acme?" | `invoice_totals(scope=all, vendor_name=Acme)` | USD 40,700, 3 invoices, Acme Industrial Supply | USD 40,700.00, 3 invoices | quiet |
| q11 "Which invoices were overdue as of 30 April 2025?" | `invoice_totals(as_of_date=2025-04-30, scope=overdue)` + the invoice list from the semantic view | 22 invoices: USD 14 / 469,300.00, EUR 5 / 101,450.50, GBP 3 / 30,600.00 | same | quiet |
| q20 "What is the total overdue amount for Summit Energy Corp?" | `invoice_totals(scope=overdue, vendor_name=Summit Energy)` | USD 138,700, 2 invoices | USD 138,700.00, 2 invoices | quiet |
| q21 "Which invoices need finance review under BR-004?" | `review_status()` | none flagged; largest ORA-INV-50008 USD 125,000 (25%), INV-2025-0010 USD 92,000 (18.4%), ORA-INV-50009 USD 71,200 (14.2%) | same | quiet |

q08 and q20 took one tool call each in round 2, against four in round 1 (the failed call, a retry,
the semantic-context lookup and the SQL).

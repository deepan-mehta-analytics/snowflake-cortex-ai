# How the amounts in an answer are checked

*A plain-language guide to what happens to a number — such as "USD 469,300.00 overdue" — between
your question and the agent's answer, and why the project's promise is worded the way it is.*

> **The promise:** Every amount in an answer either comes from a query result or is flagged.

---

## The short version

The AP invoice agent is an AI assistant that answers questions about supplier invoices. AI models
are good at understanding questions and writing answers, but they are not reliable calculators: if
they add up a long list of numbers in their head, they sometimes get it wrong.

So this project does three things:

1. **It gives the agent a calculator it can trust.** A small, tested program in the database
   (called `invoice_totals`) adds up invoice amounts exactly, per currency.
2. **It checks the answers in testing.** Before a release, a set of test questions with known
   correct answers is run, and the totals in the agent's answers are compared with the known ones.
3. **It checks every answer as it arrives** (when you use this project's own command-line client):
   each amount in the answer is compared with the numbers the database actually returned. Anything
   that does not match is shown with a ⚠️ warning and, where possible, the correct figure.

---

## Why this was needed: a real mistake

The question *"Which invoices were overdue as of 30 April 2025?"* has a known answer: 22 invoices,
of which 14 are in US dollars and add up to **USD 469,300.00**.

In version 1.0.0 the agent found the right 22 invoices every time. But in some runs it then added
the 14 dollar amounts itself, in its own words, and got **USD 679,700.00**, **657,600.00** or
**709,300.00**. The project's automated testing caught this, and the result was published as a known
limitation rather than hidden.

Telling the AI more firmly to "let the database do the adding" helped, but did not make the problem
go away — the AI still decides, answer by answer, whether to follow that advice.

---

## What happens now, step by step

| Step | What happens | In plain words |
|---|---|---|
| 1. You ask | "Which invoices were overdue as of 30 April 2025?" | — |
| 2. The agent picks tools | It can search descriptions, write a database query, or call `invoice_totals` | Tools are small programs the AI is allowed to use |
| 3. The tools return data | The database sends back rows and, from `invoice_totals`, exact totals | This is the "query result" in the promise |
| 4. The agent writes the answer | It quotes the totals | The AI could still type a wrong number here |
| 5. Check C reads the answer | Every amount must be one the database returned, or the exact sum of returned rows | If not: ⚠️ plus the correct sum |

Example of a flagged answer:

```
By currency, the overdue totals are USD 709,300.00, EUR 101,450.50 and GBP 30,600.00.

⚠️ Amount check:
- USD 709,300.00 is not in any query result; the rows returned sum to USD 469,300.00
```

---

## The three layers of checking

- **A — scored test runs.** Before a release, 21 test questions are sent to the agent and another AI
  (a "judge") scores each answer against the known correct one. This shows how well the agent does
  overall, but it is a sample, and the judge's scores vary a little from run to run.
- **B — a free totals check on those test runs.** For test questions with a single total per
  currency, a simple program checks that the correct figures actually appear in the answer. It only
  warns; it never stops a release on its own.
- **C — a check on every answer** in this project's command-line client, as described above.

---

## Why the promise says "comes from a query result", not "comes from tested code"

An earlier draft said every amount "comes from tested code". That was not quite true. Check C also
accepts a total that the database calculated through the agent's ordinary query tool (for example a
total spend per vendor). That total is correct — the database did the adding — but it was not
produced by the one specially tested program, `invoice_totals`. The honest wording is therefore
"comes from a query result": the number was calculated by the database, not by the AI.

---

## What these checks cannot do

- **They do not stop the AI from writing a wrong number.** They make sure a wrong number does not
  reach you unnoticed.
- **Check C only works in this project's own client** (`cortex_agent/run_agent.py`). If you use the
  same agent through Snowflake's own chat interfaces (Snowflake Intelligence, CoWork) or through
  Claude's connector, the tested calculator is still there, but the after-the-fact check is not.
- **Amounts are never converted between currencies.** Dollars, euros and pounds are always reported
  separately, because adding them together without an exchange rate would give a meaningless number.
  (The only exception is the finance-review rule, which compares invoices with a USD 500,000 limit
  using the exchange rate on the invoice date.)

---

## Where to look for more detail

- Engineering decision record: [`docs/decisions/2026-10-23-exact-totals-tool.md`](../decisions/2026-10-23-exact-totals-tool.md)
- The original mistake, run by run: [`docs/evidence/v1.0.0/q11_totals_record.md`](../evidence/v1.0.0/q11_totals_record.md)
- Results for this version: [`docs/evidence/v1.1.0/`](../evidence/v1.1.0/) (added at release)

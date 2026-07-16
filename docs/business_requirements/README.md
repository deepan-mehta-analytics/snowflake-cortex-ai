# Business Requirements

These 3 CSVs are the finance/engineering requirements that drove the Silver
Dynamic Table design in `sql/02_silver/01_dt_silver_ap_invoices.sql`. They
are sourced verbatim from the reference workshop this project is built from
(see the root `README.md` Dataset section for attribution) and kept here for
traceability — every `BR-###` comment in the Silver SQL points back to a rule
defined in `sample_business_requirements_business_rules.csv`.

## Files

- **`sample_business_requirements_source_onboarding.csv`** — the requests to onboard Baan and Workday as new bronze sources: requester, priority, target go-live, and open items (e.g. Baan's on-prem extract timing, Workday's tenant/currency handling).
- **`sample_business_requirements_column_mapping.csv`** — field-by-field mapping from each new source's bronze columns to the common Silver schema, including transform notes (direct map, normalize, drop).
- **`sample_business_requirements_business_rules.csv`** — BR-001 through BR-010: the actual decisions implemented in the Silver Dynamic Table (status normalization, no currency conversion, Baan dedup logic, GL account handling, source system tagging, refresh timing, retention).

## Rule → implementation map

| Rule | Decision | Where it's implemented |
|---|---|---|
| BR-001 | Normalize all source statuses to `APPROVED`/`PENDING` | `CASE` expressions per source branch in the Silver DT |
| BR-002 | No currency conversion at Silver; store original transaction currency | `invoice_amount`/`currency_code` passed through unmodified |
| BR-003 | Baan nightly extract can re-send an invoice under a new ID; dedupe on `ban_invoice_ref`, keep latest | `QUALIFY ROW_NUMBER() OVER (PARTITION BY ban_invoice_ref ORDER BY ban_created DESC) = 1` |
| BR-005 | Payment terms formats differ per source (`NET30` vs `N30` vs `Net 30`) — left as-is at Silver, open decision for Gold | No transform applied; noted inline |
| BR-006 | No cross-source GL account mapping at Silver | `gl_account` passed through as the source's native code |
| BR-007 | Every Silver row carries a `source_system` literal | Hard-coded per `UNION ALL` branch |
| BR-008 | Drop system-specific columns at the bronze-to-silver boundary | Not selected into the Silver DT (still available in bronze if needed) |
| BR-009 | Sources refresh at different cadences; Silver should not force an artificial cadence | `TARGET_LAG = DOWNSTREAM` |
| BR-010 | Bronze retains full history; Silver/Gold are current-state | No retention logic needed — Dynamic Tables reflect current state by design |

BR-004 (amount-threshold data quality flagging) is intentionally **not** implemented in the Silver DT — the business rule specifies it as a Data Metric Function / guardrail concern, which is out of scope for this repo's current phase (see root `README.md` Roadmap).

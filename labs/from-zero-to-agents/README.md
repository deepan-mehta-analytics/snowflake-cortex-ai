# From Zero to Agents — Northstar Badge Lab 2 (run after CoCo Foundations)

Source page: https://www.snowflake.com/en/developers/guides/from-zero-to-agents/
Step-by-step quickstart: https://quickstarts.snowflake.com/guide/getting-started-with-snowflake-intelligence/index.html
(the quickstart domain itself still blocks automated fetch — 403 — but the
full step list below was pulled from the source page, which fetches fine,
and cross-checked term-for-term against its raw HTML)

Underlying repo (verified real): https://github.com/Snowflake-Labs/sfguide-getting-started-with-snowflake-intelligence

This lab does have a Northstar auto-grader, same as CoCo Foundations — it
lives on the quickstarts.snowflake.com platform itself (still blocked to
automated fetch here), not on the marketing overview page the step list
below was pulled from. Run it the same way as Lab 1: get the personalized
grader SQL from the platform once logged in, run it in a **scratch
worksheet only, never saved to disk** (it embeds real account/email PII —
same handling as Lab 1's grader).

This lab uses **Snowflake's own fictional retail/marketing dataset** — fully
separate from both the `coco` AP invoice pipeline and the `COCO_WORKSHOP`
CoCo Foundations lab. Its own database: `DASH_DB_SI`.

## Assets in this folder

- `setup.sql` — creates role `snowflake_intelligence_admin`, warehouse
  `dash_wh_si`, database `dash_db_si` (schema `retail`), database
  `snowflake_intelligence` (schema `agents`), loads `marketing_campaign_metrics`,
  `products`, `sales`, `social_media`, `support_cases` from public S3, creates
  a git integration to the real upstream repo above, pulls
  `marketing_campaigns.yaml` semantic model from it, and sets up an email
  notification integration + `send_email` procedure
- `marketing_data.csv` — appears to be a manual-upload alternative/supplement
  to the S3-loaded `marketing_campaign_metrics` table; confirm against the
  live guide before using — not yet cross-checked

## Steps

1. Run `setup.sql` in full via Workspaces (Run All), as `ACCOUNTADMIN` (it
   grants itself the privileges it needs via `snowflake_intelligence_admin`)
2. It ends with a self-check block that reports whether all 5 tables exist
   and are populated
3. **AI enrichment** — run in a worksheet against `dash_db_si.retail`:
   ```sql
   SELECT
       title,
       SNOWFLAKE.CORTEX.AI_SENTIMENT(transcript) AS sentiment_score,
       SNOWFLAKE.CORTEX.AI_CLASSIFY(transcript, ['Return', 'Quality', 'Shipping']) AS issue_category
   FROM support_cases;
   ```
4. **Dynamic Table** — continuously-refreshed join of marketing + support data:
   ```sql
   CREATE OR REPLACE DYNAMIC TABLE enriched_marketing_intelligence
   TARGET_LAG = '1 hours'
   WAREHOUSE = dash_wh_si
   AS
   SELECT m.campaign_name, m.clicks, s.product AS product_name,
          SNOWFLAKE.CORTEX.SENTIMENT(s.transcript) AS avg_sentiment
   FROM marketing_campaign_metrics m
   JOIN support_cases s ON m.category = s.product;
   ```
5. **Semantic view via Cortex Analyst Autopilot** (Snowsight UI: **AI & ML →
   Analyst → Create with Autopilot**):
   - Name `SEMANTIC_VIEW`, location `DASH_DB_SI.RETAIL` — Autopilot actually
     saved it as **`SEMANTIC_VIEW_AUTOPILOT`**; use that real name downstream
   - Select all 5 tables + the new dynamic table, all columns — the dynamic
     table must be explicitly added in this step, it is not auto-included
   - Set `MARKETING_CAMPAIGN_METRICS` primary key to `CATEGORY`
   - Add relationship `ENRICHED_MARKETING_INTELLIGENCE.PRODUCT_NAME` →
     `MARKETING_CAMPAIGN_METRICS.CATEGORY`, relationship type **Many-to-one**
     (many `ENRICHED_MARKETING_INTELLIGENCE` rows per `CATEGORY`)
   - If validation fails with "Insufficient privileges to operate on schema
     RETAIL", the Snowsight session's active role isn't
     `snowflake_intelligence_admin` (the owning role) — switch it via the
     role selector, same worksheet-role-context issue seen elsewhere in
     this project
6. **Cortex Search service** (Snowsight UI: **AI & ML → Search**):
   - Database/schema `DASH_DB_SI.RETAIL`, service name `campaign_search`
   - Search column `campaign_name`, all attributes/columns selected
   - Warehouse `DASH_WH_SI` for both querying and indexing, target lag `1 hour`
7. **Agent** (Snowsight UI: **AI & ML → Agents**):
   - Create `MarketingAgent` in `DASH_DB_SI.RETAIL`
   - Description: analyzes structured marketing metrics + unstructured
     customer feedback
   - Tools: Semantic View `SEMANTIC_VIEW_AUTOPILOT` (`DASH_WH_SI`, 60s
     timeout), Cortex Search `CAMPAIGN_SEARCH` (max 4 results), custom
     procedure `SEND_EMAIL()` (body/recipient/subject params)
8. **Validate** via **AI & ML → Snowflake CoWork** with sample questions:
   - "What are the top 5 campaigns by clicks?"
   - "Show me campaign performance metrics and product relationships"
   - "What is the relationship between campaign clicks and customer
     satisfaction by category?"
   - "What are the main customer complaints in support cases?"
   - Check the **Trace** panel to confirm correct tool selection
9. *(optional)* **Masking policy** to restrict `clicks` to admin roles:
   ```sql
   CREATE OR REPLACE MASKING POLICY mask_engagement_clicks AS (val number)
   RETURNS number ->
     CASE
       WHEN CURRENT_ROLE() IN ('SNOWFLAKE_INTELLIGENCE_ADMIN', 'ACCOUNTADMIN') THEN val
       ELSE 0
     END;

   ALTER TABLE marketing_campaign_metrics MODIFY COLUMN clicks SET MASKING POLICY mask_engagement_clicks;
   ```

## Status

**Complete** — auto-grader passed, all steps done against the live account:
`setup.sql` (all 5 tables created/populated), the AI enrichment query
(sentiment + classification over `support_cases`), the
`ENRICHED_MARKETING_INTELLIGENCE` Dynamic Table, the semantic view (saved as
`SEMANTIC_VIEW_AUTOPILOT`, not `SEMANTIC_VIEW`), the `campaign_search` Cortex
Search service, and `MarketingAgent` with all 3 tools correctly configured
(semantic view, Cortex Search, `SEND_EMAIL()` procedure). Validated against
all 4 sample questions in step 8, with the Trace panel confirming clean
single-pass tool execution. Run this lab *after* CoCo Foundations, per the
intended sequence — satisfied.

### Known limitations

- The `MarketingAgent`'s tool configuration initially had two real bugs
  (traced via `DESCRIBE AGENT`, not guessed): only 1 of the intended 3 tools
  was present, and the one present tool referenced a nonexistent warehouse
  (`DASH_WH` instead of the real `DASH_WH_SI`). Root cause: Snowsight's Agent
  Studio (a preview feature) silently failed to persist Tools-tab edits on
  Save/Publish at least twice. Fixed by issuing `CREATE OR REPLACE AGENT ...
  FROM SPECIFICATION` directly via SQL instead of the UI.
- The `ENRICHED_MARKETING_INTELLIGENCE` Dynamic Table (step 4's `JOIN
  support_cases s ON m.category = s.product`) always returns 0 rows against
  the quickstart's own sample data — `support_cases.product` values
  (`Cyclone Helmet`, `ThermoJacket Pro`, etc.) don't match either
  `marketing_campaign_metrics.category` (`Fitness Wear`) or
  `products.PRODUCT_NAME` (`Fitness Item 1`, etc.) under any join path. This
  is a vendor sample-data inconsistency, not fixable without fabricating a
  mapping — the agent correctly reports it can't answer clicks-vs-satisfaction
  questions rather than fabricating a result.
- `dash_wh_si` defaults to `warehouse_size='large'` in `setup.sql`; resized to
  `XSMALL` with `AUTO_SUSPEND = 60` after this lab burned meaningfully more
  credit than expected during agent testing/retries.

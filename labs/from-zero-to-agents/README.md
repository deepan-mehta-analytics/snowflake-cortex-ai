# From Zero to Agents — Northstar Badge Lab 2 (run after CoCo Foundations)

Source page: https://www.snowflake.com/en/developers/guides/from-zero-to-agents/
Step-by-step quickstart: https://quickstarts.snowflake.com/guide/getting-started-with-snowflake-intelligence/index.html
(blocked automated fetch — 403 — open it directly in your browser when you
reach this lab; the steps below cover only what's verified from `setup.sql`
itself, which is self-consistent and safe to run as-is)

Underlying repo (verified real): https://github.com/Snowflake-Labs/sfguide-getting-started-with-snowflake-intelligence

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
3. Open the quickstart link above in your browser for the remaining steps
   (Cortex Search service setup, agent creation, validation) — not yet
   transcribed here since the page blocks automated fetching

## Status

`setup.sql` and `marketing_data.csv` downloaded and partially verified
(setup.sql is internally consistent and self-referencing). Full step list
not yet confirmed — open the live quickstart guide before running anything
beyond `setup.sql`. Not yet run against the live account. Run this lab
*after* CoCo Foundations, per the intended sequence.

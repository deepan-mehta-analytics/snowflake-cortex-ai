# CoCo Foundations — Northstar Badge Lab 1 (run first)

Source (verified, fetched directly): https://github.com/hindcraig3/cortex-code-foundations

This is the **same reference workshop** this repo's AP invoice pipeline (`coco`
database, `sql/`, `cortex_agent/`, `eval/`) was originally grounded in — the
lab builds an equivalent pipeline from scratch under its own `COCO_WORKSHOP`
database, entirely separate from the `coco` database used elsewhere in this
repo. Do not point this lab at `coco` — it must use `COCO_WORKSHOP`.

This lab is driven **inside Snowsight's CoCo panel** (the blue star icon,
bottom-right corner) — not the local `cortex` CLI, no install required. Each
step below is a prompt you paste into that panel; I can't run it for you.

## Assets in this folder

- `00_snowday_setup.sql` — creates `COCO_WORKSHOP` database, `PIPELINE_LAB` +
  `SOURCE_DATA` schemas, `COCO_WORKSHOP_WH` warehouse, governance tags
- `00_sample_data.sql` — loads `BRONZE_SAP_AP_INVOICES`, `BRONZE_ORACLE_AP_INVOICES`,
  `BRONZE_BAAN_AP_INVOICES`, `BRONZE_WORKDAY_AP_INVOICES`, `AGENT_EVAL_SET` (15
  golden questions)
- `01_demo_reset.sql` — drops demo-created objects to reset between attempts
- `sample_business_requirements_*.csv` (3 files) — Demo 2's new-requirements PRD
- `dynamic-tables.zip` — CoCo skill required for Demo 1, downloaded from the
  repo's `assets/` folder

## Steps

**Setup (run once, via Projects → Workspaces → new SQL file → paste → Run All):**
1. Run `00_snowday_setup.sql`
2. Run `00_sample_data.sql`

**Demo 1 — Pipeline Builder** (builds `PIPELINE_LAB.SILVER_AP_INVOICES`):
1. In CoCo, ask it to list tables in `COCO_WORKSHOP.SOURCE_DATA` and identify
   which are relevant to an AP invoices Silver layer
2. Ask it to compare columns between `BRONZE_SAP_AP_INVOICES` and
   `BRONZE_ORACLE_AP_INVOICES`
3. Unzip `dynamic-tables.zip`, upload the unzipped **folder** via CoCo's `+`
   icon → "Upload skill folder(s)"; confirm with `/dynamic`
4. Turn on **Plan Mode**, prompt CoCo to create `SILVER_AP_INVOICES` in
   `COCO_WORKSHOP.PIPELINE_LAB` combining the SAP + Oracle bronze tables
5. Turn off Plan Mode, tell it to proceed and create a SQL file with the code;
   click **Keep All**
6. Ask CoCo to list its skills, inspect `dynamic-tables`, then invoke
   `/dynamic-table` against `SILVER_AP_INVOICES` for a TARGET_LAG
   recommendation + monitoring runbook
7. *(optional)* Ask for a proof query (record counts by `SOURCE_SYSTEM`)

**Demo 2 — Managing changing requirements** (adds Baan + Workday):
1. Upload the 3 `sample_business_requirements_*.csv` files to CoCo
2. Ask it to review them and summarize impact on the pipeline
3. Plan Mode on → ask for an implementation plan
4. Plan Mode off → tell it to proceed, update the SQL file, and return
   mapping/assumptions/validation queries; **Keep All**

**Demo 3 — Build an Agent (optional)**:
1. Ask CoCo to define the value/use case for an agent on `SILVER_AP_INVOICES`
2. Ask it to build a semantic view `SV_AP_ANALYTICS` over `SILVER_AP_INVOICES`;
   **Keep All**, then deploy + validate it
3. Ask CoCo to build a Cortex Agent on `SV_AP_ANALYTICS`; **Allow** when
   prompted to save/deploy
4. Ask CoCo to audit the semantic view for best practices

## Status

Complete. Demos 1–3 all run against the live account: `SILVER_AP_INVOICES`
Dynamic Table (SAP+Oracle, then all 4 sources with BR-001/BR-003), a
semantic view + Cortex Agent on top of it (quality score improved from 0/6
to fully passing after the best-practices audit fix), all correctly scoped
to `COCO_WORKSHOP` with the real `coco` database untouched. Auto-grader
passed: "Congratulations! You have successfully completed the Cortex Code
Foundations workshop!"

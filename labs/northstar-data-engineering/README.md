# Northstar Badge Lab — Data Engineering with Snowflake (Day 1, Lab 1)

Guide: https://www.snowflake.com/en/developers/guides/snowflake-northstar-data-engineering/
Companion repo (verified real via GitHub API, not WebFetch summary alone):
https://github.com/Snowflake-Labs/sfguide-snowflake-northstar-data-engineering

This is the first of Day 1's two labs in the Northstar Badge sequence — run
*before* the CoCo Foundations / From Zero to Agents labs (Day 2, already
complete), per the actual badge program order. Uses Snowflake's "Tasty
Bytes" food-truck sample dataset, fully separate from every other
database/dataset in this repo (`coco`, `COCO_WORKSHOP`, `DASH_DB_SI`).

**Scenario:** investigate why Tasty Bytes' Hamburg, Germany food truck sales
dropped to $0 for several days in February 2022, using the
Ingestion → Transformation → Delivery (I-T-D) framework.

## Assets in this folder

Downloaded verbatim from the verified companion repo:

- `assets/00_ingestion/copy_into.sql` — **exercise version**: creates the
  `tasty_bytes.public.s3load` stage (public S3 bucket, no credentials
  needed) and one example table (`country`); the actual `COPY INTO` is left
  blank for you to write
- `assets/00_ingestion/solution/solution_copy_into.sql` — the filled-in
  answer key for the exercise above
- `assets/00_ingestion/load_tasty_bytes.sql` — the **full data load script**:
  creates `raw_customer`/`harmonized`/`analytics` schemas, a `demo_build_wh`
  warehouse (**`XLARGE`** — bigger than the `large` size that caused Day 2's
  cost overrun, but this script `DROP WAREHOUSE`s it at the very end after
  loading, so exposure is bounded to load time only, not indefinite), 7 raw
  tables (`franchise`, `location`, `menu`, `truck`, `order_header`,
  `order_detail`, `customer_loyalty`), 2 harmonized + 2 analytics views, and
  `COPY INTO` for all 7 tables from the same public S3 stage
  (`s3://sfquickstarts/tasty-bytes-builder-education/`)
- `assets/01_transformation/hamburg_sales.sql` — exercise: explores Feb 2022
  Hamburg sales (starts with `country`/`city` filters left as `'#'`
  placeholders), joins in Marketplace weather data via
  `Pelmorex_Weather_Source_frostbyte.onpoint_id.history_day` +
  `postal_codes`, creates `tasty_bytes.harmonized.daily_weather_v`, then asks
  you to name+create a windspeed-tracking view (placeholder:
  `-- add name of view`, guide's suggested name is `windspeed_hamburg`, not
  yet independently confirmed beyond the placeholder context)
- `assets/01_transformation/udf.sql` — two scalar UDFs:
  `tasty_bytes.analytics.fahrenheit_to_celsius()`,
  `tasty_bytes.analytics.inch_to_millimeter()`
- `assets/01_transformation/updated_hamburg_sales.sql` — exercise: joins
  `daily_weather_v` + `orders_v`, applies both UDFs, and asks you to name+
  create the combined sales+weather view (placeholder: `-- add name of
  view`, guide's suggested name is `weather_hamburg`, same caveat as above)
- `assets/02_delivery/streamlit.py` — Streamlit-in-Snowflake app
  ("Weather and Sales Trends for Hamburg, Germany"), dual-axis Altair chart
  (sales vs. temperature/precipitation/wind speed); references the view from
  the previous step via a literal placeholder string
  (`"INSERT NAME OF VIEW HERE"`) that must be filled in with whatever name
  you gave `weather_hamburg` above

## Steps (from the guide, cross-checked against real asset content)

1. **Account setup** — free trial, Enterprise edition, AWS, US West (Oregon)
   (already have an active trial account from this project's earlier work)
2. **Weather data** — Snowsight → **Data Products → Marketplace** → search
   "pelmorex frostbyte" → get **"Pelmorex Weather Source: Frostbyte"** (live
   data share, no `COPY INTO`, no storage cost)
3. **Sales data from S3** — run `assets/00_ingestion/load_tasty_bytes.sql`
   (the full solution) or work through `copy_into.sql` as the fill-in-the-
   blank exercise first, then compare against `solution/solution_copy_into.sql`
4. **Transformation** — run `hamburg_sales.sql` to explore Feb 2022 Hamburg
   sales and confirm the zero-sales days, then join in weather data via the
   Marketplace share and create `daily_weather_v` + a named windspeed view
5. **UDFs + combined view** — run `udf.sql`, then `updated_hamburg_sales.sql`
   to apply both UDFs and create the final combined sales+weather view
6. **Delivery** — create a Streamlit-in-Snowflake app named
   `HAMBURG_GERMANY_TRENDS` in `TASTY_BYTES.HARMONIZED`, paste in
   `streamlit.py`, filling in the view-name placeholder

## Auto-grader

Not yet independently verified for this specific lab (the companion repo
has no grader script — same as every other lab in this project, since the
real grader is a personalized script obtained from the Northstar Streamlit
app after registration, never stored in any public repo). User has
confirmed an auto-grader exists for this lab; treat it the same as the
other 3 labs — scratch worksheet only, never saved to disk, once reached.

## Status

**Scaffolded only — not yet run against the live account.** Real content
verified via GitHub API + raw file fetch (not trusted from WebFetch
summarization alone — a WebFetch pass for the *other* Day 1 lab
(`create-declarative-data-pipelines-with-dynamic-tables`) fabricated an
entire step list against a wrong repo before this lesson was re-applied
here). Cost note carried over from Day 2: `demo_build_wh` is `XLARGE` but
self-drops at the end of `load_tasty_bytes.sql` — watch that the script
runs to completion so the drop actually executes.

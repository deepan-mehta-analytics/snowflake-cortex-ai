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

**Complete — auto-grader passed.** Real content
verified via GitHub API + raw file fetch (not trusted from WebFetch
summarization alone — a WebFetch pass for the *other* Day 1 lab
(`create-declarative-data-pipelines-with-dynamic-tables`) fabricated an
entire step list against a wrong repo before this lesson was re-applied
here).

- **Ingestion**: `load_tasty_bytes.sql` run live — all 7 tables loaded
  (`order_detail` 673,655,465 rows, `order_header` 248,201,269 rows,
  `customer_loyalty` 222,540, `location` 13,093, `truck` 450, `franchise`
  335, `menu` 100) in **51.7s total** script time; `demo_build_wh` (XLARGE)
  confirmed dropped afterward via `SHOW WAREHOUSES` — cost landed near
  Snowflake's 60-second minimum billing floor (~0.27 credits), well under
  the pre-run estimate, since Tasty Bytes' 454 well-partitioned S3 files
  parallelize very well on XLARGE.
- **Found and fixed a real dependency gap**: `hamburg_sales.sql`'s
  `daily_weather_v` view joins `tasty_bytes.raw_pos.country`, but that table
  is never created by `load_tasty_bytes.sql` — it only exists in the
  fill-in-the-blank exercise's answer key (`solution/solution_copy_into.sql`).
  The README originally treated `load_tasty_bytes.sql` and
  `copy_into.sql`/`solution_copy_into.sql` as alternative paths for the same
  step; they are not — both are required (the exercise's `country` table
  load, skipping its `CREATE OR REPLACE DATABASE`/`SCHEMA` statements since
  those would have wiped the already-loaded tables). `country` table loaded
  cleanly (30 rows).
- **Confirmed the scenario's actual root cause** via `hamburg_sales.sql`
  (placeholders filled: `country='Germany'`, `city='Hamburg'`,
  windspeed view named `windspeed_hamburg` per the guide): daily sales are
  exactly **$0.0000 for Feb 16–21, 2022**, and max wind speed spikes to
  **51.6–66.5 mph** across that exact window — every other February day
  runs 17–43 mph. Temperature that week (39–46°F) is unremarkable. Root
  cause: a windstorm shut the Hamburg truck down for 6 days.
- **Known limitation found in the vendor's own `updated_hamburg_sales.sql`**
  (kept as-downloaded, not silently patched, per this project's "download
  labs verbatim" convention — same call made for the From Zero to Agents
  lab's vendor Dynamic Table join bug): the combined `weather_hamburg` view
  joins `daily_weather_v` directly to `orders_v`. `daily_weather_v` has
  **100 rows per day for Hamburg** (one per matching postal code in the
  Pelmorex weather share), so the join fans out daily sales ×100 in that
  view's `daily_sales` column (e.g. Feb 1 shows $41.8M instead of the real
  ~$418K from `hamburg_sales.sql`'s own dedicated sales query). The $0-sales
  /high-wind date alignment is unaffected — only the absolute dollar
  magnitude in this one view is inflated. UDFs
  (`fahrenheit_to_celsius`, `inch_to_millimeter`) work correctly.
- Cost note carried over from Day 2: `demo_build_wh` is `XLARGE` but
  self-drops at the end of `load_tasty_bytes.sql` — confirmed working as
  designed this run.

- **Delivery**: Streamlit-in-Snowflake app `HAMBURG_GERMANY_TRENDS` deployed
  to `TASTY_BYTES.HARMONIZED` via SQL (`PUT` to an internal stage +
  `CREATE STREAMLIT ... MAIN_FILE = 'streamlit_app.py'`), not the Snowsight
  UI. View-name placeholder filled with `TASTY_BYTES.HARMONIZED.WEATHER_HAMBURG`.
  Note: the app's own code divides `DAILY_SALES` by 1,000,000 for a
  "$ millions" axis — that scaling only reads sensibly with the ×100-inflated
  figures from the join fan-out above (real ~$418K/day would show as a
  near-flat 0.4 line on that axis); not something to fix, just worth knowing
  when viewing the chart.

- **Auto-grader pre-verified (BWITD01–06)**: the real grader
  (`Data Ingestion, Transformation, and Delivery with Snowflake` in the
  Northstar auto-grader dropdown — the guide-page view was removed from that
  Streamlit app at some point, leaving only a bare dropdown selector)
  checks `STREAMLIT_TITLE`, not `STREAMLIT_NAME`, for the delivery step
  (BWITD06). `CREATE STREAMLIT ... MAIN_FILE = ...` via SQL sets the object
  name but leaves `STREAMLIT_TITLE` null — a real gap, not a grader flake.
  Fixed via `ALTER STREAMLIT tasty_bytes.harmonized.HAMBURG_GERMANY_TRENDS
  SET TITLE = 'HAMBURG_GERMANY_TRENDS'`. All 6 conditions
  (`INFORMATION_SCHEMA.DATABASES`/`raw_pos.country` row count/
  `INFORMATION_SCHEMA.VIEWS` ×2/`INFORMATION_SCHEMA.FUNCTIONS`/
  `INFORMATION_SCHEMA.STREAMLITS`) independently verified passing via direct
  SQL before the real grader (which also posts registration email/name to an
  external grading API) was run.

**Auto-grader passed** — "Congratulations! You have successfully completed
the Snowflake Northstar - Data Engineering workshop!" All 6 checks
(BWITD01–06) confirmed, matching the independent pre-verification above.

**This lab is complete.**

# Snowflake Northstar Badge Labs

Four labs across two days, each independently graded. Fully separate from
this repo's core AP-invoice pipeline (`sql/`, `cortex_agent/`, `eval/`) — no
shared databases, warehouses, or objects with the main project.

| Day | Lab | Folder | Status |
|---|---|---|---|
| 1 | Data Engineering with Snowflake | [`northstar-data-engineering/`](northstar-data-engineering/README.md) | Scaffolded, not yet run |
| 1 | Create Declarative Data Pipelines with Dynamic Tables | `declarative-dynamic-tables/` | Not yet scaffolded — real guide content not yet verified (see below) |
| 2 | CoCo Foundations | [`coco-foundations/`](coco-foundations/README.md) | **Complete** — auto-grader passed |
| 2 | From Zero to Agents | [`from-zero-to-agents/`](from-zero-to-agents/README.md) | **Complete** — auto-grader passed |

Despite the numbering above, Day 2's labs were completed first in this
project's timeline; Day 1's labs were only discovered afterward. Each lab's
own README documents its real, verified setup independent of this ordering.

## A note on verification discipline

Every lab in this repo is fetched and cross-checked against real sources
(GitHub API file trees, raw file content) before being written up — not
trusted from a single WebFetch summary. This has caught real problems
twice: a fabricated GitHub repo path for the From Zero to Agents lab, and an
entire fabricated step list for `declarative-dynamic-tables` (WebFetch
summarized a similarly-named but *different* repo/guide as if it were this
one). See each lab's own README for specifics.

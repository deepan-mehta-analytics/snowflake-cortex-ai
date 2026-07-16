# Dynamic Tables Reference

Reference documentation for Snowflake Dynamic Tables — creating, monitoring,
troubleshooting, optimizing, alerting, and migrating pipelines onto them.
Sourced from the `dynamic-tables` skill bundle distributed with the
[Cortex Code Foundations](https://github.com/hindcraig3/cortex-code-foundations)
workshop (see `docs/business_requirements/README.md` for this project's
overall attribution to that source).

**This is plain reference material, not an installed Claude Code skill** —
it's kept here so the design decisions in `sql/02_silver/` (`TARGET_LAG`,
refresh mode, the Baan dedup pattern) can be checked against documented
best practice without leaving the repo.

If you're using Snowflake's own Cortex CLI (`cortex`) rather than Claude
Code, you don't need this folder at all — recent Cortex CLI builds ship an
equivalent `dynamic-tables` skill bundled by default (check with
`cortex skill list`, under `[BUNDLED]`).

## Contents

| File | Covers |
|---|---|
| `SKILL.md` | Entry point: Dynamic Tables vs. Streams+Tasks decision tree, mandatory init steps, intent routing to the sub-skills below |
| `create/SKILL.md` | Creating new Dynamic Tables |
| `monitor/SKILL.md` | Health checks, refresh history, trend/drift analysis |
| `troubleshoot/SKILL.md` | Diagnosing failing or `UPSTREAM_FAILED` refreshes |
| `optimize/SKILL.md` | Improving refresh mode, decomposing large DTs |
| `dt-alerting/SKILL.md` | Setting up alerts on refresh failure |
| `permissions/SKILL.md` | Privilege/ownership troubleshooting |
| `task-to-dt/SKILL.md` | Migrating Streams+Tasks pipelines to Dynamic Tables |
| `custom-incrementalization/SKILL.md` | CI DTs — stream-static joins, append-only logs, stateful MERGE |
| `dbt-to-dt/SKILL.md` | Converting dbt `table` models to Dynamic Tables |
| `pipeline-diagnostics/SKILL.md` | Pipeline timelines, Gantt charts, root-cause tracing |
| `references/*.md` | Supporting reference: SQL syntax, monitoring functions, DT state/graph, incremental operators, masking policies, supported queries |

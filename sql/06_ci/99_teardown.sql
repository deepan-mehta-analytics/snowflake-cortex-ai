-- ══════════════════════════════════════════════════════════════════
-- 06_ci / 99 — Teardown (remove the CI identity and eval objects)
-- ══════════════════════════════════════════════════════════════════
-- Run when live eval is no longer needed (or before the trial ends).
-- Also set the GitHub variable LIVE_EVAL_ENABLED to false (or delete it)
-- and delete the SNOWFLAKE_PAT secret.

-- ── User, network policy, role ───────────────────────────────────
USE ROLE ACCOUNTADMIN;                                                -- created these in 00
DROP USER IF EXISTS ci_eval_user;                                     -- also revokes its PAT
DROP NETWORK POLICY IF EXISTS ci_eval_network_policy;                 -- no longer attached once the user is gone
DROP ROLE IF EXISTS ci_eval_role;                                     -- drops the role and all its grants

-- ── Evaluation objects ───────────────────────────────────────────
USE ROLE SYSADMIN;                                                    -- owner of coco.eval (06_ci/01)
DROP SCHEMA IF EXISTS coco.eval;                                      -- golden table, config stage, datasets

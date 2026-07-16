-- ── GitHub PAT → Snowflake Git integration ────────────────────
-- One-time, account-level setup that lets Snowflake pull this repo directly
-- (Snowflake Workspaces "From Git Repository", GIT REPOSITORY stages,
-- EXECUTE IMMEDIATE FROM @repo, snow CLI git commands, etc.).
--
-- SECURITY: replace <PASTE_YOUR_GITHUB_PAT_HERE> below only in an
-- interactive Snowsight worksheet, run it, then close the worksheet WITHOUT
-- saving — or save your filled-in copy as *.local.sql, which .gitignore
-- excludes. Never commit a version of this file with a real PAT in it; the
-- PAT is only meant to live inside the Snowflake SECRET object created here.
USE ROLE ACCOUNTADMIN;                                        -- CREATE INTEGRATION requires account-level privilege

-- ── Secret: GitHub Personal Access Token ─────────────────────
CREATE OR REPLACE SECRET coco.agent.sec_coco_github_pat       -- schema-scoped secret holding the GitHub credential
    TYPE = password                                           -- Snowflake secret type for username+token pairs
    USERNAME = 'deepan-mehta-analytics'                        -- GitHub account/org the PAT belongs to
    PASSWORD = '<PASTE_YOUR_GITHUB_PAT_HERE>'                   -- fill in only when running interactively; never commit
    COMMENT = 'GitHub PAT for deepan-mehta-analytics/snowflake-cortex-ai git integration';  -- documents intent

-- ── API integration: GitHub HTTPS git API ────────────────────
CREATE OR REPLACE API INTEGRATION api_int_coco_github          -- account-level object authorizing outbound git calls
    API_PROVIDER = git_https_api                                -- built-in provider type for git-over-HTTPS integrations
    API_ALLOWED_PREFIXES = ('https://github.com/deepan-mehta-analytics')  -- restrict to this GitHub org only
    ALLOWED_AUTHENTICATION_SECRETS = (coco.agent.sec_coco_github_pat)      -- only this secret may authenticate through it
    ENABLED = TRUE;                                              -- activate the integration immediately

-- ── Git repository object ─────────────────────────────────────
CREATE OR REPLACE GIT REPOSITORY coco.agent.git_repo_snowflake_cortex_ai  -- git-backed stage object for this repo
    API_INTEGRATION = api_int_coco_github                         -- reuse the integration created above
    GIT_CREDENTIALS = coco.agent.sec_coco_github_pat               -- reuse the secret created above
    ORIGIN = 'https://github.com/deepan-mehta-analytics/snowflake-cortex-ai.git';  -- HTTPS clone URL of this repo

-- ── Verify ──────────────────────────────────────────────────────
ALTER GIT REPOSITORY coco.agent.git_repo_snowflake_cortex_ai FETCH;  -- pull latest branches/tags from GitHub now
SHOW GIT BRANCHES IN GIT REPOSITORY coco.agent.git_repo_snowflake_cortex_ai;  -- confirm main branch is visible
LS @coco.agent.git_repo_snowflake_cortex_ai/branches/main;             -- confirm repo files are browsable as a stage

-- ── Grants (adjust principal names to your account) ────────────
GRANT USAGE ON INTEGRATION api_int_coco_github TO ROLE sysadmin;                        -- let sysadmin use the integration
GRANT READ ON GIT REPOSITORY coco.agent.git_repo_snowflake_cortex_ai TO ROLE sysadmin;  -- let sysadmin browse repo files

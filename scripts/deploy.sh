#!/usr/bin/env bash
# Thin wrapper: the deploy logic lives in scripts/deploy.py (PAT auth, manifest order, no Snowflake CLI).
set -euo pipefail                                              # exit on error, unset var, or failed pipe stage
cd "$(dirname "${BASH_SOURCE[0]}")/.."                         # run from the repo root
python scripts/deploy.py "${@:---plan}"                        # default to a dry run; pass --apply to execute

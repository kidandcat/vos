#!/usr/bin/env bash
# The lakefile version and the latest numbered changelog heading must match.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
lake_ver=$(sed -n 's/.*version := v!"\([0-9][0-9A-Za-z.+-]*\)".*/\1/p' lakefile.lean | head -1)
cl_ver=$(sed -n 's/^## \[\([0-9][0-9A-Za-z.+-]*\)\].*/\1/p' CHANGELOG.md | head -1)
if [ -z "$lake_ver" ]; then
  echo "no version := v!\"...\" in lakefile.lean" >&2
  exit 1
fi
if [ -z "$cl_ver" ]; then
  echo "no ## [X.Y.Z] heading in CHANGELOG.md" >&2
  exit 1
fi
if [ "$lake_ver" != "$cl_ver" ]; then
  echo "lakefile version $lake_ver != changelog $cl_ver" >&2
  exit 1
fi
echo "version ok ($lake_ver)"

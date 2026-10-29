#!/usr/bin/env bash
# Fail if a printed theorem depends on sorryAx or on an axiom other than
# propext, Classical.choice, and Quot.sound.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if grep -R -n -E --include='*.lean' \
    '(^|[^A-Za-z])sorry([^A-Za-z]|$)|(^|[^A-Za-z])admit([^A-Za-z]|$)' \
    Vos Tests; then
  echo "sorry or admit in Vos or Tests" >&2
  exit 1
fi
OUT=$(lake env lean Tests/PrintAxioms.lean 2>&1) || {
  echo "$OUT" >&2
  exit 1
}
echo "$OUT"
OUT="$OUT" python3 - <<'PY'
import os, re, sys
text = os.environ["OUT"]
if "error:" in text:
    sys.exit("lean reported an error")
reports = re.findall(r"depends on axioms: \[([^\]]*)\]", text)
none_ax = len(re.findall(r"does not depend on any axioms", text))
expected = 62
if len(reports) + none_ax != expected:
    sys.exit(f"expected {expected} axiom reports, got {len(reports)} lists and {none_ax} empty")
allowed = {"propext", "Classical.choice", "Quot.sound"}
for group in reports:
    for name in (n.strip() for n in group.split(",")):
        if not name:
            continue
        if name == "sorryAx" or name not in allowed:
            sys.exit(f"axiom not allowed: {name}")
print(f"axioms ok ({len(reports) + none_ax} theorems)")
PY

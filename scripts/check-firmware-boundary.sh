#!/usr/bin/env bash
# The core is standalone. VM and AI-agent sandboxing live under Vos/Sandbox
# and Vos/Agent. Nothing else in Vos/ may import them, and a firmware bundle
# may not compile them.
#
#   scripts/check-firmware-boundary.sh
#   scripts/check-firmware-boundary.sh .lake/c3/bundle
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
python3 - "$ROOT" "$@" <<'PY'
import os, pathlib, sys
root = pathlib.Path(sys.argv[1])
bundles = [pathlib.Path(p) for p in sys.argv[2:]]
forbidden_prefixes = ("Vos.Sandbox", "Vos.Agent")
vos = root / "Vos"
sandbox = vos / "Sandbox"
if not any(sandbox.glob("*.lean")):
    sys.exit("Vos/Sandbox has no Lean file; the boundary check would be vacuous")

def module_name(path: pathlib.Path) -> str:
    rel = path.relative_to(vos).with_suffix("")
    return "Vos." + ".".join(rel.parts)

def is_forbidden(mod: str) -> bool:
    return any(mod == p or mod.startswith(p + ".") for p in forbidden_prefixes)

def read_imports(path: pathlib.Path):
    mods = []
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith("import "):
            mods.append(s.split()[1])
    return mods

imports = {}
for path in vos.rglob("*.lean"):
    imports[module_name(path)] = read_imports(path)
# The library root. Lake builds what this file imports. It is not under Vos/.
imports["Vos"] = read_imports(root / "Vos.lean")

def closure(start: str):
    seen, stack = [], [start]
    while stack:
        m = stack.pop()
        if m in seen:
            continue
        seen.append(m)
        stack.extend(imports.get(m, ()))
    return seen

failed = False
for mod, deps in sorted(imports.items()):
    if is_forbidden(mod):
        continue
    hit = [m for m in closure(mod) if is_forbidden(m)]
    if hit:
        failed = True
        print(f"{mod} reaches {', '.join(hit)}", file=sys.stderr)

# Firmware trees that exist today, plus the bare-metal ones when they appear.
trees = [
    root / "target" / "idf",
    root / "target" / "esp32c3",
    root / "target" / "esp32s3",
    root / "target" / "rp2040",
    root / "target" / "rp2350",
]
needles = ("Vos.Sandbox", "Vos/Sandbox", "Vos.Agent", "Vos/Agent")
for tree in trees:
    if not tree.is_dir():
        continue
    for path in tree.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix not in {".c", ".h", ".lean", ".cmake", ".txt"}:
            continue
        if "build" in path.parts:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for needle in needles:
            if needle in text:
                failed = True
                print(f"{path.relative_to(root)} contains {needle}", file=sys.stderr)

for bundle in bundles:
    src = bundle / "src"
    if not src.is_dir():
        sys.exit(f"bundle sources missing: {src}")
    for path in src.iterdir():
        if any(part in path.name for part in ("Sandbox", "Agent")):
            failed = True
            print(f"bundle contains {path.name}", file=sys.stderr)

if failed:
    sys.exit("firmware boundary failed")
print("firmware boundary ok")
PY

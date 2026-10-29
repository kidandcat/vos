#!/usr/bin/env bash
# The core is standalone. VM and AI-agent sandboxing live under Vos/Sandbox
# and Vos/Agent. Nothing else in Vos/ may import them. A firmware bundle is
# scanned for those names in C sources and for Vos_Sandbox / Vos_Agent in
# the symbol table (nm), not only in file names.
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
    root / "target" / "rv32-virt",
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

# Lean C spells Vos.Sandbox as Vos_Sandbox (lp_vos_Vos_Sandbox_..., l_Vos_Sandbox_...).
symbol_needles = ("Vos_Sandbox", "Vos_Agent", "Vos.Sandbox", "Vos.Agent")

def scan_text(label: str, text: str):
    global failed
    for needle in symbol_needles:
        if needle in text:
            failed = True
            print(f"{label} contains symbol {needle}", file=sys.stderr)
            return

def scan_binary(path: pathlib.Path):
    global failed
    import subprocess
    r = subprocess.run(["nm", "-A", str(path)], capture_output=True, text=True)
    blob = r.stdout + r.stderr
    if r.returncode != 0:
        failed = True
        err = r.stderr.strip() or r.stdout.strip()
        print(f"nm failed on {path}: {err}", file=sys.stderr)
        return
    for needle in ("Vos_Sandbox", "Vos_Agent"):
        if needle in blob:
            failed = True
            print(f"{path} defines a symbol containing {needle}", file=sys.stderr)

for bundle in bundles:
    if bundle.is_file() and bundle.suffix in {".elf", ".o", ".a"}:
        scan_binary(bundle)
        continue
    src = bundle / "src"
    if not src.is_dir():
        sys.exit(f"bundle sources missing: {src}")
    for path in src.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix in {".c", ".h", ".cpp", ".S", ".s"}:
            scan_text(str(path), path.read_text(encoding="utf-8", errors="replace"))
        elif path.suffix in {".o", ".elf", ".a"}:
            scan_binary(path)

if failed:
    sys.exit("firmware boundary failed")
print("firmware boundary ok")
PY

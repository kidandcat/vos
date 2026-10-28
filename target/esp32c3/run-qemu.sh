#!/usr/bin/env bash
# Build the C3 demo and boot it under Espressif QEMU (machine esp32c3).
# Checks the serial log for the three demo lines, in order.
#
# Requires: elan (Lean 4.35.0), ESP-IDF v5.4.x on IDF_PATH, qemu-system-riscv32
# with the esp32c3 machine, and libslirp. See target/esp32c3/setup-tools.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
IDF_PATH=${IDF_PATH:-"$HOME/esp/esp-idf"}
QEMU=${QEMU:-"$HOME/esp/qemu/qemu/bin/qemu-system-riscv32"}
LOG=${LOG:-"$ROOT/.lake/c3/qemu.log"}

if [ ! -x "$QEMU" ]; then
  echo "qemu not found at $QEMU" >&2
  exit 1
fi
if [ ! -f "$IDF_PATH/export.sh" ]; then
  echo "ESP-IDF not found at $IDF_PATH" >&2
  exit 1
fi
( cd "$ROOT/target/c3" && sha256sum -c SHA256SUMS )

# shellcheck disable=SC1091
source "$HOME/.elan/env"
lean --version

mkdir -p "$ROOT/.lake/c3/init-c" "$ROOT/.lake/c3/extra-c"
lake build Vos.Target.C3Demo

python3 "$ROOT/target/c3/bundle.py" \
  --lean-prefix "$(lean --print-prefix)" \
  --ir "$ROOT/.lake/build/ir" \
  --init-c "$ROOT/.lake/c3/init-c" \
  --extra-c "$ROOT/.lake/c3/extra-c" \
  --out "$ROOT/.lake/c3/bundle"

echo "---- host bundle ----"
"$ROOT/.lake/c3/bundle/vos-c3-host"

# shellcheck disable=SC1091
source "$IDF_PATH/export.sh"
export VOS_BUNDLE="$ROOT/.lake/c3/bundle"
cd "$ROOT/target/esp32c3"
idf.py set-target esp32c3
idf.py build

cd build
esptool.py --chip esp32c3 merge_bin --fill-flash-size 4MB -o flash_image.bin @flash_args
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
set +e
timeout 120 "$QEMU" -nographic -icount 3 -machine esp32c3 \
  -drive "file=flash_image.bin,if=mtd,format=raw" >"$LOG" 2>&1 &
qpid=$!
set -e
ok=0
for _ in $(seq 1 110); do
  if grep -q "vos c3: demo ok" "$LOG"; then
    ok=1
    break
  fi
  if grep -q "vos c3: fail" "$LOG" || grep -q "vos c3: panic fatal" "$LOG"; then
    echo "demo failed; log follows" >&2
    cat "$LOG" >&2
    kill "$qpid" 2>/dev/null || true
    wait "$qpid" 2>/dev/null || true
    exit 1
  fi
  if ! kill -0 "$qpid" 2>/dev/null; then
    break
  fi
  sleep 1
done
kill "$qpid" 2>/dev/null || true
wait "$qpid" 2>/dev/null || true

python3 - "$LOG" <<'PY'
import sys
text = open(sys.argv[1], errors="replace").read()
keys = ["vos c3: sent 41", "vos c3: timer not due", "vos c3: demo ok"]
pos = []
for k in keys:
    i = text.find(k)
    if i < 0:
        sys.exit(f"missing {k!r}")
    pos.append(i)
if not (pos[0] < pos[1] < pos[2]):
    sys.exit(f"lines out of order: {pos}")
if "vos c3: fail" in text or "vos c3: panic fatal" in text:
    sys.exit("fail or fatal panic in the log")
print("qemu esp32c3: demo ok")
PY

#!/usr/bin/env bash
# Build one chip image and boot it under Espressif QEMU.
# Called by target/esp32c3/run-qemu.sh and target/esp32s3/run-qemu.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
: "${VOS_CHIP:?}" "${VOS_MACHINE:?}" "${VOS_QEMU:?}" "${VOS_PROJECT:?}" "${VOS_TAG:?}" "${VOS_ELF:?}"
IDF_PATH=${IDF_PATH:-"$HOME/esp/esp-idf"}
LOG=${LOG:-"$ROOT/.lake/c3/qemu-${VOS_TAG}.log"}

if [ ! -x "$VOS_QEMU" ]; then
  echo "qemu not found at $VOS_QEMU" >&2
  exit 1
fi
if [ ! -f "$IDF_PATH/export.sh" ]; then
  echo "ESP-IDF not found at $IDF_PATH" >&2
  exit 1
fi
if ! command -v cmake >/dev/null || ! command -v ninja >/dev/null; then
  echo "cmake and ninja must be on PATH. Run target/esp32c3/setup-tools.sh." >&2
  exit 1
fi
( cd "$ROOT/target/c3" && sha256sum -c SHA256SUMS )

# shellcheck disable=SC1091
source "$HOME/.elan/env"
lean --version

mkdir -p "$ROOT/.lake/c3/init-c" "$ROOT/.lake/c3/extra-c"
lake build Vos.Target.C3Demo

if [ ! -s "$ROOT/.lake/c3/init-c/.complete" ]; then
  echo "== generating C for Lean's Init (once per toolchain)"
  bash "$ROOT/target/c3/gen_init_c.sh" "$(lean --print-prefix)" "$ROOT/.lake/c3/init-c"
  echo ok > "$ROOT/.lake/c3/init-c/.complete"
fi

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
if ! command -v cmake >/dev/null || ! command -v ninja >/dev/null; then
  echo "export.sh did not leave cmake and ninja on PATH." >&2
  exit 1
fi
export VOS_BUNDLE="$ROOT/.lake/c3/bundle"
cd "$VOS_PROJECT"
# A sdkconfig left from another chip would ignore sdkconfig.defaults.
if [ -f sdkconfig ] && ! grep -q "CONFIG_IDF_TARGET=\"${VOS_CHIP}\"" sdkconfig; then
  rm -f sdkconfig sdkconfig.old
fi
idf.py set-target "$VOS_CHIP"
idf.py build
echo "---- ${VOS_ELF} ----"
if [ -n "${VOS_SIZE_PREFIX:-}" ] && command -v "${VOS_SIZE_PREFIX}size" >/dev/null; then
  "${VOS_SIZE_PREFIX}size" -d "build/${VOS_ELF}.elf"
fi
idf.py size
wc -c "build/${VOS_ELF}.bin"

cd build
esptool.py --chip "$VOS_CHIP" merge_bin --fill-flash-size 4MB -o flash_image.bin @flash_args
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
set +e
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
timeout 120 "$VOS_QEMU" -nographic -icount 3 -machine "$VOS_MACHINE" \
  -drive "file=flash_image.bin,if=mtd,format=raw" >"$LOG" 2>&1 &
qpid=$!
set -e
for _ in $(seq 1 110); do
  if grep -q "vos ${VOS_TAG}: demo ok" "$LOG"; then
    break
  fi
  if grep -q "vos ${VOS_TAG}: fail" "$LOG" || grep -q "vos ${VOS_TAG}: panic fatal" "$LOG" ||
    grep -q "vos ${VOS_TAG}: hal fail" "$LOG"; then
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

cp "$LOG" "$VOS_PROJECT/build/qemu-serial.log"
if ! python3 - "$LOG" "$VOS_TAG" <<'PY'
import sys
text = open(sys.argv[1], errors="replace").read()
tag = sys.argv[2]
keys = [
    f"vos {tag}: hal uart ok",
    f"vos {tag}: hal nvs ok",
    f"vos {tag}: hal gpio ok" if f"vos {tag}: hal gpio ok" in text else f"vos {tag}: hal gpio level unread",
    f"vos {tag}: hal spi stub",
    f"vos {tag}: hal i2c stub",
    f"vos {tag}: hal radio stub",
    f"vos {tag}: sent 41",
    f"vos {tag}: timer not due",
    f"vos {tag}: demo ok",
]
pos = []
for k in keys:
    i = text.find(k)
    if i < 0:
        sys.exit(f"missing {k!r}")
    pos.append(i)
# The three demo lines stay in order. The hook lines are printed first.
if not (pos[-3] < pos[-2] < pos[-1]):
    sys.exit(f"demo lines out of order: {pos[-3:]}")
if f"vos {tag}: fail" in text or f"vos {tag}: panic fatal" in text or f"vos {tag}: hal fail" in text:
    sys.exit("fail or fatal panic in the log")
print(f"qemu {tag}: demo ok")
PY
then
  echo "guest log follows" >&2
  cat "$LOG" >&2
  exit 1
fi

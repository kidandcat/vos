#!/usr/bin/env bash
# Boot the generic RV32 image on QEMU virt and check the serial log.
# This is not an RP2350 boot.
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v riscv64-unknown-elf-gcc >/dev/null; then
  echo "riscv64-unknown-elf-gcc is not on PATH (package gcc-riscv64-unknown-elf)" >&2
  exit 1
fi
if ! command -v qemu-system-riscv32 >/dev/null; then
  echo "qemu-system-riscv32 is not on PATH (package qemu-system-misc)" >&2
  exit 1
fi
make clean all RV32_CC=riscv64-unknown-elf-gcc
LOG=/tmp/vos-rv32-virt.log
: > "$LOG"
set +e
timeout 20 qemu-system-riscv32 -machine virt -nographic -bios none \
  -kernel vos-rv32.elf -serial mon:stdio >"$LOG" 2>&1 &
qpid=$!
set -e
for _ in $(seq 1 15); do
  if grep -q "vos rv32: virt ok" "$LOG"; then
    break
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
keys = ["vos rv32: boot", "vos rv32: tick", "vos rv32: virt ok"]
pos = []
for k in keys:
    i = text.find(k)
    if i < 0:
        sys.exit("missing " + repr(k) + "\n" + text)
    pos.append(i)
ticks = text.count("vos rv32: tick")
if ticks < 3:
    sys.exit(f"expected 3 tick lines, saw {ticks}\n" + text)
if not (pos[0] < pos[1] < text.rfind("vos rv32: virt ok")):
    sys.exit("lines out of order\n" + text)
print("qemu virt rv32: ok")
PY

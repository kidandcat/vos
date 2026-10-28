#!/usr/bin/env bash
# Build the C3 demo and boot it under Espressif QEMU (machine esp32c3).
# Checks the serial log for the hook lines and the three demo lines.
#
# Requires: elan (Lean 4.35.0), ESP-IDF v5.4.x, cmake, ninja, and
# qemu-system-riscv32. See target/esp32c3/setup-tools.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
exec env \
  VOS_CHIP=esp32c3 \
  VOS_MACHINE=esp32c3 \
  VOS_QEMU="$HOME/esp/qemu/qemu/bin/qemu-system-riscv32" \
  VOS_PROJECT="$ROOT/target/esp32c3" \
  VOS_TAG=c3 \
  VOS_ELF=vos_c3 \
  VOS_SIZE_PREFIX="${VOS_SIZE_PREFIX:-riscv32-esp-elf-}" \
  bash "$ROOT/target/esp/run-qemu.sh"

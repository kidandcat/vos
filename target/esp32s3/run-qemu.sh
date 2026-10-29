#!/usr/bin/env bash
# Build the S3 demo and boot it under Espressif QEMU (machine esp32s3).
# Same demo and the same hook checks as the C3 script, on the Xtensa binary.
#
# Requires: elan (Lean 4.35.0), ESP-IDF v5.4.x, cmake, ninja, and
# qemu-system-xtensa. See target/esp32c3/setup-tools.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/target/esp/ensure-path.sh"
ensure_vos_build_tools
exec env \
  VOS_CHIP=esp32s3 \
  VOS_MACHINE=esp32s3 \
  VOS_QEMU="${VOS_QEMU:-$HOME/esp/qemu/qemu/bin/qemu-system-xtensa}" \
  VOS_PROJECT="$ROOT/target/esp32s3" \
  VOS_TAG=s3 \
  VOS_ELF=vos_s3 \
  VOS_SIZE_PREFIX="${VOS_SIZE_PREFIX:-xtensa-esp-elf-}" \
  bash "$ROOT/target/esp/run-qemu.sh"

#!/usr/bin/env bash
# Install ESP-IDF v5.4.4 (esp32c3) and Espressif's riscv32 QEMU into $HOME.
# Safe to re-run. Does not use apt except for libslirp, which QEMU needs.
set -euo pipefail
IDF_TAG=v5.4.4
QEMU_TAG=esp-develop-9.2.2-20260417
QEMU_TAR=qemu-riscv32-softmmu-esp_develop_9.2.2_20260417-x86_64-linux-gnu.tar.xz
QEMU_URL=https://github.com/espressif/qemu/releases/download/${QEMU_TAG}/${QEMU_TAR}

mkdir -p "$HOME/esp"
if [ ! -f "$HOME/esp/esp-idf/export.sh" ]; then
  git clone --depth 1 -b "$IDF_TAG" https://github.com/espressif/esp-idf.git "$HOME/esp/esp-idf"
fi
cd "$HOME/esp/esp-idf"
git submodule update --init --recursive --depth 1
./install.sh esp32c3

if [ ! -x "$HOME/esp/qemu/qemu/bin/qemu-system-riscv32" ]; then
  mkdir -p "$HOME/esp/qemu"
  curl -fsSL -o /tmp/qemu-esp.tar.xz "$QEMU_URL"
  tar -C "$HOME/esp/qemu" -xJf /tmp/qemu-esp.tar.xz
fi

if command -v sudo >/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq libslirp0 python3.12-venv python3-pip
fi
if ! "$HOME/esp/qemu/qemu/bin/qemu-system-riscv32" -machine help >/dev/null 2>&1; then
  echo "qemu needs libslirp.so.0 (package libslirp0)" >&2
  exit 1
fi
"$HOME/esp/qemu/qemu/bin/qemu-system-riscv32" -machine help | grep -q esp32c3
echo "esp32c3 tools ok"

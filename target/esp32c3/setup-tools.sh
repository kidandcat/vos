#!/usr/bin/env bash
# Install ESP-IDF v5.4.4 (esp32c3) and Espressif's riscv32 QEMU into $HOME.
# Safe to re-run. apt is only used for QEMU's shared libraries and Python venv.
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

# The published riscv32 binary is dynamically linked. A headless runner
# has libc and not the rest; the loader error is not always libslirp.
if command -v sudo >/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    libslirp0 libpixman-1-0 libgcrypt20 libglib2.0-0 libsdl2-2.0-0 zlib1g \
    python3.12-venv python3-pip
fi
QEMU_BIN="$HOME/esp/qemu/qemu/bin/qemu-system-riscv32"
if [ ! -x "$QEMU_BIN" ]; then
  echo "qemu binary missing at $QEMU_BIN" >&2
  find "$HOME/esp/qemu" -name 'qemu-system-riscv32' -print >&2 || true
  exit 1
fi
# -machine help still loads SDL. dummy keeps a runner with no display alive.
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
if ! "$QEMU_BIN" -machine help >/tmp/vos-qemu-help.txt 2>/tmp/vos-qemu-help.err; then
  echo "qemu -machine help failed" >&2
  ldd "$QEMU_BIN" >&2 || true
  cat /tmp/vos-qemu-help.err >&2 || true
  exit 1
fi
grep -q esp32c3 /tmp/vos-qemu-help.txt
echo "esp32c3 tools ok"

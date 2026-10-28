#!/usr/bin/env bash
# Install ESP-IDF v5.4.4 (esp32c3 and esp32s3) and Espressif's QEMU into $HOME.
# Safe to re-run. apt is used for QEMU's shared libraries, Python venv, and
# for cmake and ninja when install.sh has not put those two on PATH.
set -euo pipefail
IDF_TAG=v5.4.4
QEMU_TAG=esp-develop-9.2.2-20260417
QEMU_BASE=https://github.com/espressif/qemu/releases/download/${QEMU_TAG}

mkdir -p "$HOME/esp"
if [ ! -f "$HOME/esp/esp-idf/export.sh" ]; then
  git clone --depth 1 -b "$IDF_TAG" https://github.com/espressif/esp-idf.git "$HOME/esp/esp-idf"
fi
cd "$HOME/esp/esp-idf"
git submodule update --init --recursive --depth 1
./install.sh esp32c3 esp32s3

fetch_qemu() {
  local bin=$1 tar=$2
  if [ -x "$HOME/esp/qemu/qemu/bin/$bin" ]; then
    return 0
  fi
  mkdir -p "$HOME/esp/qemu"
  curl -fL --retry 3 -o "/tmp/$tar" "$QEMU_BASE/$tar"
  tar -C "$HOME/esp/qemu" -xJf "/tmp/$tar"
}

fetch_qemu qemu-system-riscv32 \
  qemu-riscv32-softmmu-esp_develop_9.2.2_20260417-x86_64-linux-gnu.tar.xz
fetch_qemu qemu-system-xtensa \
  qemu-xtensa-softmmu-esp_develop_9.2.2_20260417-x86_64-linux-gnu.tar.xz

# install.sh records cmake and ninja in its tool list but does not always
# leave the commands on PATH (a system cmake with no ninja is the usual case).
# idf.py will not configure without both.
if command -v sudo >/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    libslirp0 libpixman-1-0 libgcrypt20 libglib2.0-0 libsdl2-2.0-0 zlib1g \
    python3.12-venv python3-pip \
    cmake ninja-build
fi
if ! command -v cmake >/dev/null || ! command -v ninja >/dev/null; then
  echo "cmake and ninja must be on PATH. install.sh did not provide them." >&2
  echo "Install packages cmake and ninja-build, then re-run this script." >&2
  exit 1
fi

export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
check_qemu() {
  local bin=$1 machine=$2
  local path="$HOME/esp/qemu/qemu/bin/$bin"
  if [ ! -x "$path" ]; then
    echo "qemu binary missing at $path" >&2
    find "$HOME/esp/qemu" -name "$bin" -print >&2 || true
    exit 1
  fi
  if ! "$path" -machine help >/tmp/vos-qemu-help.txt 2>/tmp/vos-qemu-help.err; then
    echo "$bin -machine help failed" >&2
    ldd "$path" >&2 || true
    cat /tmp/vos-qemu-help.err >&2 || true
    exit 1
  fi
  grep -q "$machine" /tmp/vos-qemu-help.txt
}
check_qemu qemu-system-riscv32 esp32c3
check_qemu qemu-system-xtensa esp32s3
echo "cmake $(cmake --version | head -1)"
echo "ninja $(ninja --version)"
echo "esp32c3 and esp32s3 tools ok"

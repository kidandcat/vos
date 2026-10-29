# Put cmake and ninja on PATH when ESP-IDF unpacked them outside it.
# Sourced by the chip wrappers and by target/esp/run-qemu.sh.
ensure_vos_build_tools() {
  local bin found
  # find and head live in the usual directories. export.sh can drop those
  # from PATH, so the search itself does not depend on the caller's PATH.
  local toolpath="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  for bin in cmake ninja; do
    if command -v "$bin" >/dev/null 2>&1; then
      continue
    fi
    found=$(PATH="$toolpath" find "$HOME/.espressif/tools" /usr/local/bin /usr/bin \
      -type f -name "$bin" 2>/dev/null | PATH="$toolpath" head -1 || true)
    if [ -n "$found" ]; then
      PATH="${found%/*}:${PATH}"
      export PATH
    fi
  done
}

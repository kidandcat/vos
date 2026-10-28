#!/usr/bin/env bash
# What each vos module adds when that probe is the only entry.
# Links the bundled C with the chip gcc and --gc-sections. The delta is
# against the empty probe, which is the prelude and the runtime pool.
# This is not the ESP-IDF image. Flash and RAM of the demo image are what
# target/esp/run-qemu.sh prints from idf.py size.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
IDF_PATH=${IDF_PATH:-"$HOME/esp/esp-idf"}
# shellcheck disable=SC1091
source "$HOME/.elan/env"
# shellcheck disable=SC1091
source "$IDF_PATH/export.sh"

if [ ! -s "$ROOT/.lake/c3/init-c/.complete" ]; then
  echo "== generating C for Lean's Init (once per toolchain)"
  bash "$ROOT/target/c3/gen_init_c.sh" "$(lean --print-prefix)" "$ROOT/.lake/c3/init-c"
  echo ok > "$ROOT/.lake/c3/init-c/.complete"
fi
lake build

OUT=$ROOT/.lake/size
rm -rf "$OUT"
mkdir -p "$OUT"
# name entry symbol expect
probes=(
  "empty Vos.Target.Size.Empty vos_size_empty 0"
  "queue Vos.Target.Size.Queue vos_size_queue 1"
  "sched Vos.Target.Size.Sched vos_size_sched 1"
  "kernel Vos.Target.Size.Kernel vos_size_kernel 1"
  "timer Vos.Target.Size.Timer vos_size_timer 1"
  "sem Vos.Target.Size.Sem vos_size_sem 1"
  "mutex Vos.Target.Size.Mutex vos_size_mutex 1"
  "event Vos.Target.Size.Event vos_size_event 1"
)

link_one() {
  local name=$1 cc=$2 elf=$3 harness=$4
  local bundle=$OUT/$name
  local extra=()
  case "$cc" in
    *xtensa*) extra=(-mlongcalls -mtext-section-literals) ;;
  esac
  # shellcheck disable=SC2086
  "$cc" -O2 -ffunction-sections -fdata-sections -fno-common \
    -I "$bundle/include" -DUVL_HEAP_SIZE=98304 \
    "${extra[@]}" \
    "$bundle"/src/*.c "$bundle"/rt/uvl_rt.c "$harness" \
    -o "$elf" -lm -Wl,--gc-sections
}

for row in "${probes[@]}"; do
  read -r name entry sym expect <<<"$row"
  harness=$OUT/$name-harness.c
  cat >"$harness" <<EOF
#include <stddef.h>
#include <stdint.h>
extern void vos_rt_init(void);
extern uint32_t ${sym}(uint32_t);
extern void *uvl_heap_alloc(size_t n);
int main(void) {
  vos_rt_init();
  /* Keep the static pool in every probe, including the empty one. */
  (void)uvl_heap_alloc(8);
  return ${sym}(0) == ${expect} ? 0 : 1;
}
EOF
  echo "---- bundle $name ----"
  python3 "$ROOT/target/c3/bundle.py" \
    --lean-prefix "$(lean --print-prefix)" \
    --ir "$ROOT/.lake/build/ir" \
    --init-c "$ROOT/.lake/c3/init-c" \
    --extra-c "$ROOT/.lake/c3/extra-c" \
    --entry "$entry" \
    --harness "$harness" \
    --out "$OUT/$name"
  "$OUT/$name/vos-c3-host"
  link_one "$name" riscv32-esp-elf-gcc "$OUT/$name-c3.elf" "$harness"
  link_one "$name" xtensa-esp-elf-gcc "$OUT/$name-s3.elf" "$harness"
  riscv32-esp-elf-size -d "$OUT/$name-c3.elf" >"$OUT/$name-c3.size"
  xtensa-esp-elf-size -d "$OUT/$name-s3.elf" >"$OUT/$name-s3.size"
done

python3 - "$OUT" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
names = ["empty", "queue", "sched", "kernel", "timer", "sem", "mutex", "event"]
note = {
    "empty": "prelude only",
    "queue": "Vos.Queue",
    "sched": "Vos.Sched",
    "kernel": "Vos.Kernel, which imports Queue and Sched",
    "timer": "Vos.Timer",
    "sem": "Vos.Sem, which imports Sched",
    "mutex": "Vos.Mutex, which imports Sched",
    "event": "Vos.Event, which imports Sched",
}

def parse(path):
    lines = path.read_text().splitlines()
    for line in lines:
        parts = line.split()
        if len(parts) >= 3 and parts[0].isdigit():
            return tuple(int(x) for x in parts[:3])
    raise SystemExit(f"no size line in {path}")

rows = {(name, arch): parse(out / f"{name}-{arch}.size") for name in names for arch in ("c3", "s3")}
print("| probe | opt-in | arch | text | data | bss | text−empty | data−empty | bss−empty |")
print("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |")
for name in names:
    for arch in ("c3", "s3"):
        text, data, bss = rows[(name, arch)]
        bt, bd, bb = rows[("empty", arch)]
        print(f"| {name} | {note[name]} | {arch} | {text} | {data} | {bss} | {text - bt} | {data - bd} | {bss - bb} |")
print()
print("Every probe calls uvl_heap_alloc so the 98304-byte pool is linked. text/data/bss deltas are on top of the empty probe.")
PY

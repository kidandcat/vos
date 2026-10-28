#!/bin/sh
# gen_init_c.sh <lean-prefix> <out-dir>
# C for every module of Lean's Init (about 650 files, once per toolchain).
# The toolchain ships Init only as host objects; the C3 image needs the C.
set -e
L=$1
OUT=$2
HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
cd "$L/src/lean"
# shellcheck disable=SC2046
exec "$HERE/gen_c.sh" "$L" "$OUT" Init.lean $(find Init -name '*.lean')

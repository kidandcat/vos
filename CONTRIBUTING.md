# Contributing

Issues and pull requests are welcome. The text in this repository is English: README, docs, comments, commit messages, scripts, and CI. Discussion with the maintainer can be in another language. The files that land in the tree stay in English.

## Build

The Lean toolchain is pinned in `lean-toolchain` (v4.35.0).

```bash
lake build
lake test
lake exe vos-demo
bash scripts/check-axioms.sh
bash scripts/check-firmware-boundary.sh
bash scripts/check-version.sh
```

`lake test` prints `vos tests ok`. A proof may use only `propext`, `Classical.choice`, and `Quot.sound`. No `sorry`. No new `axiom`.

## What belongs in the core

`Vos.Sched`, `Vos.Queue`, `Vos.Kernel`, and the sync modules stay free of VM and AI-agent sandbox code. That code lives under `Vos.Sandbox` or `Vos.Agent` and is imported only by a target that wants it. `scripts/check-firmware-boundary.sh` enforces this, including the C bundled for ESP32.

Do not claim a board, a radio, or an emulator you did not run. Say what the log showed.

## Version

A user-visible change updates `CHANGELOG.md`. A release also changes `version := v!"X.Y.Z"` in `lakefile.lean` so the two strings match. See `RELEASING.md`. Do not push a git tag. The maintainer creates tags after merge.

## ESP32 and QEMU

`bash target/esp32c3/setup-tools.sh` installs ESP-IDF v5.4.4, both QEMU builds, and `cmake` / `ninja` if they are missing. `bash target/esp32c3/run-qemu.sh` and `bash target/esp32s3/run-qemu.sh` boot the demo. `bash target/rv32-virt/run-qemu.sh` boots the generic RV32 image on QEMU `virt`. That image is not an RP2350.

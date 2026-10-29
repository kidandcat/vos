# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Vos.Arch.Mtime`: a machine-timer state machine. Pending while `cmp ≤ time`. An idle `take` is one `Sched.tick`. A busy kernel only queues the tick.
- `target/rv32-virt`: generic RV32 startup, UART, and a CLINT `mtime`/`mtimecmp` tick, booted on QEMU `virt`. The serial line is `vos rv32: virt ok`. This is not an RP2350 image.

### Changed

- ESP32-C3 and ESP32-S3 are the primary targets. Both boot in Espressif QEMU only. `rp2350-riscv`, the Pico 2 W, the CYW43439, and the SX126x are parked. `docs/bare-metal.md` records what a later board bring-up still has to show, and the order of those pull requests.
- `scripts/check-firmware-boundary.sh` scans bundled C and `nm` symbol tables for `Vos_Sandbox` and `Vos_Agent`. A file name alone does not decide the result.
- `VOS_QEMU` selects the QEMU binary in the chip wrappers. `target/esp/ensure-path.sh` puts `cmake` and `ninja` on `PATH` when ESP-IDF left them off it.

## [0.1.0] - 2026-10-29

First tagged line of the kernel. The items below are the work that landed on `main` through pull request 5. Nothing here was run on a physical board.

### Added

- Host scheduler and bounded queues, with theorems checked in CI (`propext`, `Classical.choice`, `Quot.sound` only). A differential test compares the scheduler with a second implementation. Pull request 1.
- Timers, counting semaphores, a non-recursive mutex, and 32 event flags, plus the lemmas that unblocking a task and sending to a waiting receiver make that task ready. Pull request 2.
- ESP32-C3 target. One FreeRTOS task runs the Lean demo. An `esp_timer` callback only posts ticks on an ESP-IDF queue. The image boots in Espressif QEMU, machine `esp32c3`, and a script checks the serial log. Pull request 3.
- ESP32-S3 target with the same demo, booted in QEMU machine `esp32s3`. Measured flash and RAM for both chips, and a table of what each kernel module adds when linked alone. UART and NVS are checked on the serial log. GPIO calls the IDF driver; QEMU read the pin back as 0. SPI, I2C, and the radio hook stay stubs. Pull request 4.
- Firmware boundary: `Vos.Sandbox` and `Vos.Agent` are opt-in, and CI fails if the core or an ESP32 bundle reaches them. `docs/bare-metal.md` plans `rp2350-riscv` (Hazard3) as the first bare-metal core, with the CYW43439 and an SX126x still unbuilt. Pull request 5.

[Unreleased]: https://github.com/kidandcat/vos/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kidandcat/vos/releases/tag/v0.1.0

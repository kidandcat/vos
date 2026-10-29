# Bare metal: RP2040 and RP2350

Not started. No RP2040 or RP2350 image has been compiled or booted here. This note is the plan for the PRs after the ESP32-S3 work. It is not a proof and not a test.

The core stays the pure kernel. These targets are opt-in. They must not be imported by `Vos.Sched`, `Vos.Queue`, `Vos.Kernel`, or the rest of the core. VM and agent sandboxing stay in `Vos.Sandbox` and `Vos.Agent`, which these firmware images also must not link. `scripts/check-firmware-boundary.sh` is that check.

## What is asked

A standalone image. No FreeRTOS and no ESP-IDF. Our own startup, vector table, and tick. RP2040 is Cortex-M0+. RP2350 has Cortex-M33 cores and Hazard3 RISC-V cores; those are two images, not one startup. The radio is SPI, one interface, two chips: SX126x, and SX1276 because the older doors use it.

uvl is the reference for the shape of a bare-metal Lean image, not for an RP2040 boot. Its `baremetal/pico/` firmware is Pico SDK, cross-compiled for Pico and Pico 2, and that README says it has not been run on a board. The emulator run in `baremetal/tools/test.sh` is `qemu-system-arm -M mps2-an385`, a Cortex-M3 board. That checks the C bundle on a generic ARM core. It does not boot an RP2040 ROM, XIP flash, or SPI peripheral. This note is from reading that tree. Those binaries were not run for this note.

## What can be proved

The kernel tick is already a pure function. A bare-metal port adds a small model of the registers the tick path touches, and nothing else.

Worth modelling in Lean, as a state and a step, not as MMIO:

- SysTick: control, reload, current, count-flag. A theorem that an enabled timer with reload `n` raises one tick when the count expires, and that writing the current register clears it.
- The kernel clock: that one accepted tick is one `Sched.tick`, and a tick that arrives while the kernel is already in a step is queued, not re-entered. The core stays single-threaded. Core 1 stays out of the model.
- The radio command encoder, behind one `exchange` function that takes bytes and returns bytes. SX126x opcodes and SX1276 register writes are two tables. A theorem can say the bytes for "write this buffer" and "read it back" match, and that a busy flag does not drop a finished transfer. The host can run that against a fake SPI trace. That is a test of the encoder, not of a radio.

A proof about that model does not say the C stores the register, that the vector table points at the handler, or that the silicon matches the datasheet. Those stay in the trusted base, next to the compiler and the runtime.

## What stays C or assembly

- The reset handler: stack pointer, copy `.data`, zero `.bss`, set `VTOR`, call the Lean init. Assembly, or a few instructions of C that we do not pretend to prove.
- The vector table itself.
- The handler's load and store of the real SysTick and NVIC registers. On M0+ the hardware stacks the exception frame, so the handler body can be C. The Lean model is the specification that C is supposed to match.
- The linker script and the flash boot stage. RP2040 does not start at our reset vector; the boot ROM does. Getting from the ROM into our image is C, a second-stage, or an emulator shortcut. It is not a kernel theorem.
- SPI byte shifts. The radio encoder calls `vos_hal_spi_xfer`. The transfer is C until some later model of the FIFO exists. That C is the same stub-or-driver split the ESP shim already uses.

## Emulators

Nothing in this list was run for this note. Upstream QEMU has no `rp2040` or `rp2350` machine. It can run a Cortex-M binary on a different board, which is what uvl does with `mps2-an385`. That is the only emulator path whose shape is already known in this project, and it is not an RP2040.

| Option | What it claims | SPI radio | Run here |
| --- | --- | --- | --- |
| Upstream `qemu-system-arm -M mps2-an385` | Cortex-M3, not RP2040 | no | not for this note; this is uvl's bundle check |
| [QEMU RFC branch](https://github.com/2xs/qemu-rp2040-pico) (Gilles Grimaud, patches on qemu-devel through October 2026, not merged) | RP2040 / Pico: M0+, UART, timers, DMA, XIP, boot ROM. The v2 cover letter says general-purpose SPI, PIO, I2C, PWM, and ADC are not implemented | no | not run |
| [matgla/Renode_RP2040](https://github.com/matgla/Renode_RP2040) | Renode description of RP2040. The repo says it is frozen work in progress. SPI master is partial | maybe a byte transfer, not a checked SX126x | not run |
| [picoem](https://github.com/0x4D44/picoem) `rp2040-emu` / `rp2350-emu` | Research emulators. Arm only. The published table lists UART, SPI, and I2C as stubs. Hazard3 is out of scope | no | not run |
| [Lemur](https://github.com/lukaspirkl/Lemur) | Hazard3 on RP2350, real boot ROM, GDB. The author says most peripherals are stubs | no | not run |
| [rp2350js](https://github.com/c1570/rp2350js) | RP2040 and RP2350, Hazard3 and a basic Cortex-M33. Runs some pico-examples, MicroPython, PIO, and DMA | not established | not run |

So the first boot that can be claimed as an RP2040 is not available from upstream QEMU. A later PR has to install one of the forks, name the commit, and paste the serial log. If that emulator has no SPI master, the radio stays a host test of the encoder. It must not be described as an on-air or on-chip test.

## Risks

- M0+ is not M3. A bundle that runs on `mps2-an385` can still be illegal or slow on M0+ (no divide instruction, soft float if any Init code emits it). uvl's Pico cross-compile is evidence that a similar bundle can link, not that this demo does.
- 264 KB SRAM on RP2040. The pool is 96 KB. uvl's Pico figure was about 115 KB of static RAM including that pool. Headroom is real and small. The ESP-IDF images are not that number.
- Dual core. This kernel is one thread. Core 1 stays in reset. A proof about core 0 says nothing about the second core or the SIO FIFO.
- Boot ROM versus "the emulator jumped to our ELF". Those are different claims. An ELF load that skips the ROM can pass and still not boot from flash.
- SX126x and SX1276 do not share a register map. One Lean interface with two encoders is the design. One C driver with `#ifdef` inside the kernel is not.
- Proofs stop at the model. The C stores, the vector table, the ROM, and the radio silicon are trusted, not proved.

## Order

1. Boundary check and this note. No chip code.
2. SysTick model in Lean, with the tick theorem, and a C handler plus vector table linked into the existing runtime. Boot that on `mps2-an385` and label it Cortex-M3, not RP2040.
3. RP2040 startup and linker script, no Pico SDK and no FreeRTOS. UART trace. Install one emulator from the table, record the commit, and write down which peripherals answered. No radio claim unless that emulator actually clocks SPI.
4. Radio encoder in Lean for SX126x and SX1276, tested against a fake SPI trace on the host. The C transfer stays a shim.
5. RP2350 Cortex-M33 image, reusing the ARM startup only where the ISA matches. Hazard3 is a separate image, and only after an emulator we have actually run executes it.

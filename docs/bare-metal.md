# Targets: ESP32-C3 and ESP32-S3

The primary targets are ESP32-C3 (RISC-V) and ESP32-S3 (Xtensa). Both images in this tree boot in Espressif QEMU (`esp32c3` and `esp32s3`). Neither has been run on a board. The trusted base is unchanged: the proofs trust the Lean kernel, compiler, and runtime. They do not trust the C shim, FreeRTOS, ESP-IDF, the peripherals, or QEMU. There is no whole-firmware claim.

`rp2350-riscv` (the RP2350's Hazard3, plus an SX126x on SPI) and the Pico 2 W (CYW43439) are parked. They are a later bet, not the next pull request. This tree does not start that target and does not investigate an RP2350 emulator. The notes further down are the record already written. They were not re-run for this decision.

The core stays the pure kernel. It does not depend on a VM or on an AI-agent sandbox. That code lives in `Vos.Sandbox` and `Vos.Agent`. `scripts/check-firmware-boundary.sh` fails if the core imports them, if bundled C names them, or if `nm` finds a `Vos_Sandbox` or `Vos_Agent` symbol.

`target/rv32-virt` stays in the tree as a generic RV32 check. It is linked at `0x80000000` and booted on QEMU's `virt` machine. Its serial line is `vos rv32: virt ok`. It is not an RP2350 boot.

## From QEMU to a board

What the QEMU log already shows, on both chips, is the host demo compiled to C:

- UART0. `printf` and `vos_hal_uart_write` (`uart_write_bytes` on UART0) produced `hal uart ok`. The console is the default UART. On the S3, `sdkconfig.defaults` sets `CONFIG_ESP_CONSOLE_SECONDARY_NONE` so the log is not the USB Serial/JTAG console.
- NVS. The shim writes `0xA5` under key `probe` in namespace `vos` and reads it back (`hal nvs ok`).
- The demo lines `sent 41`, `timer not due`, and `demo ok`.
- The tick is an `esp_timer` callback (100 ms) that only posts event `2` on an ESP-IDF queue. `app_main` is the only task that calls Lean. This is not `Vos.Arch.Mtime`, and it is not a proved interrupt.

What that log does not show:

- A flash of the merged 4 MB image (`esptool.py merge_bin --fill-flash-size 4MB`) onto a physical C3 or S3, and the same lines on a real serial port. The QEMU command uses `-drive file=flash_image.bin,if=mtd,format=raw`. A board uses the serial port the adapter actually enumerates.
- GPIO. The shim calls `gpio_config`, `gpio_set_level`, and `gpio_get_level` on pin 4. Under both QEMU machines the readback was 0 after a set to 1, and the log says `hal gpio level unread`. The pin was not observed.
- SPI, I2C, and the radio hook. No slave is attached to the QEMU command. Those three return -1 and the log says `stub`.

If an SX126x is added later, on either chip, the shift stays in C. `vos_hal_spi_xfer` would call the ESP-IDF SPI master, with the board's pins and the busy and DIO lines as GPIO. A Lean SX126x codec can be checked on the host against a fake SPI trace. That codec is the bytes, not an on-air test, and it is not this image.

What stays C on these two targets: ESP-IDF startup, FreeRTOS, `target/idf` (the shim and `app_main`), `target/c3/rt/uvl_rt.c`, and the C that Lean emits. The Lean model does not store the UART FIFO, the timer register, or a GPIO pad.

### Proposed order

1. This change: the note, the README, `VOS_QEMU`, `cmake`/`ninja` on `PATH`, and a boundary check that reads symbols. No kernel change.
2. Flash the same image to a named C3 board and a named S3 board. The pass line is the same serial text the QEMU script already requires. Until that log exists, the README keeps "not on a board".
3. GPIO on that board, or an explicit note that the pin was still not observed. QEMU readback is not that result.
4. SPI shim in C, then an SX126x codec in Lean against a host fake trace. No air.
5. Parked, and not started: `rp2350-riscv`, the Pico 2 W, the CYW43439 blob, and an RP2350 emulator.

## Parked: `rp2350-riscv`

The Hazard3 facts below are citations, not a boot. No RP2350 emulator was started. No CYW43439 firmware was fetched or committed, and no SX126x transaction was run. Cortex-M33, RP2040, and the SX1276 on the older doors stay behind the same HAL and the same radio interface, later still.

Source: RP2350 datasheet, RP-008373-DS-3, section 3.8. The two cores are identical. Each socket holds either a Cortex-M33 or a Hazard3; the one not selected is held in reset. Cortex-M33 is the default at boot (section 3.9). Section 3.8 lists the standard extensions RP2350 enables:

- RV32I, M, A, C (also spelled Zca), Zba, Zbb, Zbs, Zbkb, Zcb, Zcmp, Zicsr
- Machine and User modes, PMP with eight NAPOT regions, debug

The same section's architecture string, preferred for GCC 14, is `rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp`. The table above that also lists Zifencei v2.0. Custom extensions in that section: Xh3power, Xh3bextm, Xh3irq, Xh3pmpm. `src/rp2_common/hardware_hazard3/include/hardware/hazard3/features.h` in the Pico SDK sets those four to version 1.0 when `PICO_RP2350` is set.

The timer is not an Arm SysTick. Datasheet section 3.1.8, "RISC-V platform timer": one 64-bit counter shared by both cores, `MTIME` and `MTIMEH` in the SIO block. Each core has its own `MTIMECMP` / `MTIMECMPH` at the same address. The interrupt is asserted, unsigned, while `MTIME ≥ MTIMECMP`. It drives `mip.mtip` on the RISC-V cores and `SIO_IRQ_MTIMECMP`. The Hazard3 manual (https://wren.wtf/hazard3/doc/, interrupt-request table) says the core's `timer_irq` pin is `mip.mtip` and should be wired to a standard `mtime`/`mtimecmp` peripheral. The generated register header `hardware/regs/rvcsr.h` in the Pico SDK names `mcause` code 7 as the timer IRQ. Xh3irq is the local controller for external system IRQs; it is not the machine timer.

The QEMU `virt` image uses the CLINT at `0x02000000`, not the SIO block. Same compare, different address. That is why the log says `virt` and not `rp2350`.

### Two buses, one radio interface

The CYW43439 on a Pico W / Pico 2 W is not on the hardware SPI block. The wiring is a PIO program that speaks a short gSPI. [soypat/cyw43439](https://github.com/soypat/cyw43439) is the pattern: a pure driver over that PIO bus. The chip's firmware, about 224 KB for Wi-Fi and about 231 KB for the combined Wi-Fi and Bluetooth image in that repository's embed file, is loaded into the CYW43439 and runs there. It does not run on the RP2350.

The SX126x is a normal SPI slave on a hardware SPI block, plus a busy pin and a DIO. It does not share the PIO program with the CYW43439.

Both radios would sit behind one Lean interface: `exchange` takes a bounded byte string and returns one. SX126x commands are one codec. A later SX1276 codec is a second table, not a second interface. The CYW43439 is not that interface. It is a bus that, once the blob is loaded, yields Ethernet frames. Those frames would enter a separate network module. None of this is implemented.

Pin numbers are not fixed in this note. A later pull request that writes the C copies them from the Pico 2 W schematic.

### What a later proof could cover

The kernel tick is already a pure function. Around a parked target, the host theorems that exist today are only these:

- The machine timer, as a state and a step (`Vos.Arch.Mtime`). Pending while `cmp ≤ time`. `setCmp` to a later compare clears it. `advance` before the compare does not. `take` with a positive period counts one tick when the kernel is idle, and only increments `queued` when it is busy. `onTimer` applies that idle tick as one `Sched.tick`. Core 1 is outside the model. These are host theorems. They do not say the QEMU `virt` image implements them, and they do not say an ESP32 `esp_timer` callback implements them.
- An SX126x codec, not written. The bytes for a write and the matching read, and a busy flag that does not drop a finished transfer. The host would run that against a fake SPI trace. That is the encoder, not a radio and not the air.
- CYW43439 framing, not written. SDPCM and ioctl headers, sequence numbers, and a download that is a sequence of writes covering a blob of a given length. The theorem would be about those bytes. It says nothing about what the blob does after it starts.
- A minimal IP codec, opt-in, not imported by the kernel. See below. Not written.

None of that says the C stores the register, that the vector table points at the handler, that the boot ROM entered our image, or that a frame left the antenna.

### IP stack

[soypat/lneto](https://github.com/soypat/lneto) is the pattern, not a dependency. It is a userspace stack with no OS, no goroutines, time passed in by the caller, and one small interface for every protocol. Its licence is BSD-3-Clause. We do not vendor it.

A vos version would be a Lean module, `Vos.Net`, opted in by a Pico 2 W target and by nobody else. It does not exist.

The boundary protocol would be a bounded Ethernet frame. The CYW43439 side, after the blob is running, delivers frames. The Lean side never sees PIO, SPI, or SDPCM.

First slice, and the only one this plan treats as provable, if that target is ever started:

- Ethernet header, IPv4 header, UDP header.
- The IPv4 and UDP checksums match the ones defined on the bytes.
- One state machine: a UDP echo, or the bytes of a DHCP discover. A fixed input frame produces a fixed output frame.

TCP, TLS, and "joined this access point" are not in that slice. The kernel must not import `Vos.Net`.

### What would stay C or assembly

- Reset: stack, copy `.data`, zero `.bss`, set `VTOR`. Assembly.
- The vector table.
- The timer handler's loads and stores. On the Hazard3 that is `mtime` / `mtimecmp` in the SIO, not SysTick. The Lean model is the specification that C is supposed to match. The QEMU `virt` image already has a C handler for the CLINT, and that handler is not proved.
- The linker script and whatever the RP2350 boot ROM requires before our reset runs. That is a boot stage, not a kernel theorem.
- The PIO program for the CYW43439 gSPI, and the hardware SPI shift for the SX126x. Both are C or PIO assembly. `exchange` would be the Lean name; the shift is not.
- Copying the firmware blob into the download buffer. The blob is data. We do not disassemble it.

### The CYW43439 blob

The firmware source is not available. Infineon has said the Wi-Fi firmware source is proprietary and is not shared. The blob runs inside the CYW43439.

Two licences showed up when this note was written. They are not the same object:

- The C driver at [georgerobotics/cyw43-driver](https://github.com/georgerobotics/cyw43-driver) is MIT. `LICENSE` is the MIT text, copyright 2019–2026 George Robotics Pty Ltd, and `src/cyw43.h` says `SPDX-License-Identifier: MIT`. That is the driver source, not the blob.
- [soypat/cyw43439](https://github.com/soypat/cyw43439) is also MIT for the Go driver. The blobs under its `firmware/` directory (Wi-Fi about 224190 bytes, combined Wi-Fi and Bluetooth about 231077 bytes) sit next to `LICENSE-permissive-binary-license-1.0.lic`. That licence allows redistribution in binary form, without modification. It forbids reverse engineering, decompilation, and disassembly. It grants no patent licence for combinations that include the software, and it licences no hardware. The file, as fetched, does not name the copyright holder above the title.

Older packaging, including the `cyw43-firmware` crate's docs, described a George Robotics non-commercial licence and a separate Raspberry Pi Ltd licence limited to RP2040 and other chips produced by Raspberry Pi Ltd. The current driver repository's top-level `LICENSE` is the MIT text, and a fetch of `LICENSE.RP` from that repository returned 404. This note does not treat the blob as MIT.

vos will not commit the blob until a human puts the licence file beside it and accepts those terms. The blob is not rewritten, not disassembled, and not proved. Bluetooth, if it is ever switched on, needs its own licence check. BTstack as shipped by the Pico SDK has been a separate grant from the Wi-Fi blob. It is not part of any image in this tree.

### Emulators, not started

Nothing in this table was run. No usable emulator found when the note was first written runs the CYW43439 or its firmware. This decision does not reopen that search.

| Option | What it claims | CYW43439 | SX126x SPI | Run here |
| --- | --- | --- | --- | --- |
| Upstream QEMU | No RP2350 machine. `qemu-system-arm -M mps2-an385` is a Cortex-M3, which is what uvl's bundle test uses | no | no | not run |
| [QEMU RFC `2xs/qemu-rp2040-pico`](https://github.com/2xs/qemu-rp2040-pico) | RP2040, not RP2350. Not merged. Cover letter: general-purpose SPI is not implemented | no | no | not run |
| [picoem](https://github.com/0x4D44/picoem) `rp2350-emu` | Research emulator, Cortex-M33. UART, SPI, and I2C listed as stubs. Hazard3 out of scope | no | no | not run |
| [Lemur](https://github.com/lukaspirkl/Lemur) | Hazard3 on RP2350. Author: most peripherals are stubs | no | no | not run |
| [rp2350js](https://github.com/c1570/rp2350js) | RP2350, Hazard3 and a basic Cortex-M33. Some Pico examples, PIO, DMA | no | not established | not run |
| Renode wireless | IEEE 802.15.4 and BLE media. Not 802.11, not this chip | no | no | not run |

uvl remains the reference for the shape of a bare-metal Lean image. Its Pico firmware is the Pico SDK, and that README says it was not run on a board. The emulator line in `baremetal/tools/test.sh` is the Cortex-M3 board above. That was read, not run.

A first boot that could be claimed as a Pico 2 W would be a serial log from a named emulator commit, or from a board. A generic Cortex-M3 run is labeled Cortex-M3. A fake SPI trace is labeled a fake SPI trace. Neither is the radio. None of those logs exist here.

### Risks, if that target is unparked

- The blob is opaque and large. SRAM on the RP2350 is 520 KB. The pool is 96 KB. A 230 KB blob that is only copied out to the CYW43439 still has to sit in flash, and the download buffer has to sit in RAM while it is sent. The first image should not link `Vos.Net` and the blob at the same time until those sizes are measured.
- PIO gSPI is timing-sensitive. A model of SDPCM bytes does not show that the PIO program samples the wire correctly.
- A bundle that runs on QEMU `virt` can still be wrong on the RP2350 (boot ROM, XIP, SIO timer address). TrustZone is an Arm feature and is not this image.
- One Hazard3. The other Hazard3 stays reset. A theorem about core 0 says nothing about core 1, and nothing about the Cortex-M33 sockets, which the datasheet holds in reset when RISC-V is selected.
- SX126x and the later SX1276 do not share a register map. One `exchange` and two codecs. Not one C function full of `#ifdef` inside the kernel.
- Proofs stop at the model. The C, the PIO program, the ROM, the blob, and both radios are trusted, not proved.

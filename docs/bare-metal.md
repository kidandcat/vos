# Bare metal: Pico 2 W first

Not started. No RP2350 image has been compiled or booted here, and no CYW43439 or SX126x transaction has been run. This is the plan. It is not a proof and not a test.

The first bare-metal target is the Raspberry Pi Pico 2 W: an RP2350, the on-board CYW43439 Wi-Fi/Bluetooth chip, and an SX126x LoRa module on SPI. RP2040, and the SX1276 used by the older doors, stay later targets behind the same HAL and the same radio interface. They are not the first image.

The core stays the pure kernel. This target is opt-in. It must not be imported by `Vos.Sched`, `Vos.Queue`, or `Vos.Kernel`. VM and agent sandboxing stay in `Vos.Sandbox` and `Vos.Agent`. `scripts/check-firmware-boundary.sh` fails if a firmware bundle links those.

No FreeRTOS and no ESP-IDF. Our own startup, vector table, and tick. The RP2350 has Cortex-M33 cores and Hazard3 RISC-V cores. The first image is Cortex-M33, one core. Hazard3 is a second image, later, and only if an emulator we have actually run executes it.

## Two buses, one radio interface

The CYW43439 on a Pico W / Pico 2 W is not on the hardware SPI block. The wiring is a PIO program that speaks a short gSPI. [soypat/cyw43439](https://github.com/soypat/cyw43439) is the pattern: a pure driver over that PIO bus. The chip's firmware, about 224 KB for Wi-Fi and about 231 KB for the combined Wi-Fi and Bluetooth image in that repository's embed file, is loaded into the CYW43439 and runs there. It does not run on the RP2350.

The SX126x is a normal SPI slave on a hardware SPI block, plus a busy pin and a DIO. It does not share the PIO program with the CYW43439.

Both radios sit behind one Lean interface: `exchange` takes a bounded byte string and returns one. SX126x commands are one codec. A later SX1276 codec is a second table, not a second interface. The CYW43439 is not that interface. It is a bus that, once the blob is loaded, yields Ethernet frames. Those frames enter a separate network module.

Pin numbers are not fixed in this note. The PR that writes the C copies them from the Pico 2 W schematic.

## What can be proved

The kernel tick is already a pure function. Around it:

- SysTick, as a state and a step. An enabled timer with reload `n` raises one tick when the count expires. Writing the current register clears it. One accepted tick is one `Sched.tick`. A tick that arrives during a kernel step is queued, not re-entered. Core 1 is outside the model.
- The SX126x codec. The bytes for a write and the matching read, and a busy flag that does not drop a finished transfer. The host runs that against a fake SPI trace. That is the encoder, not a radio and not the air.
- The CYW43439 framing that we can see from the RP2350: SDPCM and ioctl headers, sequence numbers, and a download that is a sequence of writes covering a blob of a given length. The theorem is about those bytes. It says nothing about what the blob does after it starts.
- A minimal IP codec, opt-in, not imported by the kernel. See below.

None of that says the C stores the register, that the vector table points at the handler, that the boot ROM entered our image, or that a frame left the antenna.

## IP stack

[soypat/lneto](https://github.com/soypat/lneto) is the pattern, not a dependency. It is a userspace stack with no OS, no goroutines, time passed in by the caller, and one small interface for every protocol. Its licence is BSD-3-Clause. We do not vendor it.

The vos version is a Lean module, `Vos.Net`, opted in by the Pico 2 W target and by nobody else.

The boundary protocol is a bounded Ethernet frame. The CYW43439 side, after the blob is running, delivers frames. The Lean side never sees PIO, SPI, or SDPCM.

First slice, and the only one this plan treats as provable:

- Ethernet header, IPv4 header, UDP header.
- The IPv4 and UDP checksums match the ones defined on the bytes.
- One state machine: a UDP echo, or the bytes of a DHCP discover. A fixed input frame produces a fixed output frame.

TCP, TLS, and "joined this access point" are not in that slice. lneto's TCP exists and is a later port if the echo is real. It is not claimed here. The kernel must not import `Vos.Net`.

## What stays C or assembly

- Reset: stack, copy `.data`, zero `.bss`, set `VTOR`. Assembly.
- The vector table.
- The SysTick handler's loads and stores. On Cortex-M33 the hardware stacks the exception frame, so the handler body can be C. The Lean model is the specification that C is supposed to match.
- The linker script and whatever the RP2350 boot ROM requires before our reset runs. That is a boot stage, not a kernel theorem.
- The PIO program for the CYW43439 gSPI, and the hardware SPI shift for the SX126x. Both are C or PIO assembly. `exchange` is the Lean name; the shift is not.
- Copying the firmware blob into the download buffer. The blob is data. We do not disassemble it.

## The CYW43439 blob

The firmware source is not available. Infineon has said the Wi-Fi firmware source is proprietary and is not shared. The blob runs inside the CYW43439.

Two licences showed up when this note was written. They are not the same object:

- The C driver at [georgerobotics/cyw43-driver](https://github.com/georgerobotics/cyw43-driver) is MIT. `LICENSE` is the MIT text, copyright 2019–2026 George Robotics Pty Ltd, and `src/cyw43.h` says `SPDX-License-Identifier: MIT`. That is the driver source, not the blob.
- [soypat/cyw43439](https://github.com/soypat/cyw43439) is also MIT for the Go driver. The blobs under its `firmware/` directory (Wi-Fi about 224190 bytes, combined Wi-Fi and Bluetooth about 231077 bytes) sit next to `LICENSE-permissive-binary-license-1.0.lic`. That licence allows redistribution in binary form, without modification. It forbids reverse engineering, decompilation, and disassembly. It grants no patent licence for combinations that include the software, and it licences no hardware. The file, as fetched, does not name the copyright holder above the title.

Older packaging, including the `cyw43-firmware` crate's docs, described a George Robotics non-commercial licence and a separate Raspberry Pi Ltd licence limited to RP2040 and other chips produced by Raspberry Pi Ltd. The current driver repository's top-level `LICENSE` is the MIT text, and a fetch of `LICENSE.RP` from that repository returned 404. This note does not treat the blob as MIT.

vos will not commit the blob until a human puts the licence file beside it and accepts those terms. The blob is not rewritten, not disassembled, and not proved. Bluetooth, if it is ever switched on, needs its own licence check. BTstack as shipped by the Pico SDK has been a separate grant from the Wi-Fi blob. It is not part of the first image.

## Emulators

Nothing in this table was run for this note. No usable emulator found here runs the CYW43439 or its firmware. A Wi-Fi or Bluetooth result cannot be an emulator result until that changes. The SX126x is in the same position unless the emulator clocks a SPI slave, which none of these claim.

| Option | What it claims | CYW43439 | SX126x SPI | Run here |
| --- | --- | --- | --- | --- |
| Upstream QEMU | No RP2350 machine. `qemu-system-arm -M mps2-an385` is a Cortex-M3, which is what uvl's bundle test uses | no | no | not run |
| [QEMU RFC `2xs/qemu-rp2040-pico`](https://github.com/2xs/qemu-rp2040-pico) | RP2040, not RP2350. Not merged. Cover letter: general-purpose SPI is not implemented | no | no | not run |
| [picoem](https://github.com/0x4D44/picoem) `rp2350-emu` | Research emulator, Cortex-M33. UART, SPI, and I2C listed as stubs. Hazard3 out of scope | no | no | not run |
| [Lemur](https://github.com/lukaspirkl/Lemur) | Hazard3 on RP2350. Author: most peripherals are stubs | no | no | not run |
| [rp2350js](https://github.com/c1570/rp2350js) | RP2350, Hazard3 and a basic Cortex-M33. Some Pico examples, PIO, DMA | no | not established | not run |
| Renode wireless | IEEE 802.15.4 and BLE media. Not 802.11, not this chip | no | no | not run |

uvl remains the reference for the shape of a bare-metal Lean image. Its Pico firmware is the Pico SDK, and that README says it was not run on a board. The emulator line in `baremetal/tools/test.sh` is the Cortex-M3 board above. That was read, not run.

The first boot that can be claimed as a Pico 2 W is a serial log from a named emulator commit, or from a board. A generic Cortex-M3 run is labeled Cortex-M3. A fake SPI trace is labeled a fake SPI trace. Neither is the radio.

## Risks

- The blob is opaque and large. SRAM on the RP2350 is 520 KB. The pool is 96 KB. A 230 KB blob that is only copied out to the CYW43439 still has to sit in flash, and the download buffer has to sit in RAM while it is sent. The first image should not link `Vos.Net` and the blob at the same time until those sizes are measured.
- PIO gSPI is timing-sensitive. A model of SDPCM bytes does not show that the PIO program samples the wire correctly.
- M33 is not M3. A bundle that runs on `mps2-an385` can still be wrong on the RP2350 (boot ROM, XIP, TrustZone left on). TrustZone stays off in the first image: everything secure, no claim about the other world.
- One core. The second M33 and both Hazard3 cores stay reset. A theorem about core 0 says nothing about them.
- SX126x and the later SX1276 do not share a register map. One `exchange` and two codecs. Not one C function full of `#ifdef` inside the kernel.
- Proofs stop at the model. The C, the PIO program, the ROM, the blob, and both radios are trusted, not proved.

## Order

No target code until the ESP32-S3 work is merged and this note has an answer.

1. SysTick model and a C handler. Boot on `mps2-an385` and call it Cortex-M3, not a Pico.
2. RP2350 Cortex-M33 startup and linker script. UART trace. Install one emulator from the table, or say that none of them booted, and do not call a cross-compile a boot.
3. SX126x codec in Lean, host fake SPI. Hardware SPI C shim. No air.
4. CYW43439 framing in Lean (headers and a blob download of a given length), PIO gSPI in C or assembly, mock bus on the host. The blob is linked only with its licence file. No association, no DHCP, no air.
5. `Vos.Net`: Ethernet, IPv4, UDP, checksum theorems, one echo or one DHCP discover, against fake frames. The Pico target may import it. The kernel may not.
6. Later, same interfaces: RP2040 startup, and an SX1276 codec beside the SX126x codec. Hazard3 only after an emulator we have run executes it.

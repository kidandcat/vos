# Bare metal: `rp2350-riscv` first

The first bare-metal core is the RP2350's Hazard3 RISC-V, platform name `rp2350-riscv`. The Cortex-M33 is a later option. RP2040, and the SX1276 on the older doors, stay later still, behind the same HAL and the same radio interface.

What actually runs in this tree is not that chip. `target/rv32-virt` is a generic RV32 image linked at `0x80000000` and booted on QEMU's `virt` machine. Its serial line is `vos rv32: virt ok`. It is not an RP2350 boot. No RP2350 emulator was started. No CYW43439 firmware was fetched or committed, and no SX126x transaction was run.

The core stays the pure kernel. This target is opt-in. It must not be imported by `Vos.Sched`, `Vos.Queue`, or `Vos.Kernel`. VM and agent sandboxing stay in `Vos.Sandbox` and `Vos.Agent`. `scripts/check-firmware-boundary.sh` fails if a firmware bundle links those.

No FreeRTOS and no ESP-IDF.

## Hazard3 on the RP2350

Source: RP2350 datasheet, RP-008373-DS-3, section 3.8. The two cores are identical. Each socket holds either a Cortex-M33 or a Hazard3; the one not selected is held in reset. Cortex-M33 is the default at boot (section 3.9). Section 3.8 lists the standard extensions RP2350 enables:

- RV32I, M, A, C (also spelled Zca), Zba, Zbb, Zbs, Zbkb, Zcb, Zcmp, Zicsr
- Machine and User modes, PMP with eight NAPOT regions, debug

The same section's architecture string, preferred for GCC 14, is `rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp`. The table above that also lists Zifencei v2.0. Custom extensions in that section: Xh3power, Xh3bextm, Xh3irq, Xh3pmpm. `src/rp2_common/hardware_hazard3/include/hardware/hazard3/features.h` in the Pico SDK sets those four to version 1.0 when `PICO_RP2350` is set.

The timer is not an Arm SysTick. Datasheet section 3.1.8, "RISC-V platform timer": one 64-bit counter shared by both cores, `MTIME` and `MTIMEH` in the SIO block. Each core has its own `MTIMECMP` / `MTIMECMPH` at the same address. The interrupt is asserted, unsigned, while `MTIME ≥ MTIMECMP`. It drives `mip.mtip` on the RISC-V cores and `SIO_IRQ_MTIMECMP`. The Hazard3 manual (https://wren.wtf/hazard3/doc/, interrupt-request table) says the core's `timer_irq` pin is `mip.mtip` and should be wired to a standard `mtime`/`mtimecmp` peripheral. The generated register header `hardware/regs/rvcsr.h` in the Pico SDK names `mcause` code 7 as the timer IRQ. Xh3irq is the local controller for external system IRQs; it is not the machine timer.

The QEMU `virt` image uses the CLINT at `0x02000000`, not the SIO block. Same compare, different address. That is why the log says `virt` and not `rp2350`.

## Two buses, one radio interface

The CYW43439 on a Pico W / Pico 2 W is not on the hardware SPI block. The wiring is a PIO program that speaks a short gSPI. [soypat/cyw43439](https://github.com/soypat/cyw43439) is the pattern: a pure driver over that PIO bus. The chip's firmware, about 224 KB for Wi-Fi and about 231 KB for the combined Wi-Fi and Bluetooth image in that repository's embed file, is loaded into the CYW43439 and runs there. It does not run on the RP2350.

The SX126x is a normal SPI slave on a hardware SPI block, plus a busy pin and a DIO. It does not share the PIO program with the CYW43439.

Both radios sit behind one Lean interface: `exchange` takes a bounded byte string and returns one. SX126x commands are one codec. A later SX1276 codec is a second table, not a second interface. The CYW43439 is not that interface. It is a bus that, once the blob is loaded, yields Ethernet frames. Those frames enter a separate network module.

Pin numbers are not fixed in this note. The PR that writes the C copies them from the Pico 2 W schematic.

## What can be proved

The kernel tick is already a pure function. Around it:

- The machine timer, as a state and a step (`Vos.Arch.Mtime`). Pending while `cmp ≤ time`. `setCmp` to a later compare clears it. `advance` before the compare does not. `take` with a positive period counts one tick when the kernel is idle, and only increments `queued` when it is busy. `onTimer` applies that idle tick as one `Sched.tick`. Core 1 is outside the model. These are host theorems. They do not say the QEMU image implements them.
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
- A bundle that runs on QEMU `virt` can still be wrong on the RP2350 (boot ROM, XIP, SIO timer address). TrustZone is an Arm feature and is not this image.
- One Hazard3. The other Hazard3 stays reset. A theorem about core 0 says nothing about core 1, and nothing about the Cortex-M33 sockets, which the datasheet holds in reset when RISC-V is selected.
- SX126x and the later SX1276 do not share a register map. One `exchange` and two codecs. Not one C function full of `#ifdef` inside the kernel.
- Proofs stop at the model. The C, the PIO program, the ROM, the blob, and both radios are trusted, not proved.

## Order

1. Done in this tree, and not an RP2350: `Vos.Arch.Mtime` on the host, and `target/rv32-virt` on QEMU `virt` (`vos rv32: virt ok`).
2. Next: install one RP2350 emulator (picoem, Lemur, rp2350js, or another) and boot a Hazard3 image, or write down that none of them booted. Until that log exists, nothing is called `rp2350-riscv` at runtime.
3. SX126x codec in Lean, host fake SPI. Hardware SPI C shim on the real map. No air.
4. CYW43439 framing in Lean, PIO gSPI in C or assembly, mock bus on the host. The blob is linked only with its licence file. It is not committed in this change. No association, no DHCP, no air.
5. `Vos.Net`: Ethernet, IPv4, UDP, checksum theorems, one echo or one DHCP discover, against fake frames. The kernel may not import it.
6. Later, same interfaces: Cortex-M33 if a port wants it, RP2040 startup, and an SX1276 codec beside the SX126x codec.

# vos

A modular real-time kernel in Lean 4 (toolchain `v4.35.0`, the same as [uvl](https://github.com/kidandcat/uvl), [cairn](https://github.com/kidandcat/cairn) and [vlab](https://github.com/kidandcat/vlab)). Firmware and apps are meant to sit on this, including a later port of uvl's bare-metal UI and the Fecha door and gateway on ESP32-C3 and ESP32-S3. This repository does not replace FreeRTOS on those chips. On ESP32 the Lean kernel is one FreeRTOS task fed by an ESP-IDF queue. ESP32-C3 and ESP32-S3 are in this tree. Both were booted in QEMU, not on a board.

The model is a pure function over a fixed task table and fixed queue capacities. Nothing in the kernel path allocates a new slot or grows a queue past its capacity. Modules are opt-in at the import: `Vos.Queue` does not import the scheduler, `Vos.Sched` does not import queues, and `Vos.Kernel` is the layer that uses both. `Vos.Hal` is only the port record. A target that does not import a module does not refer to it.

The core stays small and standalone. It does not depend on a VM or on an AI-agent sandbox. That code, when it exists, lives under `Vos.Sandbox` or `Vos.Agent` and is imported only by a target that wants it. `Vos.lean` does not import it. `scripts/check-firmware-boundary.sh` fails if any other file under `Vos/` reaches those modules, and if the C bundled into the ESP32 images contains them. The same check covers `target/rp2040` and `target/rp2350` when those trees exist. A bare-metal plan that has not been built is in `docs/bare-metal.md`.

```bash
lake build
lake test
lake exe vos-demo
bash scripts/check-axioms.sh
bash scripts/check-firmware-boundary.sh
```

`lake test` prints `vos tests ok`. The demo prints `vos demo ok`.

## Trusted base

The proofs are about the Lean model. They trust:

- the Lean kernel, the compiler, and the runtime used to check and run the host tests
- classical reasoning that shows up as `Classical.choice` (from the list-length lemma and from `grind`), plus `propext` and `Quot.sound`

They do not trust, because those pieces are not in this repository: a C shim, ESP-IDF, FreeRTOS, hardware, or QEMU. There is no whole-firmware claim, and no claim that a later C build of this model implements the theorems.

`scripts/check-axioms.sh` prints the axioms of the theorems in the table below and fails on an incomplete proof or on any axiom outside that set. The library does not declare `axiom`, and the test sources do not use incomplete proofs.

## What is proved

Equal priority keeps the earlier ready-list entry. A delay of `0` is a yield. Tasks woken on the same tick are appended in index order, not earliest-deadline order. `Policy.priority` may preempt at a kernel step when a ready task is strictly more urgent. `Policy.cooperative` switches only when the running task yields, blocks, or exits.

| Theorem | Statement |
| --- | --- |
| `Spec.Queue.enq_accept`, `enq_reject` | A message is appended when `length < cap`, and otherwise the list is unchanged and the call reports rejection. |
| `Spec.Queue.enq_prefix` | An enqueue does not drop or reorder the messages already stored. |
| `Spec.Queue.deq_head` | Dequeue returns the head and leaves the tail. |
| `Spec.Queue.pushAll_append`, `fifo` | A list that fits is stored in order, and draining that many messages returns that same list once. |
| `Queue.length_le` | Every queue value has `length ≤ cap`. |
| `Sched.empty_inv`, `spawn_inv`, `yield_inv`, `block_inv`, `unblock_inv`, `delay_inv`, `exit_inv`, `dispatch_inv`, `wakeDue_inv`, `tick_inv` | Each of these steps stays inside `Inv`. |
| `Sched.ready_bounded` | The ready list is no longer than the task table. |
| `Sched.blocked_not_current` | A blocked task is not current. |
| `Sched.dispatch_not_blocked` | The task `dispatch` selects was already current or was ready, so it was not blocked. |
| `Sched.priority_max` | After a priority dispatch, every ready task has priority ≤ the running task. |
| `Sched.coop_yield_runs_head` | A cooperative yield runs the task that was at the head of the ready list. |
| `Sched.delay_blocks` | `delay dt` with `dt ≠ 0` blocks the running task until `now + dt` and does not leave it current. |
| `Sched.ticks_before_deadline` | For every `k` with `now + k` still before the deadline, that task is still blocked. |
| `Kernel.send_room` | A send into a non-full queue with no waiting receiver appends one message and does not change the scheduler. |
| `Kernel.send_to_waiter` | A send into an empty queue with a waiting receiver delivers that message to the oldest waiter's inbox and leaves the queue empty. |
| `Kernel.send_full` | A send into a full queue leaves the queue unchanged, stores the message in the sender's single pending slot, blocks the sender, and preserves `Inv`. |
| `Kernel.recv_head` | A receive with no waiting sender returns the head and leaves the tail. |
| `Kernel.recv_empty` | A receive on an empty queue returns nothing, blocks the receiver, and preserves `Inv`. |
| `Sched.unblock_readies` | Unblocking a blocked task makes it alive and either ready or current, and preserves `Inv`. |
| `Kernel.send_readies_waiter` | A send into an empty queue readies the oldest blocked receiver through `unblock`. The receiver is alive and either ready or current. |
| `Timer.ticks_before` | An active timer that is not yet due stays inactive-as-a-fire for every `k` with `now + k` still before the deadline: `due` stays false and the deadline does not move. |
| `Timer.fires_at` | The tick that reaches a one-shot deadline sets `due` and clears `active`. |
| `Timer.periodic_next` | A periodic fire sets `due` and arms the next deadline at `deadline + period`, which is strictly later. |
| `Sem.count_bound`, `waiters_bounded` | `count ≤ max` for every semaphore. A duplicate-free waiter list is no longer than the task table. |
| `Sem.give_incs`, `give_saturated` | With no waiter, `give` increments below `max` and refuses at `max`. |
| `Sem.give_wakes` | `give` to a blocked waiter leaves `count` unchanged and readies that waiter. |
| `Sem.take_decs`, `take_blocks` | `take` decrements a positive count. `take` at 0 blocks the caller and keeps the count at 0. |
| `Sem.give_keeps_token`, `take_keeps_token` | If the waiter list is empty or the count is 0, `give` (when it fits) and `take` leave that disjunction true. |
| `Mutex.at_most_one` | Every mutex state has at most one owner. This one has no axioms. |
| `Mutex.lock_takes`, `lock_blocks` | Locking a free mutex stores the caller. Locking a mutex another task holds leaves that owner in place and blocks the caller. |
| `Mutex.unlock_foreign`, `unlock_frees` | Unlock by a non-owner does nothing. Unlock by the owner with no waiter clears the owner. |
| `Mutex.unlock_passes` | Unlock by the owner passes the mutex to the oldest blocked waiter and readies that waiter. The resulting state still has at most one owner. |
| `Event.set_no_clear`, `set_only` | Setting bits does not clear a bit that was set, and does not change a bit outside the mask. |
| `Event.clear_only`, `clear_bit` | Clearing bits does not change a bit outside the mask, and clears a bit inside it. |
| `Event.set_keeps_waiter` | A sole waiter whose mask is still unsatisfied stays on the list, and the scheduler is unchanged. |
| `Event.set_wakes` | A sole blocked waiter whose mask becomes satisfied leaves the list and is readied. |

`#print axioms` on these reports only `propext`, `Quot.sound`, and, where the proof uses the list-length lemma or `grind`, `Classical.choice`. `Queue.length_le` and `Mutex.at_most_one` have no axioms.

Not proved: that the cooperative policy is starvation-free for an arbitrary task program. The yield theorem is one step. Not proved: priority inheritance, a recursive mutex, or that a timer callback is a function. The timer's fire is the `due` bit. Not proved: anything about the C compiler, the runtime, interrupts, or devices.

## What is tested

`lake test` runs on the host, with `Sched.now` as the only clock.

- The queue spec: three messages drain in order, a fourth is rejected, capacity 0 rejects.
- The wrapper queue against a ring buffer, 300 random push/pop steps, seed `7`, capacity 5. The lists matched. The ring is test code. It is not the kernel and it is not proved.
- Priority: tasks of priority 1, 3, 2, and the running task is 3, then 2, then 1 as each blocks.
- Cooperative: a higher priority does not preempt; yield runs the ready head, then the previous task.
- Delay 3 on the only task: still blocked at `now = 2`, running at `now = 3`.
- Kernel: the demo below, a full queue of capacity 1 that holds the second message in `pending` and releases it on the next receive, and a blocked receiver that becomes current when a higher-priority send wakes it.
- Timers: a one-shot of 3 ticks is not due at `now = 2` and is due at `now = 3`. A period of 2, after the first fire, is not due again on the next tick.
- Semaphores: count 0, 1, 2 against max 2, a third `give` refused, `take` to 0 blocks, `give` wakes with the count still 0. Then 80 non-blocking give/take steps, seed 11, max 3, against a separate counter. The counts matched.
- Mutex: task 0 locks, task 1's lock leaves the owner at 0 and blocks task 1, task 0's unlock stores owner 1 and marks task 1 alive. Unlock by the non-owner does not change the owner.
- Events: a waiter for bit 0 stays blocked when bit 1 is set, and is readied when bit 0 is set. Bit 1 stays set.
- The C3 demo as a pure function (`Vos.Target.C3Demo.trace`): codes `[1, 2, 4]` for start, one tick, two ticks.
- Differential: `Tests.Ref` is a second scheduler on arrays and `Nat` indexes. Both policies, seeds `1`, `42`, `99`, `2026`, 200 steps each, 4 tasks. The current task, ready list, clock, park, priority, delay flag, and deadline agreed at every step. A mismatch fails the test. This is not a proof that the reference is the spec.

The same demo, compiled to C with the vendored single-threaded runtime and linked into an ESP-IDF image, was booted in QEMU on `esp32c3` and `esp32s3`. See below. That run is a test of the shim and the generated C. It is not a proof, and it is not a physical board.

`lake exe vos-demo` is the same two-task script the test calls `demoOk`: priority 1 and 5, send `41`, delay 2, the low-priority task receives `41`, the high-priority task is still blocked at `now = 1` and running at `now = 2`.

## What is not verified

- A physical ESP32-C3 or ESP32-S3. Both images below were booted in QEMU only.
- RP2040 and uvl's bare-metal target.
- The GPIO level. The shim calls the IDF driver (`gpio_config`, `gpio_set_level`, `gpio_get_level` on pin 4). Under QEMU `esp32c3` and `esp32s3` the readback was 0 after a set to 1. The log says `hal gpio level unread`. The pin was not checked.
- SPI, I2C, and the radio hook. No slave and no peer is attached in this QEMU command, so a transfer cannot be checked. Those three return -1 and the log says `stub`.
- Priority inheritance, recursive locking, and timer callbacks as functions. The sync objects above are the model, not those FreeRTOS extras.
- Drivers, radio, WiFi, BLE, TLS, MQTT, and the Fecha protocol. Those are not this kernel.
- That compiling this Lean code to C preserves the theorems. The QEMU run shows this one demo produced the same three lines as the host bundle. It does not show that every theorem survives the compiler.

## Targets

The portable core is `Sched`, `Queue`, and `Kernel`. A target supplies a clock and, later, the shims behind `Vos.Hal`.

| Target | Role | In this tree |
| --- | --- | --- |
| `host` | Deterministic clock for tests and proofs. | Runs. |
| ESP32-C3 | One FreeRTOS task (`app_main`) runs the Lean step. An `esp_timer` callback posts ticks on an ESP-IDF queue and does not enter the kernel. | Builds. Booted in QEMU `esp32c3`, not on a board. |
| ESP32-S3 | Same demo and the same shim, Xtensa toolchain. | Builds. Booted in QEMU `esp32s3`, not on a board. |
| RP2040, RP2350 | Bare metal. No FreeRTOS and no ESP-IDF. Plan only. | Not started. See `docs/bare-metal.md`. |

## Runtime

Host tests (`lake test`, `lake exe vos-demo`) use the ordinary Lean runtime. They do not link `libleanrt`.

The ESP32-C3 and ESP32-S3 images do not link `libleanrt` either. They link the same bundle. `target/c3/rt/uvl_rt.c` and `target/c3/include/lean/config.h` are byte-identical to [uvl](https://github.com/kidandcat/uvl) `ff2f323` (`baremetal/rt/uvl_rt.c`, `baremetal/include/lean/config.h`). `target/c3/SHA256SUMS` is checked by `target/esp32c3/run-qemu.sh`. `target/c3/include/uvl.h` is not that header: the runtime includes the name, and this file is only the heap-stats struct and the panic hook it actually uses. `target/c3/bundle.py` is the reachable-initializer loop from uvl's `uvl_bundle.py`, with vos entry points instead of the glyph table and the UVL shell.

uvl's bare-metal runtime (`baremetal/rt/uvl_rt.c` at the commit vlab pins, `ff2f323`) is a static pool, reference counting, no threads, no `Task`. That is the runtime a later vos image should use, because this kernel is also single-threaded: one loop, no shared Lean objects across threads, so the counters do not need to be atomic.

The durable fix is still a small repository both uvl and vos pin. These two files are the copy, with the hash, and they are not edited here.

## Layout

```
Vos/Spec/Queue.lean    list model: capacity, FIFO, no loss, no duplication
Vos/Spec/Sched.lean    the scheduler properties as propositions
Vos/Queue.lean         queue value that carries the capacity proof
Vos/Sched.lean         cooperative and priority scheduler
Vos/Kernel.lean        send and receive on top of both
Vos/Timer.lean         one-shot and periodic timers
Vos/Sem.lean           counting semaphores
Vos/Mutex.lean         non-recursive mutex
Vos/Event.lean         32 event flags
Vos/Spec/Sync.lean     names for the sync properties
Vos/Hal/Port.lean      target capabilities
Vos/Sandbox/           VM and agent sandbox; the core does not import it
docs/bare-metal.md     RP2040 / RP2350 plan; nothing there is built
Vos/Host/Sim.lean      host clock and the demo script
Vos/Target/C3Demo.lean pure demo exported to C
Vos/Target/Size/       footprint probes, one module each
target/c3/             runtime, bundler, host harness
target/idf/            shared ESP-IDF shim (HAL, app_main)
target/esp32c3/        C3 project and QEMU script
target/esp32s3/        S3 project and QEMU script
Tests/Ref.lean         the second scheduler used by the differential test
```

## ESP32-C3

`app_main` is the only task that calls Lean. It blocks on an ESP-IDF queue. An `esp_timer` callback posts a tick (`2`) and does not call Lean. One start event (`1`) is posted before the loop. The Lean side is `Vos.Target.C3Demo`: two tasks (priorities 1 and 5), one queue, one one-shot timer of 2 ticks. The return codes are `1` (sent 41, low task has it, timer armed), `2` (after one tick the timer is not due), `4` (after two ticks the timer is due and the high-priority task is current).

```bash
bash target/esp32c3/setup-tools.sh   # once: IDF v5.4.4, both QEMU builds, cmake, ninja
bash target/esp32c3/run-qemu.sh      # first run also emits C for Lean's Init
bash target/esp32s3/run-qemu.sh
bash target/esp/measure-modules.sh   # per-module text/data/bss, not the IDF image
```

`install.sh` does not always leave `cmake` and `ninja` on `PATH`. `setup-tools.sh` installs the distro packages `cmake` and `ninja-build` when `sudo` is available, and it exits if either command is still missing. `idf.py` will not configure without them.

The toolchain ships `Init` as host objects. `run-qemu.sh` writes C for those modules to `.lake/c3/init-c` once per toolchain (`target/c3/gen_init_c.sh`), then the bundler keeps the ones the demo reaches. That directory is not in git.

Checked on this machine, not on a board. ESP-IDF v5.4.4, `riscv32-esp-elf-gcc` 14.2 and `xtensa-esp-elf-gcc` 14.2, QEMU `esp-develop-9.2.2-20260417`.

The serial log on each machine, in order, contained `hal uart ok`, `hal nvs ok`, `hal gpio level unread 0`, `hal spi stub`, `hal i2c stub`, `hal radio stub`, then `sent 41`, `timer not due`, `demo ok`, then `main_task: Returned from app_main()`. No `hal fail`, no `vos c3: fail` or `vos s3: fail`, and no fatal panic.

UART is `uart_write_bytes` on UART0. NVS stores the byte `0xA5` under the key `probe` in namespace `vos` and reads it back. GPIO calls the driver; the level did not come back. SPI, I2C, and radio stay stubs.

### Image size

These are one link of the whole ESP-IDF image, the vos pool included (96 KiB, `UVL_HEAP_SIZE`). They are not a chip measurement. `idf.py size` is the memory map. `*-elf-size` is the raw ELF, and its columns do not match that map (it folds `.rodata` into `data`, and its `bss` is larger than the DRAM `.bss` the map reports). The `.bin` length is the app file, which is padded above `idf.py size`'s "total image size".

An earlier C3 link, before these HAL drivers, was reported as `data` 40368 and `.bin` 253776. Other builds of that same image came out `data` 40376 and 40384, `.bin` 253792. That is 8 or 16 bytes. Treat the byte count as approximate: the number is the whole IDF link, and the app image pads flash segments to 16 bytes. The table below is this tree, with the UART, NVS, and GPIO drivers linked, so it is larger than that earlier image.

| | C3 | S3 |
| --- | ---: | ---: |
| `idf.py size` total image | 305036 | 308772 |
| app `.bin` bytes | 305152 | 308896 |
| flash code (`.text`) | 202570 | 185982 |
| flash data | 40336 | 45604 |
| RAM used | 164622 DRAM | 161791 DIRAM |
| of which `.data` | 6092 | 12152 |
| of which `.bss` | 102520 | 101016 |
| of which executable in RAM | 56010 DRAM `.text` | 48623 DIRAM `.text`, plus 16383 IRAM |
| `*-elf-size` text / data / bss | 258836 / 46200 / 421326 | 251244 / 57528 / 608417 |

The 96 KiB pool is inside the `.bss` figure. C3 has no separate IRAM row in `idf.py size`; the executable RAM it reports is DRAM `.text`.

### What each module adds

`target/esp/measure-modules.sh` bundles one exported probe, then links that C with the chip gcc and `--gc-sections`. The harness calls `uvl_heap_alloc` so the 98304-byte pool is in every row, including `empty`. The delta is against `empty`. It includes Init code that the probe references and `empty` does not. It does not include ESP-IDF. Sem, mutex, and event import the scheduler, so their delta includes `Vos.Sched`. Kernel imports the queue and the scheduler.

| probe | opt-in | C3 text | C3 Δtext | C3 Δdata | C3 Δbss | S3 text | S3 Δtext | S3 Δdata | S3 Δbss |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| empty | prelude | 1728 | 0 | 0 | 0 | 1031 | 0 | 0 | 0 |
| queue | `Vos.Queue` | 11374 | 9646 | 12 | 24 | 8903 | 7872 | 0 | 24 |
| sched | `Vos.Sched` | 26738 | 25010 | 36 | 60 | 21859 | 20828 | 0 | 64 |
| kernel | `Vos.Kernel` (and Queue, Sched) | 56274 | 54546 | 48 | 60 | 46875 | 45844 | 0 | 64 |
| timer | `Vos.Timer` | 13362 | 11634 | 44 | 60 | 11023 | 9992 | 4 | 64 |
| sem | `Vos.Sem` (and Sched) | 31966 | 30238 | 36 | 48 | 26491 | 25460 | 0 | 48 |
| mutex | `Vos.Mutex` (and Sched) | 33962 | 32234 | 52 | 72 | 28319 | 27288 | 0 | 72 |
| event | `Vos.Event` (and Sched) | 32512 | 30784 | 60 | 84 | 27003 | 25972 | 0 | 88 |

CI runs `target/esp32c3/run-qemu.sh`, `target/esp32s3/run-qemu.sh`, and `target/esp/measure-modules.sh` in the `qemu` job. If that job cannot install IDF or QEMU, those scripts are the reproduction. The proofs do not depend on it.

# vos

A modular real-time kernel in Lean 4 (toolchain `v4.35.0`, the same as [uvl](https://github.com/kidandcat/uvl), [cairn](https://github.com/kidandcat/cairn) and [vlab](https://github.com/kidandcat/vlab)). Firmware and apps are meant to sit on this, including a later port of uvl's bare-metal UI and the Fecha door and gateway on ESP32-C3 and ESP32-S3. This repository does not replace FreeRTOS on those chips. On ESP32 the Lean kernel is one FreeRTOS task fed by an ESP-IDF queue. That target is not in this tree yet.

The model is a pure function over a fixed task table and fixed queue capacities. Nothing in the kernel path allocates a new slot or grows a queue past its capacity. Modules are opt-in at the import: `Vos.Queue` does not import the scheduler, `Vos.Sched` does not import queues, and `Vos.Kernel` is the layer that uses both. `Vos.Hal` is only the port record. A target that does not import a module does not refer to it.

```bash
lake build
lake test
lake exe vos-demo
bash scripts/check-axioms.sh
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
- Differential: `Tests.Ref` is a second scheduler on arrays and `Nat` indexes. Both policies, seeds `1`, `42`, `99`, `2026`, 200 steps each, 4 tasks. The current task, ready list, clock, park, priority, delay flag, and deadline agreed at every step. A mismatch fails the test. This is not a proof that the reference is the spec.

`lake exe vos-demo` is the same two-task script the test calls `demoOk`: priority 1 and 5, send `41`, delay 2, the low-priority task receives `41`, the high-priority task is still blocked at `now = 1` and running at `now = 2`.

## What is not verified

- ESP32-C3, ESP32-S3, RP2040, and uvl's bare-metal target. `Vos.Hal.Port` names the capabilities a port will report (`time`, tick interrupt, GPIO, SPI, I2C, UART, storage, radio). Only `Vos.Hal.host` exists. No register, no interrupt handler, no C shim.
- QEMU. Nothing here was booted.
- Flash and RAM. No image was linked, so there is no footprint number in this repository.
- Priority inheritance, recursive locking, and timer callbacks as functions. The sync objects above are the model, not those FreeRTOS extras.
- Drivers, radio, WiFi, BLE, TLS, MQTT, and the Fecha protocol. Those are not this kernel.
- That compiling this Lean code to C preserves the theorems.

## Targets

The portable core is `Sched`, `Queue`, and `Kernel`. A target supplies a clock and, later, the shims behind `Vos.Hal`.

| Target | Role | In this tree |
| --- | --- | --- |
| `host` | Deterministic clock for tests and proofs. | Runs. |
| ESP32-C3, ESP32-S3 | One FreeRTOS task runs the Lean step; an ESP-IDF queue delivers events. Thin C shim. | Not started. |
| RP2040, uvl bare metal | Same core, different port. | Not started. Adding one does not require a change to `Sched` or `Queue`. |

## Runtime

Host tests use the ordinary Lean runtime. They do not link `libleanrt` and they do not vendor uvl's runtime.

uvl's bare-metal runtime (`baremetal/rt/uvl_rt.c` at the commit vlab pins, `ff2f323`) is a static pool, reference counting, no threads, no `Task`. That is the runtime a later vos image should use, because this kernel is also single-threaded: one loop, no shared Lean objects across threads, so the counters do not need to be atomic.

Do not fork that file inside vos and edit it. The durable fix is a small repository both uvl and vos pin, containing `uvl_rt.c`, the 32-bit `config.h`, and the bundler. vos cannot make that change in uvl from here. Until that repository exists, an ESP target in vos should copy those files once, record the hash, and not modify them. This PR does not copy them, and it does not repeat the earlier size note for a different Lean module as if it were a vos measurement.

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
Vos/Host/Sim.lean      host clock and the demo script
Tests/Ref.lean         the second scheduler used by the differential test
```

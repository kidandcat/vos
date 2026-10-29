import Vos.Sched

/-!
RISC-V machine timer, as a state machine.

This is the `mtime` / `mtimecmp` compare from the privileged specification:
the interrupt is pending while `cmp ≤ time`. It is the same compare the
RP2350 datasheet describes for the SIO platform timer (section 3.1.8). The
model does not mention a bus address. The QEMU `virt` image and a future
Hazard3 image are separate transcriptions of `take`.
-/
namespace Vos.Arch.Mtime

open Vos.Sched

structure Clock where
  time : Nat
  cmp : Nat
  mtie : Bool
  mie : Bool
  /-- The kernel is already inside a step. A timer trap is counted, not applied. -/
  busy : Bool
  queued : Nat
  ticks : Nat
  deriving DecidableEq, Repr

def pending (c : Clock) : Bool := decide (c.cmp ≤ c.time)

def armed (c : Clock) : Bool := pending c && c.mtie && c.mie

def advance (c : Clock) (dt : Nat) : Clock :=
  { c with time := c.time + dt }

def setCmp (c : Clock) (cmp : Nat) : Clock :=
  { c with cmp := cmp }

/-- One handler step. A positive `period` moves `cmp` to `time + period`,
which drops `pending`. A busy kernel only increments `queued`. -/
def take (c : Clock) (period : Nat) : Clock :=
  if armed c then
    let c := { c with cmp := c.time + period }
    if c.busy then { c with queued := c.queued + 1 }
    else { c with ticks := c.ticks + 1 }
  else
    c

/-- Apply a taken tick to the scheduler only when the kernel is idle. -/
def onTimer {n : Nat} (c : Clock) (s : Sched n) (p : Policy) (period : Nat) :
    Clock × Sched n :=
  match armed c, c.busy with
  | true, false => (take c period, Sched.tick s p)
  | _, _ => (take c period, s)

theorem pending_iff (c : Clock) : pending c = true ↔ c.cmp ≤ c.time := by
  simp [pending]

theorem setCmp_clears (c : Clock) (cmp : Nat) (h : c.time < cmp) :
    pending (setCmp c cmp) = false := by
  have hnot : ¬ cmp ≤ c.time := Nat.not_le_of_gt h
  simp [pending, setCmp, hnot]

theorem advance_before (c : Clock) (dt : Nat) (h : c.time + dt < c.cmp) :
    pending (advance c dt) = false ∧ (advance c dt).cmp = c.cmp := by
  have hnot : ¬ c.cmp ≤ c.time + dt := Nat.not_le_of_gt h
  simp [pending, advance, hnot]

theorem take_idle (c : Clock) (period : Nat) (h : armed c = false) :
    take c period = c := by
  simp [take, h]

theorem take_ticks (c : Clock) (period : Nat) (ha : armed c = true) (hb : c.busy = false)
    (hp : 0 < period) :
    (take c period).ticks = c.ticks + 1 ∧ pending (take c period) = false := by
  unfold take
  simp [ha, hb]
  have hnot : ¬ c.time + period ≤ c.time := Nat.not_le_of_gt (Nat.lt_add_of_pos_right hp)
  simp [pending, hnot]

theorem take_queues (c : Clock) (period : Nat) (ha : armed c = true) (hb : c.busy = true) :
    (take c period).ticks = c.ticks ∧ (take c period).queued = c.queued + 1 := by
  unfold take
  simp [ha, hb]

theorem onTimer_applies {n : Nat} (c : Clock) (s : Sched n) (p : Policy) (period : Nat)
    (ha : armed c = true) (hb : c.busy = false) (hp : 0 < period) (hinv : Inv s) :
    (onTimer c s p period).1.ticks = c.ticks + 1 ∧
      (onTimer c s p period).2 = Sched.tick s p ∧
      Inv (onTimer c s p period).2 := by
  unfold onTimer
  rw [ha, hb]
  dsimp
  refine ⟨(take_ticks c period ha hb hp).1, rfl, tick_inv s hinv p⟩

end Vos.Arch.Mtime

/-!
Software timers. A timer is a slot with a deadline, not a callback.

`period = 0` is one-shot: the tick that reaches the deadline sets `due` and
clears `active`. A positive period sets `due` and moves the deadline forward
by `period`. `due` stays set until `takeDue`. Nothing here allocates.
-/
namespace Vos.Timer

structure Tmr where
  deadline : Nat
  period : Nat
  active : Bool
  due : Bool
  deriving DecidableEq, Repr

def Tmr.idle : Tmr where
  deadline := 0
  period := 0
  active := false
  due := false

structure Timers (n : Nat) where
  slot : Fin n → Tmr
  now : Nat

def Timers.empty (n : Nat) : Timers n where
  slot := fun _ => Tmr.idle
  now := 0

def start {n : Nat} (ts : Timers n) (i : Fin n) (dt period : Nat) : Timers n where
  slot := fun j =>
    if j = i then { deadline := ts.now + dt, period := period, active := true, due := false }
    else ts.slot j
  now := ts.now

def takeDue {n : Nat} (ts : Timers n) (i : Fin n) : Timers n × Bool :=
  let t := ts.slot i
  if t.due then
    ({ ts with slot := fun j => if j = i then { t with due := false } else ts.slot j }, true)
  else
    (ts, false)

/-- One slot, given the current tick. Other slots are untouched. -/
def stepSlot (now : Nat) (t : Tmr) : Tmr :=
  if t.active && decide (t.deadline ≤ now) then
    if t.period = 0 then { t with active := false, due := true }
    else { t with due := true, deadline := t.deadline + t.period }
  else t

def fireDue {n : Nat} (ts : Timers n) : Timers n where
  slot := fun i => stepSlot ts.now (ts.slot i)
  now := ts.now

def tick {n : Nat} (ts : Timers n) : Timers n :=
  fireDue { ts with now := ts.now + 1 }

def afterTicks {n : Nat} (ts : Timers n) : Nat → Timers n
  | 0 => ts
  | k + 1 => afterTicks (tick ts) k

variable {n : Nat}

theorem stepSlot_early (now : Nat) (t : Tmr) (hearly : now < t.deadline) : stepSlot now t = t := by
  have hnot : ¬ t.deadline ≤ now := by omega
  simp [stepSlot, hnot]

theorem fireDue_keeps (ts : Timers n) (i : Fin n) (hearly : ts.now < (ts.slot i).deadline) :
    (fireDue ts).slot i = ts.slot i ∧ (fireDue ts).now = ts.now := by
  simp [fireDue, stepSlot_early ts.now (ts.slot i) hearly]

/-- While `now + k` is still before the deadline, the timer has not fired. -/
theorem ticks_before (ts : Timers n) (i : Fin n) (k : Nat)
    (hact : (ts.slot i).active = true) (hdue : (ts.slot i).due = false)
    (hearly : ts.now + k < (ts.slot i).deadline) :
    ((afterTicks ts k).slot i).active = true ∧ ((afterTicks ts k).slot i).due = false ∧
      ((afterTicks ts k).slot i).deadline = (ts.slot i).deadline ∧
      (afterTicks ts k).now = ts.now + k := by
  induction k generalizing ts with
  | zero =>
    simp [afterTicks, Nat.add_zero, hact, hdue]
  | succ k ih =>
    have hstep : ts.now + 1 < (ts.slot i).deadline := by omega
    have hk := fireDue_keeps { ts with now := ts.now + 1 } i (by simpa using hstep)
    have htick_slot : (tick ts).slot i = ts.slot i := by simpa [tick] using hk.1
    have htick_now : (tick ts).now = ts.now + 1 := by simpa [tick] using hk.2
    have hearly' : (tick ts).now + k < ((tick ts).slot i).deadline := by
      rw [htick_slot, htick_now]
      omega
    have ih' := ih (tick ts) (by simpa [htick_slot] using hact) (by simpa [htick_slot] using hdue) hearly'
    refine ⟨?_, ?_, ?_, ?_⟩
    · simpa [afterTicks, htick_slot] using ih'.1
    · simpa [afterTicks, htick_slot] using ih'.2.1
    · simpa [afterTicks, htick_slot] using ih'.2.2.1
    · have hnow := ih'.2.2.2
      simp [afterTicks] at hnow ⊢
      omega

theorem stepSlot_oneshot (now : Nat) (t : Tmr)
    (hact : t.active = true) (hper : t.period = 0) (hdue : t.deadline ≤ now) :
    stepSlot now t = { t with active := false, due := true } := by
  simp [stepSlot, hact, hper, hdue]

theorem stepSlot_periodic (now : Nat) (t : Tmr)
    (hact : t.active = true) (hper : t.period ≠ 0) (hdue : t.deadline ≤ now) :
    stepSlot now t = { t with due := true, deadline := t.deadline + t.period } := by
  simp [stepSlot, hact, hper, hdue]

/-- The tick that reaches a one-shot deadline sets `due` and stops the timer. -/
theorem fires_at (ts : Timers n) (i : Fin n)
    (hact : (ts.slot i).active = true) (hper : (ts.slot i).period = 0)
    (hdead : (ts.slot i).deadline = ts.now + 1) :
    ((tick ts).slot i).due = true ∧ ((tick ts).slot i).active = false ∧
      (tick ts).now = ts.now + 1 := by
  have hfire := stepSlot_oneshot (ts.now + 1) (ts.slot i) hact hper (by omega)
  simp [tick, fireDue, hfire]

/-- A periodic fire arms the next deadline `period` ticks later, not sooner. -/
theorem periodic_next (ts : Timers n) (i : Fin n)
    (hact : (ts.slot i).active = true) (hper : (ts.slot i).period ≠ 0)
    (hdead : (ts.slot i).deadline = ts.now + 1) :
    ((tick ts).slot i).due = true ∧ ((tick ts).slot i).active = true ∧
      ((tick ts).slot i).deadline = (ts.slot i).deadline + (ts.slot i).period ∧
      (ts.slot i).deadline < ((tick ts).slot i).deadline := by
  have hfire := stepSlot_periodic (ts.now + 1) (ts.slot i) hact hper (by omega)
  have hpos : 0 < (ts.slot i).period := by omega
  simp [tick, fireDue, hfire, hact]
  omega

end Vos.Timer

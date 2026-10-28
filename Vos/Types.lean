/-!
The scheduler state the rest of the kernel is stated against.

A task's phase is derived. `park` records what it is when it is neither
running nor ready: unused, blocked, or terminated. An allocated task that
may be scheduled has `park = alive`. The invariant says an alive task is
in the ready list or is current, and a blocked, unused, or terminated task
is neither.

There are `n` slots. The ready list is a duplicate-free list of those slots,
so it cannot grow past `n`. Nothing in this model allocates a new slot.
-/
namespace Vos

inductive Park where
  | unused
  | alive
  | blocked
  | terminated
  deriving DecidableEq, Repr, BEq, Inhabited

instance : LawfulBEq Park where
  eq_of_beq {a b} h := by
    cases a <;> cases b
    all_goals first | rfl | cases h
  rfl {a} := by cases a <;> rfl

inductive Phase where
  | unused
  | ready
  | running
  | blocked
  | terminated
  deriving DecidableEq, Repr, BEq

/-- Higher `prio` is more urgent. Equal priorities keep ready-list order. -/
abbrev Prio := Nat

inductive Policy where
  | cooperative
  | priority
  deriving DecidableEq, Repr, BEq

/-- `n` task slots, a ready list in arrival order, and one optional current task. -/
structure Sched (n : Nat) where
  park : Fin n → Park
  prio : Fin n → Prio
  deadline : Fin n → Nat
  onDelay : Fin n → Bool
  ready : List (Fin n)
  current : Option (Fin n)
  now : Nat

def Sched.empty (n : Nat) : Sched n where
  park := fun _ => .unused
  prio := fun _ => 0
  deadline := fun _ => 0
  onDelay := fun _ => false
  ready := []
  current := none
  now := 0

/-- Derived phase. `park = alive` is only read if the task is neither current
nor ready; the invariant says that case does not occur. -/
def phase {n : Nat} (s : Sched n) (i : Fin n) : Phase :=
  if s.current = some i then
    .running
  else if s.ready.contains i then
    .ready
  else
    match s.park i with
    | .unused => .unused
    | .alive => .ready
    | .blocked => .blocked
    | .terminated => .terminated

/-- What every scheduler operation preserves. -/
structure Inv {n : Nat} (s : Sched n) : Prop where
  ready_nodup : s.ready.Nodup
  current_not_ready : ∀ i, s.current = some i → i ∉ s.ready
  current_alive : ∀ i, s.current = some i → s.park i = .alive
  alive_live : ∀ i, s.park i = .alive → i ∈ s.ready ∨ s.current = some i
  blocked_idle : ∀ i, s.park i = .blocked → i ∉ s.ready ∧ s.current ≠ some i
  unused_idle : ∀ i, s.park i = .unused → i ∉ s.ready ∧ s.current ≠ some i
  terminated_idle : ∀ i, s.park i = .terminated → i ∉ s.ready ∧ s.current ≠ some i
  delay_blocked : ∀ i, s.onDelay i = true → s.park i = .blocked

end Vos

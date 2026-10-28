import Vos.Types

/-!
Properties of a scheduler state. Operations in `Vos.Sched` are proved
against these statements.

`priorityMax` is required of the state *after* a priority dispatch: the
running task is at least as urgent as every ready task. It is not required
of a cooperative schedule, where a low-priority task keeps the processor
until it yields or blocks.

`notBefore` says a task waiting on a delay is still blocked while `now` is
strictly before its deadline. `Vos.Sched.ticks_before_deadline` is the
statement that advancing the clock does not break this.
-/
namespace Vos.Spec.Sched

open Vos

/-- The current task is running, so it is not blocked, unused, terminated, or merely ready. -/
def currentRunning {n : Nat} (s : Sched n) : Prop :=
  ∀ i, s.current = some i → phase s i = .running

/-- A blocked task is not the one the scheduler is running. -/
def notBlocked {n : Nat} (s : Sched n) : Prop :=
  ∀ i, phase s i = .blocked → s.current ≠ some i

/-- Among ready tasks, none is strictly more urgent than the running task. -/
def priorityMax {n : Nat} (s : Sched n) : Prop :=
  ∀ c, s.current = some c → ∀ i, phase s i = .ready → s.prio i ≤ s.prio c

/-- The ready list fits in the task table. -/
def readyBounded {n : Nat} (s : Sched n) : Prop :=
  s.ready.length ≤ n

/-- A delay has not come due yet, so the task is still blocked. -/
def notBefore {n : Nat} (s : Sched n) : Prop :=
  ∀ i, s.onDelay i = true → s.now < s.deadline i → phase s i = .blocked

end Vos.Spec.Sched

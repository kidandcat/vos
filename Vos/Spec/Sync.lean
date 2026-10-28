import Vos.Event
import Vos.Mutex
import Vos.Sem
import Vos.Timer

/-!
Statements the sync modules are proved against. The theorems live next to
the operations. This module names the properties.
-/
namespace Vos.Spec.Sync

/-- A semaphore value never stores more tokens than `max`. -/
abbrev semBound {nt : Nat} (sem : Vos.Sem.Sem nt) : Prop := Vos.Sem.CountBound sem

/-- A mutex state has at most one owner. -/
abbrev mutexExcl {nt : Nat} (m : Vos.Mutex.Mutex nt) : Prop := Vos.Mutex.Exclusive m

/-- An active timer that is not yet due stays that way while `now` is before the deadline. -/
def timerNotBefore {n : Nat} (ts : Vos.Timer.Timers n) (i : Fin n) (k : Nat) : Prop :=
  (ts.slot i).active = true → (ts.slot i).due = false → ts.now + k < (ts.slot i).deadline →
    ((Vos.Timer.afterTicks ts k).slot i).due = false

/-- Setting bits does not clear a bit that was already set. -/
def eventNoClear (bits mask : Vos.Event.Bits) (i : Fin 32) : Prop :=
  bits i = true → Vos.Event.bor bits mask i = true

end Vos.Spec.Sync

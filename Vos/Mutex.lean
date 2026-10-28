import Vos.Sched

/-!
Non-recursive mutex. `owner` is one task or none, so two tasks cannot both
hold it. A lock while another task holds it blocks the caller and leaves the
owner in place. Unlock by the owner either frees the mutex or passes it to
the oldest blocked waiter. Unlock by anyone else does nothing. There is no
priority inheritance.
-/
namespace Vos.Mutex

open Vos
open Vos.Sched

structure Mutex (nt : Nat) where
  owner : Option (Fin nt)
  waiters : List (Fin nt)

def Mutex.empty (nt : Nat) : Mutex nt where
  owner := none
  waiters := []

/-- At most one holder. This is the mutual-exclusion property of every state. -/
def Exclusive {nt : Nat} (m : Mutex nt) : Prop :=
  ∀ a b, m.owner = some a → m.owner = some b → a = b

theorem at_most_one {nt : Nat} (m : Mutex nt) : Exclusive m := by
  intro a b ha hb
  have : some a = some b := by rw [← ha, hb]
  injection this

variable {nt : Nat}

def pushWaiter (ws : List (Fin nt)) (i : Fin nt) : List (Fin nt) :=
  if ws.contains i then ws else ws ++ [i]

def lock (m : Mutex nt) (s : Sched nt) (p : Policy) : Mutex nt × Sched nt × Bool :=
  match s.current with
  | none => (m, s, false)
  | some i =>
    match m.owner with
    | none => ({ m with owner := some i }, s, true)
    | some o =>
      if o = i then
        (m, s, false)
      else
        ({ m with waiters := pushWaiter m.waiters i }, block s p, false)

def unlock (m : Mutex nt) (s : Sched nt) (p : Policy) : Mutex nt × Sched nt × Bool :=
  match s.current with
  | none => (m, s, false)
  | some i =>
    if m.owner ≠ some i then
      (m, s, false)
    else
      match m.waiters with
      | [] => ({ m with owner := none }, s, true)
      | r :: rs =>
        if s.park r == .blocked then
          ({ m with owner := some r, waiters := rs }, unblock s p r, true)
        else
          ({ m with owner := none, waiters := rs }, s, true)

theorem lock_takes (m : Mutex nt) (s : Sched nt) (p : Policy) (i : Fin nt)
    (hc : s.current = some i) (hfree : m.owner = none) :
    (lock m s p).1.owner = some i ∧ (lock m s p).2.1 = s ∧ (lock m s p).2.2 = true := by
  simp [lock, hc, hfree]

theorem lock_blocks (m : Mutex nt) (s : Sched nt) (p : Policy) (i o : Fin nt)
    (hc : s.current = some i) (ho : m.owner = some o) (hne : i ≠ o) (hinv : Inv s)
    (hfresh : i ∉ m.waiters) :
    (lock m s p).1.owner = some o ∧ i ∈ (lock m s p).1.waiters ∧
      (lock m s p).2.1.park i = .blocked ∧ Inv (lock m s p).2.1 := by
  have hpark : (blockCurrent s 0 false).park i = .blocked := by simp [blockCurrent, hc]
  have hf := dispatch_same_fields (blockCurrent s 0 false) p i
  have hinv' := block_inv s hinv p
  have hne' : ¬ o = i := fun h => hne h.symm
  simp [lock, hc, ho, hne', pushWaiter, hfresh, block]
  exact And.intro (by simpa [hf.1] using hpark) hinv'

theorem unlock_foreign (m : Mutex nt) (s : Sched nt) (p : Policy) (i : Fin nt)
    (hc : s.current = some i) (hnot : m.owner ≠ some i) :
    (unlock m s p).1 = m ∧ (unlock m s p).2.1 = s ∧ (unlock m s p).2.2 = false := by
  simp [unlock, hc, hnot]

theorem unlock_frees (m : Mutex nt) (s : Sched nt) (p : Policy) (i : Fin nt)
    (hc : s.current = some i) (ho : m.owner = some i) (hw : m.waiters = []) :
    (unlock m s p).1.owner = none ∧ (unlock m s p).2.1 = s ∧ (unlock m s p).2.2 = true := by
  simp [unlock, hc, ho, hw]

theorem unlock_passes (m : Mutex nt) (s : Sched nt) (p : Policy) (i r : Fin nt)
    (rs : List (Fin nt)) (hc : s.current = some i) (ho : m.owner = some i)
    (hw : m.waiters = r :: rs) (hblk : s.park r = .blocked) (hinv : Inv s) :
    (unlock m s p).1.owner = some r ∧ (unlock m s p).1.waiters = rs ∧
      (unlock m s p).2.1.park r = .alive ∧
      (r ∈ (unlock m s p).2.1.ready ∨ (unlock m s p).2.1.current = some r) ∧
      Exclusive (unlock m s p).1 := by
  have hb : (s.park r == .blocked) = true := (beq_iff_eq).2 hblk
  have hr := unblock_readies s hinv p r hblk
  simp [unlock, hc, ho, hw, hb]
  exact And.intro hr.1 (And.intro hr.2.1 (at_most_one _))

end Vos.Mutex

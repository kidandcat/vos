import Vos.Spec.Queue

/-!
Bounded queue used by the kernel.

The representation is the list in `Vos.Spec.Queue`. `le_cap` is erased; it
exists so a queue value cannot be built with more than `cap` messages.
`enqueue` and `dequeue` are the spec operations, so the FIFO theorem
transports.
-/
namespace Vos.Queue

open Vos.Spec.Queue (enq deq)

structure Queue (α : Type) (cap : Nat) where
  items : List α
  le_cap : items.length ≤ cap

def empty {α : Type} (cap : Nat) : Queue α cap where
  items := []
  le_cap := Nat.zero_le _

theorem length_le {α : Type} {cap : Nat} (q : Queue α cap) : q.items.length ≤ cap :=
  q.le_cap

def enqueue {α : Type} {cap : Nat} (q : Queue α cap) (a : α) : Queue α cap × Bool :=
  match h : enq cap q.items a with
  | (items, ok) =>
    have hlen : items.length ≤ cap := by
      have := Vos.Spec.Queue.enq_length (items := q.items) (a := a) (cap := cap) q.le_cap
      simpa [h] using this
    (⟨items, hlen⟩, ok)

def dequeue {α : Type} {cap : Nat} (q : Queue α cap) : Queue α cap × Option α :=
  match h : deq q.items with
  | (items, v) =>
    have hlen : items.length ≤ cap := by
      exact Nat.le_trans (by simpa [h] using Vos.Spec.Queue.deq_length_le q.items) q.le_cap
    (⟨items, hlen⟩, v)

theorem enqueue_spec {α : Type} {cap : Nat} (q : Queue α cap) (a : α) :
    (enqueue q a).1.items = (enq cap q.items a).1 ∧
      (enqueue q a).2 = (enq cap q.items a).2 := by
  simp [enqueue]

theorem dequeue_spec {α : Type} {cap : Nat} (q : Queue α cap) :
    (dequeue q).1.items = (deq q.items).1 ∧ (dequeue q).2 = (deq q.items).2 := by
  simp [dequeue]

end Vos.Queue

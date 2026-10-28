/-!
Queue specification: a list that never grows past `cap`.

`enq` appends when there is room and otherwise returns the same list with
`false`. `deq` removes the head. `pushAll` then `drain` is the identity on
any list that fits. That is the FIFO, capacity, no-loss, and no-duplication
claim: the drained sequence is the pushed sequence, in order, with the same
length.
-/
namespace Vos.Spec.Queue

variable {α : Type}

def enq (cap : Nat) (items : List α) (a : α) : List α × Bool :=
  if items.length < cap then (items ++ [a], true) else (items, false)

def deq (items : List α) : List α × Option α :=
  match items with
  | [] => ([], none)
  | a :: rest => (rest, some a)

def pushAll (cap : Nat) (items : List α) : List α → List α
  | [] => items
  | a :: xs =>
    let (items', ok) := enq cap items a
    if ok then pushAll cap items' xs else items

def drain : List α → Nat → List α
  | _, 0 => []
  | items, n + 1 =>
    let (items', v) := deq items
    match v with
    | none => []
    | some a => a :: drain items' n

theorem enq_accept {cap : Nat} {items : List α} {a : α} (h : items.length < cap) :
    enq cap items a = (items ++ [a], true) := by
  simp [enq, h]

theorem enq_reject {cap : Nat} {items : List α} {a : α} (h : ¬ items.length < cap) :
    enq cap items a = (items, false) := by
  simp [enq, h]

theorem enq_length {cap : Nat} {items : List α} {a : α} (h : items.length ≤ cap) :
    (enq cap items a).1.length ≤ cap := by
  unfold enq
  split
  · simp
    omega
  · simpa using h

theorem enq_prefix (cap : Nat) (items : List α) (a : α) :
    ((enq cap items a).1).take items.length = items := by
  unfold enq
  split <;> simp

theorem deq_empty {items : List α} (h : items = []) : deq items = ([], none) := by
  simp [deq, h]

theorem deq_head {a : α} {rest : List α} : deq (a :: rest) = (rest, some a) := by
  simp [deq]

theorem deq_length_le (items : List α) : (deq items).1.length ≤ items.length := by
  cases items with
  | nil => simp [deq]
  | cons _ _ => simp [deq]

theorem pushAll_append {cap : Nat} {items xs : List α}
    (h : items.length + xs.length ≤ cap) :
    pushAll cap items xs = items ++ xs := by
  induction xs generalizing items with
  | nil => simp [pushAll]
  | cons a xs ih =>
    have hlen : (a :: xs).length = xs.length + 1 := by simp
    have hlt : items.length < cap := by omega
    rw [show pushAll cap items (a :: xs) =
        (let (items', ok) := enq cap items a
        if ok then pushAll cap items' xs else items) from rfl]
    rw [enq_accept hlt]
    simp
    have hrest : (items ++ [a]).length + xs.length ≤ cap := by simp; omega
    rw [ih hrest]
    simp

theorem drain_take (items : List α) (n : Nat) : drain items n = items.take n := by
  induction n generalizing items with
  | zero => simp [drain]
  | succ n ih =>
    cases items with
    | nil => simp [drain, deq]
    | cons a rest => simp [drain, deq, ih]

/-- Messages that fit are recovered in order, once each. -/
theorem fifo {cap : Nat} {xs : List α} (h : xs.length ≤ cap) :
    drain (pushAll cap [] xs) xs.length = xs := by
  have hpush : pushAll cap [] xs = xs := by
    simpa using pushAll_append (items := ([] : List α)) (xs := xs) (cap := cap) (by simpa using h)
  simp [hpush, drain_take]

end Vos.Spec.Queue

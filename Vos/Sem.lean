import Vos.Sched

/-!
Counting semaphore. `count ≤ max` is part of the value. A waiting taker is
blocked; `give` to a non-empty waiter list hands that task the token and
does not change `count` (the increment and the take cancel). `give` with no
waiter increments until `max` and then refuses.
-/
namespace Vos.Sem

open Vos
open Vos.Sched

structure Sem (nt : Nat) where
  count : Nat
  max : Nat
  le : count ≤ max
  waiters : List (Fin nt)

def Sem.empty (nt max : Nat) : Sem nt where
  count := 0
  max := max
  le := Nat.zero_le _
  waiters := []

def CountBound {nt : Nat} (sem : Sem nt) : Prop := sem.count ≤ sem.max

def Token {nt : Nat} (sem : Sem nt) : Prop := sem.waiters = [] ∨ sem.count = 0

theorem count_bound {nt : Nat} (sem : Sem nt) : CountBound sem := sem.le

theorem waiters_bounded {nt : Nat} (sem : Sem nt) (h : sem.waiters.Nodup) :
    sem.waiters.length ≤ nt := by
  simpa [List.length_finRange] using
    h.length_le_of_subset (l₂ := List.finRange nt) (fun _ _ => List.mem_finRange _)

variable {nt : Nat}

def pushWaiter (ws : List (Fin nt)) (i : Fin nt) : List (Fin nt) :=
  if ws.contains i then ws else ws ++ [i]

theorem pushWaiter_nodup {ws : List (Fin nt)} {i : Fin nt} (h : ws.Nodup) :
    (pushWaiter ws i).Nodup := by
  unfold pushWaiter
  split
  · exact h
  · grind

def give (sem : Sem nt) (s : Sched nt) (p : Policy) : Sem nt × Sched nt × Bool :=
  match sem.waiters with
  | r :: rs =>
    if s.park r == .blocked then
      ({ sem with waiters := rs }, unblock s p r, true)
    else
      ({ sem with waiters := rs }, s, false)
  | [] =>
    if h : sem.count < sem.max then
      ({ sem with count := sem.count + 1, le := by omega }, s, true)
    else
      (sem, s, false)

def take (sem : Sem nt) (s : Sched nt) (p : Policy) : Sem nt × Sched nt × Bool :=
  match s.current with
  | none => (sem, s, false)
  | some i =>
    if h : 0 < sem.count then
      (⟨sem.count - 1, sem.max, Nat.le_trans (Nat.sub_le sem.count 1) sem.le, sem.waiters⟩, s, true)
    else
      ({ sem with waiters := pushWaiter sem.waiters i }, block s p, false)

theorem give_incs (sem : Sem nt) (s : Sched nt) (p : Policy)
    (hw : sem.waiters = []) (hroom : sem.count < sem.max) :
    (give sem s p).1.count = sem.count + 1 ∧ (give sem s p).1.max = sem.max ∧
      (give sem s p).2.1 = s ∧ (give sem s p).2.2 = true := by
  simp [give, hw, hroom]

theorem give_saturated (sem : Sem nt) (s : Sched nt) (p : Policy)
    (hw : sem.waiters = []) (hfull : ¬ sem.count < sem.max) :
    (give sem s p).1 = sem ∧ (give sem s p).2.2 = false := by
  simp [give, hw, hfull]

theorem give_wakes (sem : Sem nt) (s : Sched nt) (p : Policy) (r : Fin nt) (rs : List (Fin nt))
    (hw : sem.waiters = r :: rs) (hblk : s.park r = .blocked) (hinv : Inv s) :
    (give sem s p).1.count = sem.count ∧ (give sem s p).1.waiters = rs ∧
      (give sem s p).2.1.park r = .alive ∧
      (r ∈ (give sem s p).2.1.ready ∨ (give sem s p).2.1.current = some r) ∧
      Inv (give sem s p).2.1 := by
  have hb : (s.park r == .blocked) = true := (beq_iff_eq).2 hblk
  have hr := unblock_readies s hinv p r hblk
  simp [give, hw, hb]
  exact hr

theorem take_decs (sem : Sem nt) (s : Sched nt) (p : Policy) (i : Fin nt)
    (hc : s.current = some i) (hpos : 0 < sem.count) :
    (take sem s p).1.count = sem.count - 1 ∧ (take sem s p).1.waiters = sem.waiters ∧
      (take sem s p).2.1 = s ∧ (take sem s p).2.2 = true := by
  simp [take, hc, hpos]

theorem take_blocks (sem : Sem nt) (s : Sched nt) (p : Policy) (i : Fin nt)
    (hc : s.current = some i) (hempty : sem.count = 0) (hinv : Inv s)
    (hfresh : i ∉ sem.waiters) :
    (take sem s p).1.count = 0 ∧ i ∈ (take sem s p).1.waiters ∧
      (take sem s p).2.1.park i = .blocked ∧ Inv (take sem s p).2.1 := by
  have hpark : (blockCurrent s 0 false).park i = .blocked := by simp [blockCurrent, hc]
  have hf := dispatch_same_fields (blockCurrent s 0 false) p i
  have hinv' := block_inv s hinv p
  simp [take, hc, hempty, pushWaiter, hfresh, block]
  exact And.intro (by simpa [hf.1] using hpark) hinv'

theorem give_keeps_token (sem : Sem nt) (s : Sched nt) (p : Policy)
    (ht : Token sem) (hw : sem.waiters = []) (hroom : sem.count < sem.max) :
    Token (give sem s p).1 := by
  simp [Token, give, hw, hroom]

theorem take_keeps_token (sem : Sem nt) (s : Sched nt) (p : Policy) (i : Fin nt)
    (ht : Token sem) (hc : s.current = some i) :
    Token (take sem s p).1 := by
  simp [Token, take, hc]
  split
  · rename_i hpos
    cases ht with
    | inl hw => simp [hw]
    | inr hz => simp [hz] at hpos
  · rename_i hnot
    have hz : sem.count = 0 := by omega
    simp [hz]

end Vos.Sem

import Vos.Sched

/-!
Event flags: 32 boolean bits. A waiter sleeps until any bit in its mask is
set, or until every bit in its mask is set. `setBits` never clears a bit.
A waiter whose mask is still unsatisfied stays blocked. A waiter whose mask
becomes satisfied is taken off the list and readied. An empty mask is rejected.
-/
namespace Vos.Event

open Vos
open Vos.Sched

abbrev Bits := Fin 32 → Bool

def emptyBits : Bits := fun _ => false

def bor (a b : Bits) : Bits := fun i => a i || b i

def band (a b : Bits) : Bits := fun i => a i && b i

def bclear (a mask : Bits) : Bits := fun i => a i && !mask i

def anySet (bits mask : Bits) : Bool :=
  (List.finRange 32).any fun i => bits i && mask i

def allSet (bits mask : Bits) : Bool :=
  (List.finRange 32).all fun i => !mask i || bits i

def maskEmpty (mask : Bits) : Bool :=
  (List.finRange 32).all fun i => !mask i

structure Group (nt : Nat) where
  bits : Bits
  waiters : List (Fin nt)
  want : Fin nt → Bits
  waitAll : Fin nt → Bool

def Group.empty (nt : Nat) : Group nt where
  bits := emptyBits
  waiters := []
  want := fun _ => emptyBits
  waitAll := fun _ => false

def satisfied {nt : Nat} (g : Group nt) (i : Fin nt) : Bool :=
  if g.waitAll i then allSet g.bits (g.want i) else anySet g.bits (g.want i)

variable {nt : Nat}

def pushWaiter (ws : List (Fin nt)) (i : Fin nt) : List (Fin nt) :=
  if ws.contains i then ws else ws ++ [i]

theorem bor_apply (a b : Bits) (i : Fin 32) : bor a b i = (a i || b i) := rfl

theorem set_no_clear (bits mask : Bits) (i : Fin 32) (h : bits i = true) :
    bor bits mask i = true := by
  simp [bor, h]

theorem set_only (bits mask : Bits) (i : Fin 32) (h : mask i = false) :
    bor bits mask i = bits i := by
  simp [bor, h]

theorem clear_only (bits mask : Bits) (i : Fin 32) (h : mask i = false) :
    bclear bits mask i = bits i := by
  simp [bclear, h]

theorem clear_bit (bits mask : Bits) (i : Fin 32) (h : mask i = true) :
    bclear bits mask i = false := by
  simp [bclear, h]

def clearBits (g : Group nt) (mask : Bits) : Group nt :=
  { g with bits := bclear g.bits mask }

def setBits (g : Group nt) (s : Sched nt) (p : Policy) (mask : Bits) : Group nt × Sched nt :=
  let g := { g with bits := bor g.bits mask }
  let woken := g.waiters.filter fun i => satisfied g i
  let still := g.waiters.filter fun i => !(satisfied g i)
  let s := woken.foldl (fun s i => unblock s p i) s
  ({ g with waiters := still }, s)

def wait (g : Group nt) (s : Sched nt) (p : Policy) (mask : Bits) (all : Bool) :
    Group nt × Sched nt × Bool :=
  match s.current with
  | none => (g, s, false)
  | some i =>
    if maskEmpty mask then
      (g, s, false)
    else
      let g :=
        { g with
          want := fun j => if j = i then mask else g.want j
          waitAll := fun j => if j = i then all else g.waitAll j }
      if satisfied g i then
        (g, s, true)
      else
        ({ g with waiters := pushWaiter g.waiters i }, block s p, false)

theorem set_keeps_waiter (g : Group nt) (s : Sched nt) (p : Policy) (mask : Bits) (r : Fin nt)
    (hw : g.waiters = [r])
    (hnot : satisfied { g with bits := bor g.bits mask } r = false) :
    (setBits g s p mask).1.waiters = [r] ∧ (setBits g s p mask).1.bits = bor g.bits mask ∧
      (setBits g s p mask).2 = s := by
  simp [hw] at hnot
  simp [setBits, hw, hnot, List.filter]

theorem set_wakes (g : Group nt) (s : Sched nt) (p : Policy) (mask : Bits) (r : Fin nt)
    (hw : g.waiters = [r]) (hblk : s.park r = .blocked) (hinv : Inv s)
    (hsat : satisfied { g with bits := bor g.bits mask } r = true) :
    (setBits g s p mask).1.waiters = [] ∧
      (setBits g s p mask).2.park r = .alive ∧
      (r ∈ (setBits g s p mask).2.ready ∨ (setBits g s p mask).2.current = some r) ∧
      Inv (setBits g s p mask).2 := by
  simp [hw] at hsat
  have hr := unblock_readies s hinv p r hblk
  simp [setBits, hw, hsat, List.filter]
  exact hr

end Vos.Event

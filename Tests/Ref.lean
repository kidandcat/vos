import Vos.Sched

/-!
A second scheduler, written against the same rules as `Vos.Sched` but with
`Array` and `Nat` indexes. The differential test runs both on one script.
This file is not part of the kernel.
-/
namespace Tests.Ref

open Vos

variable {n : Nat}

structure Ref (n : Nat) where
  park : Array Park
  prio : Array Nat
  deadline : Array Nat
  onDelay : Array Bool
  ready : List Nat
  current : Option Nat
  now : Nat

def init (n : Nat) : Ref n where
  park := Array.replicate n .unused
  prio := Array.replicate n 0
  deadline := Array.replicate n 0
  onDelay := Array.replicate n false
  ready := []
  current := none
  now := 0

def readyPush (r : List Nat) (i : Nat) : List Nat :=
  if r.contains i then r else r ++ [i]

def promote (r : Ref n) (i prio : Nat) : Ref n :=
  { r with
    park := r.park.set! i .alive
    prio := r.prio.set! i prio
    onDelay := r.onDelay.set! i false
    ready := readyPush r.ready i }

def activate (r : Ref n) (i : Nat) : Ref n :=
  { r with ready := r.ready.erase i, current := some i }

def demote (r : Ref n) (c : Nat) : Ref n :=
  { r with ready := readyPush r.ready c, current := none }

def pickMax (prio : Nat → Nat) : List Nat → Option Nat
  | [] => none
  | i :: rest =>
    match pickMax prio rest with
    | none => some i
    | some b => if prio b > prio i then some b else some i

def choose (r : Ref n) (p : Policy) : Option Nat :=
  match p with
  | .cooperative =>
    match r.current with
    | some c => some c
    | none => r.ready.head?
  | .priority =>
    match pickMax (fun i => r.prio[i]!) r.ready with
    | none => r.current
    | some i =>
      match r.current with
      | none => some i
      | some c => if r.prio[i]! > r.prio[c]! then some i else some c

def applyChoice (r : Ref n) : Option Nat → Ref n
  | none => r
  | some i =>
    match r.current with
    | none => activate r i
    | some c => if c = i then r else activate (demote r c) i

def dispatch (r : Ref n) (p : Policy) : Ref n :=
  applyChoice r (choose r p)

def findUnused (r : Ref n) : Option Nat :=
  (List.range n).find? fun i => r.park[i]! == .unused

def spawn (r : Ref n) (p : Policy) (prio : Nat) : Ref n × Option Nat :=
  match findUnused r with
  | none => (r, none)
  | some i => (dispatch (promote r i prio) p, some i)

def yieldTask (r : Ref n) (p : Policy) : Ref n :=
  match r.current with
  | none => dispatch r p
  | some c => dispatch (demote r c) p

def blockCurrent (r : Ref n) (deadline : Nat) (onDelay : Bool) : Ref n :=
  match r.current with
  | none => r
  | some c =>
    { r with
      park := r.park.set! c .blocked
      onDelay := r.onDelay.set! c onDelay
      deadline := r.deadline.set! c deadline
      ready := r.ready.erase c
      current := none }

def delay (r : Ref n) (p : Policy) (dt : Nat) : Ref n :=
  if dt = 0 then yieldTask r p
  else dispatch (blockCurrent r (r.now + dt) true) p

def unblock (r : Ref n) (p : Policy) (i : Nat) : Ref n :=
  if r.park[i]! == .blocked then dispatch (promote r i (r.prio[i]!)) p else r

def exitTask (r : Ref n) (p : Policy) : Ref n :=
  match r.current with
  | none => r
  | some c =>
    dispatch
      { r with
        park := r.park.set! c .terminated
        onDelay := r.onDelay.set! c false
        ready := r.ready.erase c
        current := none } p

def wake (r : Ref n) : Ref n :=
  (List.range n).foldl (fun r i =>
    if r.park[i]! == .blocked && r.onDelay[i]! && decide (r.deadline[i]! ≤ r.now) then
      promote r i (r.prio[i]!)
    else
      r) r

def tick (r : Ref n) (p : Policy) : Ref n :=
  dispatch (wake { r with now := r.now + 1 }) p

def block (r : Ref n) (p : Policy) : Ref n :=
  dispatch (blockCurrent r 0 false) p

inductive Act where
  | spawn (prio : Nat)
  | yield
  | delay (dt : Nat)
  | block
  | unblock (i : Nat)
  | tick
  | exit
  deriving Repr

def applyRef (r : Ref n) (p : Policy) : Act → Ref n
  | .spawn prio => (spawn r p prio).1
  | .yield => yieldTask r p
  | .delay dt => delay r p dt
  | .block => block r p
  | .unblock i => if i < n then unblock r p i else r
  | .tick => tick r p
  | .exit => exitTask r p

def applySched (s : Vos.Sched n) (p : Policy) : Act → Vos.Sched n
  | .spawn prio => (Vos.Sched.spawn s p prio).1
  | .yield => Vos.Sched.yieldTask s p
  | .delay dt => Vos.Sched.delay s p dt
  | .block => Vos.Sched.block s p
  | .unblock i =>
    if h : i < n then Vos.Sched.unblock s p ⟨i, h⟩ else s
  | .tick => Vos.Sched.tick s p
  | .exit => Vos.Sched.exitTask s p

def viewSched (s : Vos.Sched n) : Option Nat × List Nat × Nat × List (Park × Nat × Bool × Nat) :=
  (s.current.map (·.val), s.ready.map (·.val), s.now,
    (List.finRange n).map fun i => (s.park i, s.prio i, s.onDelay i, s.deadline i))

def viewRef (r : Ref n) : Option Nat × List Nat × Nat × List (Park × Nat × Bool × Nat) :=
  (r.current, r.ready, r.now,
    (List.range n).map fun i => (r.park[i]!, r.prio[i]!, r.onDelay[i]!, r.deadline[i]!))

def lcg (x : UInt64) : UInt64 :=
  x * 6364136223846793005 + 1442695040888963407

def actOf (n : Nat) (x : UInt64) : Act :=
  match x.toNat % 7 with
  | 0 => .spawn ((x.toNat / 7) % 8)
  | 1 => .yield
  | 2 => .delay ((x.toNat / 7) % 5)
  | 3 => .block
  | 4 => .unblock ((x.toNat / 7) % n)
  | 5 => .tick
  | _ => .exit

def runBoth (n : Nat) (p : Policy) (seed : UInt64) (steps : Nat) :
    Except Nat Unit := do
  let mut s : Vos.Sched n := Vos.Sched.empty n
  let mut r : Ref n := init n
  let mut x := seed
  for k in List.range steps do
    let a := actOf n x
    x := lcg x
    s := applySched s p a
    r := applyRef r p a
    if viewSched s != viewRef r then
      throw k
  pure ()

end Tests.Ref

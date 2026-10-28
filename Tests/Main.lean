import Tests.Ref
import Vos.Host.Sim
import Vos.Kernel
import Vos.Queue
import Vos.Sched
import Vos.Spec.Queue

open Vos

def fail (msg : String) : IO Unit :=
  throw (IO.userError msg)

def check (name : String) (ok : Bool) : IO Unit := do
  unless ok do
    fail name

def testQueue : IO Unit := do
  check "spec fifo" <|
    Vos.Spec.Queue.drain (Vos.Spec.Queue.pushAll 3 [] [1, 2, 3]) 3 == [1, 2, 3]
  check "spec prefix" <|
    Vos.Spec.Queue.drain (Vos.Spec.Queue.pushAll 3 [] [1, 2, 3]) 2 == [1, 2]
  let mut q : Vos.Queue.Queue Nat 3 := Vos.Queue.empty 3
  for x in [1, 2, 3] do
    let (q', ok) := Vos.Queue.enqueue q x
    unless ok do fail s!"enqueue {x}"
    q := q'
  check "order" (q.items == [1, 2, 3])
  let (full, ok) := Vos.Queue.enqueue q 4
  check "reject" (ok == false && full.items == [1, 2, 3])
  let (q2, a) := Vos.Queue.dequeue q
  check "head" (a == some 1 && q2.items == [2, 3])
  let zero : Vos.Queue.Queue Nat 0 := Vos.Queue.empty 0
  check "cap0" ((Vos.Queue.enqueue zero 1).2 == false && (Vos.Queue.dequeue zero).2 == none)

def testPriority : IO Unit := do
  let p : Policy := .priority
  let s0 : Sched 3 := Sched.empty 3
  let (s1, id0) := Sched.spawn s0 p 1
  let (s2, id1) := Sched.spawn s1 p 3
  let (s3, id2) := Sched.spawn s2 p 2
  check "ids" (id0 == some 0 && id1 == some 1 && id2 == some 2)
  check "runs highest" (s3.current == some 1)
  check "lower waiting" (s3.ready.map (·.val) == [0, 2])
  let s4 := Sched.block s3 p
  check "next is 2" (s4.current == some 2)
  let s5 := Sched.block s4 p
  check "last is 0" (s5.current == some 0)
  check "blocked not current" (s5.park 1 == .blocked && s5.current != some 1)

def testCoop : IO Unit := do
  let p : Policy := .cooperative
  let s0 : Sched 2 := Sched.empty 2
  let (s1, _) := Sched.spawn s0 p 1
  let (s2, _) := Sched.spawn s1 p 9
  check "no preempt" (s2.current == some 0)
  let s3 := Sched.yieldTask s2 p
  check "yield to head" (s3.current == some 1)
  let s4 := Sched.yieldTask s3 p
  check "round robin" (s4.current == some 0)

def testDelay : IO Unit := do
  let p : Policy := .priority
  let s0 : Sched 1 := Sched.empty 1
  let (s1, _) := Sched.spawn s0 p 1
  let s2 := Sched.delay s1 p 3
  check "asleep" (s2.current == none && s2.park 0 == .blocked && s2.deadline 0 == 3)
  let s3 := Sched.tick s2 p
  let s4 := Sched.tick s3 p
  check "before deadline" (s4.now == 2 && s4.park 0 == .blocked && s4.current == none)
  let s5 := Sched.tick s4 p
  check "at deadline" (s5.now == 3 && s5.current == some 0 && s5.park 0 == .alive)

def testKernel : IO Unit := do
  check "demo" Vos.Host.demoOk
  let p : Policy := .priority
  let w : Vos.Kernel.World Nat 2 1 1 := Vos.Kernel.World.empty Nat 2 1 1
  let q : Fin 1 := 0
  let (w, _) := Vos.Host.spawn w p 1
  let (w, hi) := Vos.Host.spawn w p 4
  match hi with
  | none => fail "spawn"
  | some hi =>
    let w := Vos.Kernel.send w p q 1
    check "one in queue" ((w.qs q).items == [1])
    let w := Vos.Kernel.send w p q 2
    check "second held" ((w.qs q).items == [1] && w.pending hi == some 2 &&
      w.sched.park hi == .blocked)
    let (w, v) := Vos.Kernel.recv w p q
    check "recv head" (v == some 1)
    -- the blocked sender is released into the free slot
    check "released" ((w.qs q).items == [2] && w.pending hi == none)

def ringContents (buf : Array Nat) (head count : Nat) : List Nat :=
  (List.range count).map fun k => buf[(head + k) % buf.size]!

def testRing (seed : UInt64) (steps : Nat) : IO Unit := do
  let cap := 5
  let mut q : Vos.Queue.Queue Nat cap := Vos.Queue.empty cap
  let mut buf := Array.replicate cap 0
  let mut head := 0
  let mut count := 0
  let mut x := seed
  for _ in List.range steps do
    let bit := x.toNat % 2
    let value := (x.toNat / 2) % 100
    x := Tests.Ref.lcg x
    if bit = 0 then
      let (q', ok) := Vos.Queue.enqueue q value
      q := q'
      if count < cap then
        buf := buf.set! ((head + count) % cap) value
        count := count + 1
        unless ok do fail "ring accepted, queue rejected"
      else
        unless !ok do fail "ring full, queue accepted"
    else
      let (q', v) := Vos.Queue.dequeue q
      q := q'
      if count = 0 then
        unless v == none do fail "ring empty, queue returned"
      else
        let expect := buf[head]!
        unless v == some expect do fail s!"ring {expect} queue {v}"
        head := (head + 1) % cap
        count := count - 1
    unless q.items == ringContents buf head count do
      fail s!"contents {q.items} vs {ringContents buf head count}"
    unless q.items.length ≤ cap do fail "over cap"

def testDiff : IO Unit := do
  for seed in [1, 42, 99, 2026] do
    for p in [Policy.cooperative, Policy.priority] do
      match Tests.Ref.runBoth 4 p seed 200 with
      | .ok () => pure ()
      | .error k => fail s!"diff seed {seed} policy {repr p} step {k}"

def main : IO UInt32 := do
  try
    testQueue
    testPriority
    testCoop
    testDelay
    testKernel
    testRing 7 300
    testDiff
    IO.println "vos tests ok"
    return 0
  catch e =>
    IO.eprintln s!"vos tests failed: {e}"
    return 1

import Tests.Ref
import Vos.Arch.Mtime
import Vos.Event
import Vos.Host.Sim
import Vos.Kernel
import Vos.Mutex
import Vos.Queue
import Vos.Sched
import Vos.Sem
import Vos.Spec.Queue
import Vos.Hal.Port
import Vos.Target.C3Demo
import Vos.Target.Size.Empty
import Vos.Target.Size.Event
import Vos.Target.Size.Kernel
import Vos.Target.Size.Mutex
import Vos.Target.Size.Queue
import Vos.Target.Size.Sched
import Vos.Target.Size.Sem
import Vos.Target.Size.Timer
import Vos.Timer

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

def bit (i : Fin 32) : Vos.Event.Bits := fun j => j == i

def testTimers : IO Unit := do
  let ts0 := Vos.Timer.start (Vos.Timer.Timers.empty 1) 0 3 0
  let ts1 := Vos.Timer.tick ts0
  let ts2 := Vos.Timer.tick ts1
  check "timer early" (ts2.now == 2 && (ts2.slot 0).due == false && (ts2.slot 0).active == true)
  let ts3 := Vos.Timer.tick ts2
  check "timer fires" (ts3.now == 3 && (ts3.slot 0).due == true && (ts3.slot 0).active == false)
  let per0 := Vos.Timer.start (Vos.Timer.Timers.empty 1) 0 1 2
  let per1 := Vos.Timer.tick per0
  check "period arms" ((per1.slot 0).due == true && (per1.slot 0).deadline == 3)
  let (per2, seen) := Vos.Timer.takeDue per1 0
  check "take due" (seen && (per2.slot 0).due == false && (per2.slot 0).deadline == 3)
  let per3 := Vos.Timer.tick per2
  check "period waits" (per3.now == 2 && (per3.slot 0).due == false)

def testSem : IO Unit := do
  let p : Policy := .priority
  let (s0, _) := Sched.spawn (Sched.empty 1) p 1
  let sem0 := Vos.Sem.Sem.empty 1 2
  let (sem1, _, ok1) := Vos.Sem.give sem0 s0 p
  let (sem2, _, ok2) := Vos.Sem.give sem1 s0 p
  let (sem3, _, ok3) := Vos.Sem.give sem2 s0 p
  check "sem inc" (ok1 && ok2 && sem2.count == 2 && !ok3 && sem3.count == 2)
  let (sem4, s4, ok4) := Vos.Sem.take sem3 s0 p
  let (sem5, _, ok5) := Vos.Sem.take sem4 s4 p
  check "sem dec" (ok4 && ok5 && sem5.count == 0)
  let (sem6, s6, ok6) := Vos.Sem.take sem5 s4 p
  check "sem blocks" (!ok6 && sem6.count == 0 && s6.park 0 == .blocked)
  let (sem7, s7, ok7) := Vos.Sem.give sem6 s6 p
  check "sem wakes" (ok7 && sem7.count == 0 && s7.park 0 == .alive)
  -- Non-blocking fragment against a counter, 80 steps, seed 11.
  let max := 3
  let mut sem : Vos.Sem.Sem 1 := Vos.Sem.Sem.empty 1 max
  let mut count := 0
  let mut x : UInt64 := 11
  for _ in List.range 80 do
    let give? := x.toNat % 2 == 0
    x := Tests.Ref.lcg x
    if give? then
      let (sem', _, ok) := Vos.Sem.give sem s0 p
      sem := sem'
      if count < max then
        count := count + 1
        unless ok do fail "sem ref accepted"
      else
        unless !ok do fail "sem ref saturated"
    else if 0 < count then
      let (sem', _, ok) := Vos.Sem.take sem s0 p
      sem := sem'
      count := count - 1
      unless ok do fail "sem ref take"
    unless sem.count == count do fail s!"sem count {sem.count} ref {count}"

def testMutex : IO Unit := do
  let p : Policy := .cooperative
  let (s1, _) := Sched.spawn (Sched.empty 2) p 1
  let (s2, _) := Sched.spawn s1 p 1
  let (m1, s3, ok) := Vos.Mutex.lock (Vos.Mutex.Mutex.empty 2) s2 p
  check "lock" (ok && m1.owner == some 0 && s3.current == some 0)
  let s4 := Sched.yieldTask s3 p
  check "other runs" (s4.current == some 1)
  let (m2, s5, ok2) := Vos.Mutex.lock m1 s4 p
  check "excluded" (!ok2 && m2.owner == some 0 && s5.park 1 == .blocked && s5.current == some 0)
  let (m3, s6, ok3) := Vos.Mutex.unlock m2 s5 p
  check "passed" (ok3 && m3.owner == some 1 && s6.park 1 == .alive)
  let (m4, s7, ok4) := Vos.Mutex.unlock m3 s6 p
  check "foreign" (!ok4 && m4.owner == some 1 && s7.current == s6.current)

def testEvents : IO Unit := do
  let p : Policy := .priority
  let (s0, _) := Sched.spawn (Sched.empty 1) p 1
  let s1 := Sched.block s0 p
  check "blocked" (s1.park 0 == .blocked)
  let g : Vos.Event.Group 1 := { Vos.Event.Group.empty 1 with
    waiters := [0], want := fun _ => bit 0, waitAll := fun _ => false }
  let (g1, s2) := Vos.Event.setBits g s1 p (bit 1)
  check "stays" (g1.waiters == [0] && s2.park 0 == .blocked && g1.bits 0 == false && g1.bits 1 == true)
  let (g2, s3) := Vos.Event.setBits g1 s2 p (bit 0)
  check "wakes" (g2.waiters == [] && s3.park 0 == .alive && g2.bits 0 == true && g2.bits 1 == true)

def testSendReadies : IO Unit := do
  let p : Policy := .priority
  let w : Vos.Kernel.World Nat 2 1 4 := Vos.Kernel.World.empty Nat 2 1 4
  let q : Fin 1 := 0
  let (w, lo) := Vos.Host.spawn w p 1
  let (w, hi) := Vos.Host.spawn w p 5
  check "ids" (lo == some 0 && hi == some 1 && w.sched.current == some 1)
  let (w, v) := Vos.Kernel.recv w p q
  check "recv blocks" (v == none && w.sched.park 1 == .blocked && w.sched.current == some 0)
  let w := Vos.Kernel.send w p q 7
  check "readied" ((w.qs q).items == [] && w.inbox 1 == some 7 &&
    w.sched.park 1 == .alive && w.sched.current == some 1)

def testMtime : IO Unit := do
  let c0 : Vos.Arch.Mtime.Clock :=
    { time := 0, cmp := 5, mtie := true, mie := true, busy := false, queued := 0, ticks := 0 }
  let c1 := Vos.Arch.Mtime.advance c0 4
  check "before compare" (Vos.Arch.Mtime.pending c1 == false)
  let c2 := Vos.Arch.Mtime.advance c1 1
  check "armed" (Vos.Arch.Mtime.armed c2 == true && c2.time == 5)
  let c3 := Vos.Arch.Mtime.take c2 10
  check "one tick" (c3.ticks == 1 && c3.queued == 0 && Vos.Arch.Mtime.pending c3 == false)
  let c4 : Vos.Arch.Mtime.Clock := { c2 with busy := true }
  let c5 := Vos.Arch.Mtime.take c4 10
  check "queued" (c5.ticks == 0 && c5.queued == 1)
  let s := (Sched.spawn (Sched.empty 1) .priority 1).1
  let stepped := Vos.Arch.Mtime.onTimer c2 s .priority 10
  check "sched tick" (stepped.1.ticks == 1 && stepped.2.now == s.now + 1)

def testC3Demo : IO Unit := do
  check "c3 trace" (Vos.Target.C3Demo.trace == [1, 2, 4])

def testSize : IO Unit := do
  check "size empty" (Vos.Target.Size.Empty.sizeEmpty 0 == 0)
  check "size queue" (Vos.Target.Size.Queue.sizeQueue 0 == 1)
  check "size sched" (Vos.Target.Size.Sched.sizeSched 0 == 1)
  check "size kernel" (Vos.Target.Size.Kernel.sizeKernel 0 == 1)
  check "size timer" (Vos.Target.Size.Timer.sizeTimer 0 == 1)
  check "size sem" (Vos.Target.Size.Sem.sizeSem 0 == 1)
  check "size mutex" (Vos.Target.Size.Mutex.sizeMutex 0 == 1)
  check "size event" (Vos.Target.Size.Event.sizeEvent 0 == 1)
  let chip := Vos.Hal.espIdf
  check "idf caps" (chip.gpio && chip.uart && chip.storage &&
    (chip.spi == false) && (chip.i2c == false) && (chip.radio == false) &&
    (chip.tickInterrupt == false))
  check "same caps" (Vos.Hal.esp32c3.caps == Vos.Hal.esp32s3.caps)

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
    testTimers
    testSem
    testMutex
    testEvents
    testSendReadies
    testMtime
    testC3Demo
    testSize
    testRing 7 300
    testDiff
    IO.println "vos tests ok"
    return 0
  catch e =>
    IO.eprintln s!"vos tests failed: {e}"
    return 1

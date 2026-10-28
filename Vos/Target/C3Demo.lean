import Vos.Host.Sim
import Vos.Kernel
import Vos.Timer

/-!
ESP32-C3 demo, as a pure function of the events the shim posts.

The shim owns the FreeRTOS queue. It posts `1` once at start and `2` on each
tick. This module runs two kernel tasks, one queue, and one one-shot timer.
`trace` is what the host test checks. The same function is `@[export]`ed for
the C build.
-/
namespace Vos.Target.C3Demo

open Vos

def policy : Policy := .priority

def queue : Fin 1 := 0

def hi : Fin 2 := 1

def lo : Fin 2 := 0

structure State where
  world : Kernel.World Nat 2 1 4
  timers : Timer.Timers 1
  phase : Nat
  code : UInt32

def init : State where
  world := Kernel.World.empty Nat 2 1 4
  timers := Timer.Timers.empty 1
  phase := 0
  code := 0

def start (s : State) : State :=
  let (w, id0) := Host.spawn s.world policy 1
  let (w, id1) := Host.spawn w policy 5
  match id0, id1 with
  | some t0, some t1 =>
    let w := Kernel.send w policy queue 41
    let w := Host.delay w policy 2
    let ts := Timer.start s.timers 0 2 0
    let (w, got) := Kernel.recv w policy queue
    let ok : Bool :=
      t0 == lo && t1 == hi && got == some 41 && (w.qs queue).items == [] &&
      w.sched.current == some lo && w.sched.park hi == .blocked &&
      w.sched.now == 0 && (ts.slot 0).due == false && (ts.slot 0).active == true &&
      (ts.slot 0).deadline == 2
    { world := w, timers := ts, phase := 1, code := if ok then 1 else 9 }
  | _, _ => { s with code := 9 }

def onTick (s : State) : State :=
  let w := Host.tick s.world policy
  let ts := Timer.tick s.timers
  if s.phase == 1 then
    let ok : Bool :=
      w.sched.now == 1 && w.sched.park hi == .blocked && w.sched.current == some lo &&
      (ts.slot 0).due == false
    { world := w, timers := ts, phase := 2, code := if ok then 2 else 9 }
  else if s.phase == 2 then
    let ok : Bool :=
      w.sched.now == 2 && (ts.slot 0).due == true && (ts.slot 0).active == false &&
      w.sched.current == some hi && w.sched.park hi == .alive
    { world := w, timers := ts, phase := 3, code := if ok then 4 else 9 }
  else
    s

def event (s : State) (ev : UInt32) : State :=
  if ev == 1 then start s
  else if ev == 2 then onTick s
  else { s with code := 9 }

def trace : List UInt32 :=
  let s1 := event init 1
  let s2 := event s1 2
  let s3 := event s2 2
  [s1.code, s2.code, s3.code]

@[export vos_c3_init]
def c3Init : State := init

@[export vos_c3_event]
def c3Event (s : State) (ev : UInt32) : State := event s ev

@[export vos_c3_code]
def c3Code (s : State) : UInt32 := s.code

end Vos.Target.C3Demo

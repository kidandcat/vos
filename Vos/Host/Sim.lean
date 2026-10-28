import Vos.Hal.Port
import Vos.Kernel

/-!
Host target: the kernel runs against `Sched.now`, which advances only when
the test calls `tick`. There is no wall clock and no thread.
-/
namespace Vos.Host

open Vos
open Vos.Kernel
open Vos.Sched

variable {α : Type} {nt nq cap : Nat}

def spawn (w : World α nt nq cap) (p : Policy) (prio : Nat) :
    World α nt nq cap × Option (Fin nt) :=
  let (s, id) := Sched.spawn w.sched p prio
  ({ w with sched := s }, id)

def yield (w : World α nt nq cap) (p : Policy) : World α nt nq cap :=
  { w with sched := yieldTask w.sched p }

def delay (w : World α nt nq cap) (p : Policy) (dt : Nat) : World α nt nq cap :=
  { w with sched := Sched.delay w.sched p dt }

def tick (w : World α nt nq cap) (p : Policy) : World α nt nq cap :=
  { w with sched := Sched.tick w.sched p }

def unblock (w : World α nt nq cap) (p : Policy) (i : Fin nt) : World α nt nq cap :=
  { w with sched := Sched.unblock w.sched p i }

def exit (w : World α nt nq cap) (p : Policy) : World α nt nq cap :=
  { w with sched := exitTask w.sched p }

def portOf (w : World α nt nq cap) : Vos.Hal.Port :=
  { Vos.Hal.host with name := s!"host:{w.sched.now}" }

/-- Two tasks, one queue, one delay. The high-priority task sends, sleeps two
ticks, and is running again when the deadline is reached. The low-priority
task receives the message while the other is asleep. -/
def demoOk : Bool :=
  let p : Policy := .priority
  let w : World Nat 2 1 4 := World.empty Nat 2 1 4
  let q : Fin 1 := 0
  let (w, id0) := spawn w p 1
  let (w, id1) := spawn w p 5
  match id0, id1 with
  | some t0, some t1 =>
    let w := send w p q 41
    let sent := (w.qs q).items == [41] && w.sched.current == some t1
    let w := delay w p 2
    let slept := w.sched.current == some t0 && w.sched.park t1 == .blocked &&
      w.sched.deadline t1 == 2 && w.sched.now == 0
    let (w, got) := recv w p q
    let took := got == some 41 && (w.qs q).items == [] && w.sched.current == some t0
    let w := tick w p
    let early := w.sched.now == 1 && w.sched.park t1 == .blocked && w.sched.current == some t0
    let w := tick w p
    let due := w.sched.now == 2 && w.sched.current == some t1 && w.sched.park t1 == .alive
    sent && slept && took && early && due
  | _, _ => false

end Vos.Host

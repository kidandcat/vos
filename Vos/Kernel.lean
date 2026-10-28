import Vos.Queue
import Vos.Sched
import Vos.Spec.Queue

/-!
One kernel step: the running task sends or receives on a bounded queue.

A send that fits is appended. If a task is waiting to receive, it is given
the head of the queue (the oldest message) and made ready. A send that does
not fit stays in that task's single pending slot and the task blocks; the
queue is unchanged. A receive on a non-empty queue, with nobody waiting to
send, returns the head and leaves the tail. A receive on an empty queue
blocks the running task. Pending and inbox slots are one message each, so
this path does not allocate.
-/
namespace Vos.Kernel

open Vos
open Vos.Sched

variable {α : Type} {nt nq cap : Nat}

structure World (α : Type) (nt nq cap : Nat) where
  sched : Sched nt
  qs : Fin nq → Vos.Queue.Queue α cap
  recvWait : Fin nq → List (Fin nt)
  sendWait : Fin nq → List (Fin nt)
  pending : Fin nt → Option α
  inbox : Fin nt → Option α

def World.empty (α : Type) (nt nq cap : Nat) : World α nt nq cap where
  sched := Sched.empty nt
  qs := fun _ => Vos.Queue.empty cap
  recvWait := fun _ => []
  sendWait := fun _ => []
  pending := fun _ => none
  inbox := fun _ => none

def setQ (w : World α nt nq cap) (qi : Fin nq) (q : Vos.Queue.Queue α cap) : World α nt nq cap :=
  { w with qs := fun j => if j = qi then q else w.qs j }

/-- Move one blocked sender's pending message into `qi`, if there is room. -/
def release (w : World α nt nq cap) (p : Policy) (qi : Fin nq) : World α nt nq cap :=
  match w.sendWait qi with
  | [] => w
  | s :: ss =>
    match w.pending s with
    | none => w
    | some m =>
      let (q, ok) := Vos.Queue.enqueue (w.qs qi) m
      if ok then
        let w := setQ w qi q
        let w := { w with
          pending := fun j => if j = s then none else w.pending j
          sendWait := fun j => if j = qi then ss else w.sendWait j }
        { w with sched := unblock w.sched p s }
      else
        w

def send (w : World α nt nq cap) (p : Policy) (qi : Fin nq) (m : α) : World α nt nq cap :=
  match w.sched.current with
  | none => w
  | some i =>
    if (w.qs qi).items.length < cap then
      let (q1, _) := Vos.Queue.enqueue (w.qs qi) m
      let w := setQ w qi q1
      match w.recvWait qi with
      | [] => w
      | r :: rs =>
        let (q2, v) := Vos.Queue.dequeue (w.qs qi)
        let w := setQ w qi q2
        let w := { w with
          recvWait := fun j => if j = qi then rs else w.recvWait j
          inbox := fun j => if j = r then v else w.inbox j }
        { w with sched := unblock w.sched p r }
    else
      let w := { w with
        pending := fun j => if j = i then some m else w.pending j
        sendWait := fun j => if j = qi then w.sendWait qi ++ [i] else w.sendWait j }
      { w with sched := block w.sched p }

def recv (w : World α nt nq cap) (p : Policy) (qi : Fin nq) : World α nt nq cap × Option α :=
  match w.sched.current with
  | none => (w, none)
  | some i =>
    match w.inbox i with
    | some m =>
      ({ w with inbox := fun j => if j = i then none else w.inbox j }, some m)
    | none =>
      let (q1, v) := Vos.Queue.dequeue (w.qs qi)
      match v with
      | some m =>
        (release (setQ w qi q1) p qi, some m)
      | none =>
        let w := { w with
          recvWait := fun j => if j = qi then w.recvWait qi ++ [i] else w.recvWait j }
        ({ w with sched := block w.sched p }, none)

theorem send_room (w : World α nt nq cap) (p : Policy) (qi : Fin nq) (m : α)
    (i : Fin nt) (hc : w.sched.current = some i)
    (hroom : (w.qs qi).items.length < cap) (hw : w.recvWait qi = []) :
    ((send w p qi m).qs qi).items = (w.qs qi).items ++ [m] ∧
      (send w p qi m).sched = w.sched := by
  have hacc := Vos.Spec.Queue.enq_accept (items := (w.qs qi).items) (a := m) (cap := cap) hroom
  simp [send, hc, hroom, hw, setQ, Vos.Queue.enqueue, Vos.Queue.enqueue_spec, hacc]

theorem send_to_waiter (w : World α nt nq cap) (p : Policy) (qi : Fin nq) (m : α)
    (i r : Fin nt) (rs : List (Fin nt)) (hc : w.sched.current = some i)
    (hempty : (w.qs qi).items = []) (hcap : cap > 0)
    (hw : w.recvWait qi = r :: rs) :
    ((send w p qi m).qs qi).items = [] ∧ (send w p qi m).inbox r = some m ∧
      (send w p qi m).recvWait qi = rs := by
  have hroom : (w.qs qi).items.length < cap := by simp [hempty]; omega
  have hacc := Vos.Spec.Queue.enq_accept (items := (w.qs qi).items) (a := m) (cap := cap) hroom
  simp [hempty] at hacc
  simp [send, hc, hroom, hw, hcap, hempty, setQ, Vos.Queue.enqueue, Vos.Queue.dequeue,
    Vos.Queue.enqueue_spec, Vos.Queue.dequeue_spec, hacc, Vos.Spec.Queue.deq_head]

theorem send_full (w : World α nt nq cap) (p : Policy) (qi : Fin nq) (m : α)
    (i : Fin nt) (hc : w.sched.current = some i)
    (hfull : ¬ (w.qs qi).items.length < cap) (hinv : Inv w.sched) :
    (send w p qi m).qs qi = w.qs qi ∧ (send w p qi m).pending i = some m ∧
      (send w p qi m).sched.park i = .blocked ∧ Inv (send w p qi m).sched := by
  have hpark : (blockCurrent w.sched 0 false).park i = .blocked := by
    simp [blockCurrent, hc]
  have hf := dispatch_same_fields (blockCurrent w.sched 0 false) p i
  have hinv' := block_inv w.sched hinv p
  simp [send, hc, hfull, block]
  exact And.intro (by simpa [hf.1] using hpark) hinv'

theorem recv_head (w : World α nt nq cap) (p : Policy) (qi : Fin nq)
    (i : Fin nt) (a : α) (rest : List α) (hc : w.sched.current = some i)
    (hin : w.inbox i = none) (hitems : (w.qs qi).items = a :: rest)
    (hsend : w.sendWait qi = []) :
    (recv w p qi).2 = some a ∧ ((recv w p qi).1.qs qi).items = rest ∧
      (recv w p qi).1.sched = w.sched := by
  simp [recv, hc, hin, Vos.Queue.dequeue, Vos.Queue.dequeue_spec, hitems,
    Vos.Spec.Queue.deq_head, release, hsend, setQ]

/-- The receiver `send` hands the message to is the task `unblock` readies. -/
theorem send_readies_waiter (w : World α nt nq cap) (p : Policy) (qi : Fin nq) (m : α)
    (i r : Fin nt) (rs : List (Fin nt)) (hc : w.sched.current = some i)
    (hempty : (w.qs qi).items = []) (hcap : cap > 0)
    (hw : w.recvWait qi = r :: rs) (hblk : w.sched.park r = .blocked)
    (hinv : Inv w.sched) :
    (send w p qi m).sched.park r = .alive ∧
      (r ∈ (send w p qi m).sched.ready ∨ (send w p qi m).sched.current = some r) ∧
      Inv (send w p qi m).sched := by
  have hroom : (w.qs qi).items.length < cap := by simp [hempty]; omega
  have hacc := Vos.Spec.Queue.enq_accept (items := (w.qs qi).items) (a := m) (cap := cap) hroom
  simp [hempty] at hacc
  have hs : (send w p qi m).sched = unblock w.sched p r := by
    simp [send, hc, hroom, hw, hcap, hempty, setQ, Vos.Queue.enqueue, Vos.Queue.dequeue,
      Vos.Queue.enqueue_spec, Vos.Queue.dequeue_spec, hacc, Vos.Spec.Queue.deq_head]
  simpa [hs] using unblock_readies w.sched hinv p r hblk

theorem recv_empty (w : World α nt nq cap) (p : Policy) (qi : Fin nq)
    (i : Fin nt) (hc : w.sched.current = some i) (hin : w.inbox i = none)
    (hempty : (w.qs qi).items = []) (hinv : Inv w.sched) :
    (recv w p qi).2 = none ∧ ((recv w p qi).1.qs qi).items = [] ∧
      (recv w p qi).1.sched.park i = .blocked ∧ Inv (recv w p qi).1.sched := by
  have hpark : (blockCurrent w.sched 0 false).park i = .blocked := by
    simp [blockCurrent, hc]
  have hf := dispatch_same_fields (blockCurrent w.sched 0 false) p i
  have hinv' := block_inv w.sched hinv p
  simp [recv, hc, hin, Vos.Queue.dequeue, Vos.Queue.dequeue_spec, hempty,
    Vos.Spec.Queue.deq_empty, block]
  exact And.intro (by simpa [hf.1] using hpark) hinv'

end Vos.Kernel

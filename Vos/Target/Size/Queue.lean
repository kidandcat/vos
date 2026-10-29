import Vos.Queue

/-! Footprint probe: `Vos.Queue` only. Not a theorem. -/
namespace Vos.Target.Size.Queue

@[export vos_size_queue]
def sizeQueue (_ : UInt32) : UInt32 :=
  let (q, ok) := Vos.Queue.enqueue (Vos.Queue.empty 4) (41 : Nat)
  let (q, v) := Vos.Queue.dequeue q
  if ok && v == some 41 && q.items == [] then 1 else 0

end Vos.Target.Size.Queue

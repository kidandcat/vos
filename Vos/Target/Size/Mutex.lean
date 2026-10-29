import Vos.Mutex

/-! Footprint probe: `Vos.Mutex`, which imports `Vos.Sched`. Not a theorem. -/
namespace Vos.Target.Size.Mutex

open Vos

@[export vos_size_mutex]
def sizeMutex (_ : UInt32) : UInt32 :=
  let p : Policy := .priority
  let (s, id) := Sched.spawn (Sched.empty 1) p 1
  match id with
  | none => 0
  | some _ =>
    let (m, _, ok) := Vos.Mutex.lock (Vos.Mutex.Mutex.empty 1) s p
    if ok && m.owner == some 0 then 1 else 0

end Vos.Target.Size.Mutex

import Vos.Sem

/-! Footprint probe: `Vos.Sem`, which imports `Vos.Sched`. Not a theorem. -/
namespace Vos.Target.Size.Sem

open Vos

@[export vos_size_sem]
def sizeSem (_ : UInt32) : UInt32 :=
  let p : Policy := .priority
  let (s, id) := Sched.spawn (Sched.empty 1) p 1
  match id with
  | none => 0
  | some _ =>
    let (sem, _, ok) := Vos.Sem.give (Vos.Sem.Sem.empty 1 2) s p
    if ok && sem.count == 1 then 1 else 0

end Vos.Target.Size.Sem

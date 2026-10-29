import Vos.Sched

/-! Footprint probe: `Vos.Sched` only. Not a theorem. -/
namespace Vos.Target.Size.Sched

open Vos

@[export vos_size_sched]
def sizeSched (_ : UInt32) : UInt32 :=
  let p : Policy := .priority
  let (s, id) := Sched.spawn (Sched.empty 1) p 1
  if id == some 0 && s.current == some 0 then 1 else 0

end Vos.Target.Size.Sched

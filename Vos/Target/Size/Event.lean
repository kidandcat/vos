import Vos.Event

/-! Footprint probe: `Vos.Event`, which imports `Vos.Sched`. Not a theorem. -/
namespace Vos.Target.Size.Event

open Vos

def mask0 : Event.Bits := fun i => i == (0 : Fin 32)

@[export vos_size_event]
def sizeEvent (_ : UInt32) : UInt32 :=
  let p : Policy := .priority
  let (g, _) := Event.setBits (Event.Group.empty 1) (Sched.empty 1) p mask0
  if g.bits (0 : Fin 32) == true && g.bits (1 : Fin 32) == false then 1 else 0

end Vos.Target.Size.Event

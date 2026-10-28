import Vos.Timer

/-! Footprint probe: `Vos.Timer` only. Not a theorem. -/
namespace Vos.Target.Size.Timer

@[export vos_size_timer]
def sizeTimer (_ : UInt32) : UInt32 :=
  let ts := Vos.Timer.tick (Vos.Timer.start (Vos.Timer.Timers.empty 1) 0 1 0)
  if (ts.slot 0).due == true && (ts.slot 0).active == false then 1 else 0

end Vos.Target.Size.Timer

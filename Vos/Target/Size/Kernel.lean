import Vos.Kernel

/-!
Footprint probe: `Vos.Kernel`. That import also pulls `Vos.Queue` and
`Vos.Sched`. Not a theorem.
-/
namespace Vos.Target.Size.Kernel

open Vos

@[export vos_size_kernel]
def sizeKernel (_ : UInt32) : UInt32 :=
  let p : Policy := .priority
  let w0 := Kernel.World.empty Nat 1 1 4
  let (sched, id) := Sched.spawn w0.sched p 1
  let w := { w0 with sched := sched }
  match id with
  | none => 0
  | some _ =>
    let w := Kernel.send w p 0 41
    let (_, got) := Kernel.recv w p 0
    if got == some 41 then 1 else 0

end Vos.Target.Size.Kernel

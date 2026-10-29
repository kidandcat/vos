/-!
Baseline for the footprint script. Opting in nothing beyond the prelude.
The export is what the linker keeps. It is not a kernel theorem.
-/
namespace Vos.Target.Size.Empty

@[export vos_size_empty]
def sizeEmpty (_ : UInt32) : UInt32 := 0

end Vos.Target.Size.Empty

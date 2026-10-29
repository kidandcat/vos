/-!
Opt-in home for VM and AI-agent sandboxing.

The kernel does not import this module. `Vos.lean` does not import it.
`scripts/check-firmware-boundary.sh` fails if any other file under `Vos/`,
or the C bundled into an ESP32 image, refers to `Vos.Sandbox` or `Vos.Agent`.
A firmware target that needs a sandbox imports it itself. The core must not.
-/
namespace Vos.Sandbox

/-- Present so the boundary check has a module to exclude. Not a kernel value. -/
def marker : Nat := 0

end Vos.Sandbox

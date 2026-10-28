/-!
The seam between the portable kernel and a target.

PR1 implements no peripheral and no interrupt shim. `host` records that the
simulator has a clock and may call `Vos.Sched.tick` between steps, which is
what makes a priority policy preemptive in the model. Later targets fill in
the same record and a C shim; those shims are outside the proofs.
-/
namespace Vos.Hal

structure Caps where
  time : Bool := true
  /-- The target calls the kernel from a timer, so `tick` can preempt. -/
  tickInterrupt : Bool := false
  gpio : Bool := false
  spi : Bool := false
  i2c : Bool := false
  uart : Bool := false
  storage : Bool := false
  radio : Bool := false
  deriving DecidableEq, Repr

structure Port where
  name : String
  caps : Caps
  deriving Repr

def host : Port where
  name := "host"
  caps := { time := true, tickInterrupt := true }

end Vos.Hal

/-!
The seam between the portable kernel and a target.

`host` records that the simulator has a clock and may call `Vos.Sched.tick`
between steps. The ESP32-C3 shim in `target/esp32c3` implements event wait
and log; GPIO, SPI, I2C, UART, NVS, and the radio hook are declared in
`vos_hal.h` and return -1. The proved kernel does not call them. The C3 demo
is a pure function of the events the shim posts (`Vos.Target.C3Demo`).
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

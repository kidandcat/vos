/-!
The seam between the portable kernel and a target.

`host` records that the simulator has a clock and may call `Vos.Sched.tick`
between steps. `esp32c3` and `esp32s3` record the hooks the shim in
`target/idf` calls into ESP-IDF: GPIO, UART, and NVS. QEMU read GPIO pin 4
back as 0 after it was set to 1, so the level is not checked. SPI, I2C, and
the radio hook return -1. `tickInterrupt` is false because the `esp_timer`
callback only posts on a FreeRTOS queue; it does not call the kernel.

These flags are a description of the shim. They are not a proof that the C
matches them. The proved kernel does not call the hooks. The demo is a pure
function of the events the shim posts (`Vos.Target.C3Demo`).
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

/-- What `target/idf/vos_hal.c` implements on both chips. -/
def espIdf : Caps where
  time := true
  tickInterrupt := false
  gpio := true
  uart := true
  storage := true

def esp32c3 : Port where
  name := "esp32c3"
  caps := espIdf

def esp32s3 : Port where
  name := "esp32s3"
  caps := espIdf

end Vos.Hal

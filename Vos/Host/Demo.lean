import Vos.Host.Sim

def main : IO UInt32 := do
  if Vos.Host.demoOk then
    IO.println "vos demo ok: priority send, delay 2, recv, wake at deadline"
    return 0
  else
    IO.eprintln "vos demo failed"
    return 1

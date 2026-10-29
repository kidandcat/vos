# Security

vos is a kernel model and a set of small firmware images. A bug in the model, the C shim, or a boot path can still matter once someone flashes a board.

## Reporting

Report a vulnerability through [GitHub private vulnerability reporting](https://github.com/kidandcat/vos/security/advisories/new) on this repository. Do not open a public issue for a vulnerability that is still unfixed.

Include what you ran, the commit, and the log. If you did not run it on hardware, say so.

## What this policy does not cover

The proofs trust the Lean kernel, the compiler, and the runtime. They do not make the C shim, ESP-IDF, FreeRTOS, QEMU, or a chip a trusted component. A mismatch between `Vos.Arch.Mtime` and the RV32 image is a bug to report. It is not, by itself, a broken proof.

The CYW43439 firmware blob is not in this repository. Do not send it as part of a report.

## Secrets

Do not commit credentials, API tokens, or private keys. CI does not need them.

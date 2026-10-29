# Generic RV32 image for QEMU virt. march is rv32imac_zicsr, a subset of the
# Hazard3 configuration in the RP2350 datasheet section 3.8. The link
# address is QEMU virt RAM, not the RP2350 map.
# Do not use $(CC): a host cc is often already in the environment.
RV32_CC ?= riscv64-unknown-elf-gcc
# zicsr is named explicitly. GCC 13's assembler rejects csrr without it.
# This is still a subset of the RP2350 Hazard3 string in datasheet section 3.8.
CFLAGS := -march=rv32imac_zicsr -mabi=ilp32 -mcmodel=medany -ffreestanding -fno-builtin -fno-stack-protector -fomit-frame-pointer -nostdlib -O1 -Wall -Wextra
LDFLAGS := -nostdlib -T link.ld -Wl,--gc-sections

.PHONY: all clean
all: vos-rv32.elf

vos-rv32.elf: start.S main.c link.ld
	$(RV32_CC) $(CFLAGS) $(LDFLAGS) start.S main.c -o $@

clean:
	rm -f vos-rv32.elf

/* Generic RV32 startup for QEMU virt. Not an RP2350 image. */
.section .text.init
.globl _start
_start:
  la sp, _stack_top
  la a0, _bss_start
  la a1, _bss_end
1:
  bgeu a0, a1, 2f
  sw zero, 0(a0)
  addi a0, a0, 4
  j 1b
2:
  call main
3:
  j 3b

.align 4
.globl trap_entry
trap_entry:
  addi sp, sp, -64
  sw ra, 60(sp)
  sw t0, 56(sp)
  sw t1, 52(sp)
  sw t2, 48(sp)
  sw a0, 44(sp)
  sw a1, 40(sp)
  sw a2, 36(sp)
  sw a3, 32(sp)
  sw a4, 28(sp)
  sw a5, 24(sp)
  sw a6, 20(sp)
  sw a7, 16(sp)
  call handle_trap
  lw ra, 60(sp)
  lw t0, 56(sp)
  lw t1, 52(sp)
  lw t2, 48(sp)
  lw a0, 44(sp)
  lw a1, 40(sp)
  lw a2, 36(sp)
  lw a3, 32(sp)
  lw a4, 28(sp)
  lw a5, 24(sp)
  lw a6, 20(sp)
  lw a7, 16(sp)
  addi sp, sp, 64
  mret

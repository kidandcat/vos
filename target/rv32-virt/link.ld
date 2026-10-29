/* QEMU virt RAM. This is not the RP2350 memory map. */
ENTRY(_start)
MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}
SECTIONS
{
  .text : {
    *(.text.init)
    *(.text*)
  } > RAM
  .rodata : { *(.rodata*) } > RAM
  .data : { *(.data*) } > RAM
  .bss : {
    _bss_start = .;
    *(.bss*)
    *(COMMON)
    _bss_end = .;
  } > RAM
  . = ALIGN(16);
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}

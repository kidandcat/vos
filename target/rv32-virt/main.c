/*
 * Generic RV32 on QEMU's virt machine. Not an RP2350 boot.
 *
 * UART is the 16550 at 0x10000000. The timer is the CLINT mtime/mtimecmp
 * pair, which is the same compare the Lean model calls `take`: pending
 * while cmp <= time, and the handler moves cmp forward by a period.
 * The RP2350 puts that compare in the SIO block instead. This binary does
 * not touch that address.
 */
#include <stdint.h>

#define UART 0x10000000u
#define CLINT_MTIMECMP 0x02004000u
#define CLINT_MTIME 0x0200BFF8u
#define PERIOD 5000u
#define TIMER_TRAP 0x80000007u

volatile uint32_t g_ticks;

static void putc(char c) {
    volatile uint8_t *thr = (volatile uint8_t *)UART;
    *thr = (uint8_t)c;
}

static void puts(const char *s) {
    while (*s) putc(*s++);
}

static uint32_t read_mtime(void) {
    return *(volatile uint32_t *)CLINT_MTIME;
}

static void write_mtimecmp(uint32_t v) {
    *(volatile uint32_t *)CLINT_MTIMECMP = v;
}

void handle_trap(void) {
    uint32_t cause;
    __asm__ volatile("csrr %0, mcause" : "=r"(cause));
    if (cause == TIMER_TRAP) {
        write_mtimecmp(read_mtime() + PERIOD);
        g_ticks++;
    }
}

static void enable_timer(void) {
    uintptr_t vec;
    __asm__ volatile("la %0, trap_entry" : "=r"(vec));
    __asm__ volatile("csrw mtvec, %0" :: "r"(vec));
    write_mtimecmp(read_mtime() + PERIOD);
    __asm__ volatile("csrs mie, %0" :: "r"(0x80));
    __asm__ volatile("csrs mstatus, %0" :: "r"(0x8));
}

void main(void) {
    puts("vos rv32: boot\n");
    enable_timer();
    while (g_ticks < 3) {
        __asm__ volatile("wfi");
    }
    puts("vos rv32: tick\n");
    puts("vos rv32: tick\n");
    puts("vos rv32: tick\n");
    puts("vos rv32: virt ok\n");
    for (;;) {
    }
}

/*
 * Host stand-in for the ESP32-C3 shim. The bundler links this so the exported
 * demo is not garbage-collected. Running the binary prints the same three
 * lines the QEMU script checks.
 */
#include <stdint.h>
#include <stdio.h>
#include <lean/lean.h>

extern void vos_rt_init(void);
extern lean_object *vos_c3_init;
extern lean_object *vos_c3_event(lean_object *s, uint32_t ev);
extern uint32_t vos_c3_code(lean_object *s);

static int g_fail;

static lean_object *step(lean_object *s, uint32_t ev) {
    s = vos_c3_event(s, ev);
    lean_inc(s);
    uint32_t c = vos_c3_code(s);
    switch (c) {
    case 1: printf("vos c3: sent 41\n"); break;
    case 2: printf("vos c3: timer not due\n"); break;
    case 4: printf("vos c3: demo ok\n"); break;
    default:
        printf("vos c3: fail %u\n", (unsigned)c);
        g_fail = 1;
        break;
    }
    return s;
}

int main(void) {
    vos_rt_init();
    lean_inc(vos_c3_init);
    lean_object *s = step(vos_c3_init, 1);
    s = step(s, 2);
    s = step(s, 2);
    lean_dec(s);
    return g_fail;
}

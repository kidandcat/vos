/*
 * One FreeRTOS task runs Lean. An esp_timer callback posts ticks onto an
 * ESP-IDF queue and does not enter the kernel. IDF's timer task is not a
 * vos task. VOS_TAG is "c3" or "s3"; the exported demo is the same function.
 */
#include <stdio.h>

#include "esp_err.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "vos_hal.h"

#include <lean/lean.h>

#ifndef VOS_TAG
#define VOS_TAG "c3"
#endif

extern void vos_rt_init(void);
extern lean_object *vos_c3_init;
extern lean_object *vos_c3_event(lean_object *s, uint32_t ev);
extern uint32_t vos_c3_code(lean_object *s);

static QueueHandle_t events;

void uvl_on_panic(const char *msg, int fatal) {
    printf("vos %s: panic%s: %s\n", VOS_TAG, fatal ? " fatal" : "", msg ? msg : "");
    if (fatal) {
        for (;;) {
            vTaskDelay(pdMS_TO_TICKS(1000));
        }
    }
}

void vos_hal_log(const char *line) { printf("%s\n", line); }

int vos_hal_wait(uint32_t *ev) {
    if (xQueueReceive(events, ev, portMAX_DELAY) != pdTRUE) return -1;
    return 0;
}

static void print_code(uint32_t c) {
    switch (c) {
    case 1: printf("vos %s: sent 41\n", VOS_TAG); break;
    case 2: printf("vos %s: timer not due\n", VOS_TAG); break;
    case 4: printf("vos %s: demo ok\n", VOS_TAG); break;
    default: printf("vos %s: fail %u\n", VOS_TAG, (unsigned)c); break;
    }
}

static void post_tick(void *arg) {
    (void)arg;
    uint32_t ev = 2;
    xQueueSend(events, &ev, 0);
}

/* `event` consumes `s` and returns a new reference. `code` consumes one too. */
static lean_object *step(lean_object *s, uint32_t ev, uint32_t *code) {
    s = vos_c3_event(s, ev);
    lean_inc(s);
    *code = vos_c3_code(s);
    print_code(*code);
    return s;
}

void app_main(void) {
    if (vos_hal_selftest() != 0) {
        printf("vos %s: hal fail\n", VOS_TAG);
        return;
    }
    events = xQueueCreate(8, sizeof(uint32_t));
    esp_timer_handle_t timer = NULL;
    const esp_timer_create_args_t args = {
        .callback = post_tick,
        .name = "vos",
    };
    ESP_ERROR_CHECK(esp_timer_create(&args, &timer));
    uint32_t start = 1;
    xQueueSend(events, &start, portMAX_DELAY);
    ESP_ERROR_CHECK(esp_timer_start_periodic(timer, 100 * 1000));

    vos_rt_init();
    lean_inc(vos_c3_init);
    lean_object *s = vos_c3_init;
    for (;;) {
        uint32_t ev = 0;
        uint32_t code = 0;
        if (vos_hal_wait(&ev) != 0) continue;
        s = step(s, ev, &code);
        if (code == 4 || code == 9) {
            esp_timer_stop(timer);
            lean_dec(s);
            break;
        }
    }
}

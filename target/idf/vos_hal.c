#include "vos_hal.h"

#include <stdio.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/uart.h"
#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"

#ifndef VOS_TAG
#define VOS_TAG "c3"
#endif

static void note(const char *msg) { printf("vos %s: %s\n", VOS_TAG, msg); }

static int nvs_ready(void) {
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        if (nvs_flash_erase() != ESP_OK) return -1;
        err = nvs_flash_init();
    }
    return err == ESP_OK ? 0 : -1;
}

int vos_hal_gpio_set(int pin, int level) {
    if (pin < 0 || pin >= 48) return -1;
    gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << pin,
        .mode = GPIO_MODE_INPUT_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    if (gpio_config(&cfg) != ESP_OK) return -1;
    if (gpio_set_level((gpio_num_t)pin, level ? 1 : 0) != ESP_OK) return -1;
    return 0;
}

int vos_hal_gpio_get(int pin, int *level) {
    if (pin < 0 || pin >= 48 || level == 0) return -1;
    *level = gpio_get_level((gpio_num_t)pin);
    return 0;
}

int vos_hal_spi_xfer(const uint8_t *tx, uint8_t *rx, size_t n) {
    (void)tx;
    (void)rx;
    (void)n;
    return -1;
}

int vos_hal_i2c_write(uint8_t addr, const uint8_t *bytes, size_t n) {
    (void)addr;
    (void)bytes;
    (void)n;
    return -1;
}

int vos_hal_uart_write(const uint8_t *bytes, size_t n) {
    if (bytes == 0 && n != 0) return -1;
    /* The console driver already installed UART0. Install is a no-op then. */
    if (uart_is_driver_installed(UART_NUM_0) == false) {
        if (uart_driver_install(UART_NUM_0, 256, 0, 0, NULL, 0) != ESP_OK) return -1;
    }
    int wrote = uart_write_bytes(UART_NUM_0, (const char *)bytes, n);
    if (wrote != (int)n) return -1;
    if (uart_wait_tx_done(UART_NUM_0, pdMS_TO_TICKS(200)) != ESP_OK) return -1;
    return 0;
}

int vos_hal_nvs_set(const char *key, const uint8_t *bytes, size_t n) {
    if (key == 0 || (bytes == 0 && n != 0) || nvs_ready() != 0) return -1;
    nvs_handle_t h;
    if (nvs_open("vos", NVS_READWRITE, &h) != ESP_OK) return -1;
    esp_err_t err = nvs_set_blob(h, key, bytes, n);
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
    return err == ESP_OK ? 0 : -1;
}

int vos_hal_nvs_get(const char *key, uint8_t *out, size_t *n) {
    if (key == 0 || out == 0 || n == 0 || *n == 0 || nvs_ready() != 0) return -1;
    nvs_handle_t h;
    if (nvs_open("vos", NVS_READONLY, &h) != ESP_OK) return -1;
    esp_err_t err = nvs_get_blob(h, key, out, n);
    nvs_close(h);
    return err == ESP_OK ? 0 : -1;
}

int vos_hal_radio(const uint8_t *tx, size_t n) {
    (void)tx;
    (void)n;
    return -1;
}

static int check_gpio(void) {
    int level = -1;
    /* The call is the IDF driver. A matching readback is checked when the
     * machine actually returns the latch; esp32c3 QEMU did not. */
    if (vos_hal_gpio_set(4, 1) != 0 || vos_hal_gpio_get(4, &level) != 0) {
        note("hal gpio fail");
        return -1;
    }
    if (level == 1 && vos_hal_gpio_set(4, 0) == 0 && vos_hal_gpio_get(4, &level) == 0 && level == 0) {
        note("hal gpio ok");
        return 0;
    }
    printf("vos %s: hal gpio level unread %d\n", VOS_TAG, level);
    return 0;
}

static int check_uart(void) {
    char buf[48];
    int n = snprintf(buf, sizeof buf, "vos %s: hal uart ok\n", VOS_TAG);
    if (n <= 0 || (size_t)n >= sizeof buf || vos_hal_uart_write((const uint8_t *)buf, (size_t)n) != 0) {
        note("hal uart fail");
        return -1;
    }
    return 0;
}

static int check_nvs(void) {
    const uint8_t stored = 0xA5;
    uint8_t got = 0;
    size_t n = 1;
    if (vos_hal_nvs_set("probe", &stored, 1) != 0 || vos_hal_nvs_get("probe", &got, &n) != 0 ||
        n != 1 || got != stored) {
        note("hal nvs fail");
        return -1;
    }
    note("hal nvs ok");
    return 0;
}

int vos_hal_selftest(void) {
    int rc = 0;
    if (check_uart() != 0) rc = -1;
    if (check_nvs() != 0) rc = -1;
    if (check_gpio() != 0) rc = -1;
    note("hal spi stub");
    note("hal i2c stub");
    note("hal radio stub");
    return rc;
}

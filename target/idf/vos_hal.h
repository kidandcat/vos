/*
 * Port hooks for an ESP-IDF target (ESP32-C3 and ESP32-S3).
 *
 * Implemented, and checked from the QEMU serial log when the boot script
 * sees the matching line:
 *   wait   ESP-IDF queue. The tick source only posts; it does not call Lean.
 *   log    printf, which IDF sends to the console UART.
 *   gpio   gpio_config + gpio_set_level / gpio_get_level. The call is real.
 *          On QEMU esp32c3, get_level did not return the level that was set
 *          (the log says "gpio level unread"). That is not a checked pin.
 *   uart   uart_write_bytes on UART0, the console.
 *   nvs    namespace "vos", blob get/set. The partition is the default nvs.
 *
 * Stubs, returning -1. This QEMU command line has no SPI or I2C slave and no
 * radio peer, so a transfer cannot be checked without hanging the boot on a
 * device that never answers:
 *   spi, i2c, radio.
 */
#pragma once
#include <stddef.h>
#include <stdint.h>

int vos_hal_wait(uint32_t *ev);
void vos_hal_log(const char *line);

int vos_hal_gpio_set(int pin, int level);
int vos_hal_gpio_get(int pin, int *level);
int vos_hal_spi_xfer(const uint8_t *tx, uint8_t *rx, size_t n);
int vos_hal_i2c_write(uint8_t addr, const uint8_t *bytes, size_t n);
int vos_hal_uart_write(const uint8_t *bytes, size_t n);
int vos_hal_nvs_set(const char *key, const uint8_t *bytes, size_t n);
int vos_hal_nvs_get(const char *key, uint8_t *out, size_t *n);
int vos_hal_radio(const uint8_t *tx, size_t n);

/* Prints one line per hook. Returns 0 when uart, nvs, and gpio passed. */
int vos_hal_selftest(void);

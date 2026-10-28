/*
 * Port hooks for a vos target.
 *
 * The C3 shim implements wait (an ESP-IDF queue) and log. The tick source is
 * an esp_timer callback that only posts to that queue. GPIO, SPI, I2C, UART,
 * NVS, and the radio hook are the names later targets fill in. On C3 they
 * return -1 and the demo does not call them.
 */
#pragma once
#include <stddef.h>
#include <stdint.h>

/* Block until the port has an event. Writes 1 (start) or 2 (tick). */
int vos_hal_wait(uint32_t *ev);

void vos_hal_log(const char *line);

int vos_hal_gpio_set(int pin, int level);
int vos_hal_spi_xfer(const uint8_t *tx, uint8_t *rx, size_t n);
int vos_hal_i2c_write(uint8_t addr, const uint8_t *bytes, size_t n);
int vos_hal_uart_write(const uint8_t *bytes, size_t n);
int vos_hal_nvs_get(const char *key, uint8_t *out, size_t *n);
int vos_hal_radio(const uint8_t *tx, size_t n);

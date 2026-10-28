/*
 * The vendored uvl_rt.c includes this name. It only needs the heap-stats
 * struct and the panic hook. This is not UVL's application ABI.
 */
#pragma once
#include <stddef.h>

typedef struct {
    size_t capacity;
    size_t live;
    size_t peak_live;
    size_t peak_top;
    size_t allocations;
    size_t coalesces;
} uvl_heap_info;

void uvl_heap_stats(uvl_heap_info *out);
void uvl_on_panic(const char *msg, int fatal);

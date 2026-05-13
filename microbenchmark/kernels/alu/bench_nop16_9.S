/*
 * bench_nop16_9 — 9 × 16-bit Thumb NOPs (nop.n) via BENCH harness.
 *
 * Off-grid sweep point used to ask: does `inner` count up to the last
 * kernel instruction *starting* fetch, or *finishing* execution? At
 * slope=1.0 c/NOP on a cache-on variant, going from 8 NOPs to 9 NOPs
 * should bump `inner` by exactly 1 cycle if the 9th NOP fully retires
 * inside the DWT snap window.
 */
#include "harness.h"

    BENCH
        .rept 9
        nop.n
        .endr
    END_BENCH

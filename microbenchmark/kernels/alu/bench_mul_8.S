/*
 * bench_mul_8 — 8 × mul r12, r1, r2 via BENCH harness.
 *
 * 32-bit Thumb-2 MUL T2 encoding (separate dest, no flag-set). Cortex-M4 = 1 cycle per errata. r12 is harness-free scratch.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        movw r1, #0x1234
        movw r2, #0x0005
        .rept 8
        mul r12, r1, r2
        .endr
    END_BENCH

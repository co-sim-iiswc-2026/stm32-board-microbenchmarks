/*
 * bench_lsl_reg_16 — 16 × lsl.w r12, r1, r2 via BENCH harness.
 *
 * Logical shift left by register (T2 32-bit Thumb-2 form). Distinct decoder path from LSL by immediate. Cortex-M4 = 1 cycle.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        movw r1, #0x00FF
        movs r2, #4
        .rept 16
        lsl.w r12, r1, r2
        .endr
    END_BENCH

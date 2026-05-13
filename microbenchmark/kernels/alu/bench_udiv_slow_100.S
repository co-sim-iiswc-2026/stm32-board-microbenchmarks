/*
 * bench_udiv_slow_100 — 100 × udiv r12, r1, r2 via BENCH harness.
 *
 * Unsigned integer divide, Slow case: full-width dividend, divisor=1 → worst-case ~12c. r1=0xffffffff, r2=0x00000001. r12 is harness-free caller-saved scratch.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        movw r1, #0xffff
        movt r1, #0xffff
        movw r2, #0x0001
        movt r2, #0x0000
        .rept 100
        udiv r12, r1, r2
        .endr
    END_BENCH

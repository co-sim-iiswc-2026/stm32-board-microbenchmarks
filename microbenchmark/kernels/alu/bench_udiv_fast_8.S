/*
 * bench_udiv_fast_8 — 8 × udiv r12, r1, r2 via BENCH harness.
 *
 * Unsigned integer divide, Fast case: small dividend, large divisor → early termination ~2c. r1=0x00000001, r2=0xfffffffe. r12 is harness-free caller-saved scratch.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        movw r1, #0x0001
        movt r1, #0x0000
        movw r2, #0xfffe
        movt r2, #0xffff
        .rept 8
        udiv r12, r1, r2
        .endr
    END_BENCH

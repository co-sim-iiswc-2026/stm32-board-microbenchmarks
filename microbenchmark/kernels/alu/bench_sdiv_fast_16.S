/*
 * bench_sdiv_fast_16 — 16 × sdiv r12, r1, r2 via BENCH harness.
 *
 * Signed integer divide, Fast case: small dividend, large divisor → early termination ~2c. r1=0x00000001, r2=0xfffffffe. r12 is harness-free caller-saved scratch.
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
        .rept 16
        sdiv r12, r1, r2
        .endr
    END_BENCH

/*
 * bench_udiv_mid_100 — 100 × udiv r12, r1, r2 via BENCH harness.
 *
 * Unsigned integer divide, Mid case: dividend has ≈24 significant bits, divisor 5 → ~7c. r1=0x00ffffff, r2=0x00000010. r12 is harness-free caller-saved scratch.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        movw r1, #0xffff
        movt r1, #0x00ff
        movw r2, #0x0010
        movt r2, #0x0000
        .rept 100
        udiv r12, r1, r2
        .endr
    END_BENCH

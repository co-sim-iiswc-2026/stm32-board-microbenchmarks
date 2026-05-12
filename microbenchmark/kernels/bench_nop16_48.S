/*
 * bench_nop16_48 — 48 × 16-bit Thumb NOPs (nop.n) via BENCH harness.
 * One cold warmup call + INNER_REPS measured calls; per-rep DWT snap pair.
 *
 * Part of the NOP-scaling sweep (bench_nop16_{8,16,24,32,40,48,56,64,72,80})
 * used to linear-fit per-NOP cost and measurement framing per hardware
 * variant. Sizes step by 8 NOPs = 2 × 64-bit flash fetches so every
 * datapoint covers an integer number of FLITF flash transactions.
 *
 * Expected per-rep `inner` cycles ≈ 48 + 6 with I-cache + prefetcher on
 * (48 cycles for the nop.n's at CPI=1.0 + ~6 cycles of bl/bx/snap framing).
 */
#include "harness.h"

    BENCH
        .rept 48
        nop.n
        .endr
    END_BENCH

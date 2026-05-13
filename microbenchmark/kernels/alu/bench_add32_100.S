/*
 * bench_add32_100 — 100 × 32-bit Thumb-2 adds (adds.w r1, r1, #1) via
 * BENCH harness. Pairs with bench_add16_100 so the only difference
 * across the two is the ADD-immediate encoding width (4 B T3 vs 2 B T1).
 *
 * Same instruction semantics as add16, just the wide encoding — intended
 * to isolate the cost of the wider fetch under the FLITF cache/prefetcher
 * model. r1 is caller-saved scratch and free of harness state on both
 * platforms.
 *
 * Expected: measured per-rep `inner` reports the wide-encoding cost;
 * compare against bench_add16_100.
 */
#include "harness.h"

    BENCH
        .rept 100
        adds.w r1, r1, #1
        .endr
    END_BENCH

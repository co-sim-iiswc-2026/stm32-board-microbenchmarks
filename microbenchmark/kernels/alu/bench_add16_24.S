/*
 * bench_add16_24 — 24 × 16-bit Thumb adds (adds.n r1, r1, #1) via BENCH
 * harness. One cold warmup call + INNER_REPS measured calls; per-rep
 * DWT snap pair.
 *
 * Naming: `add16` = the 16-bit Thumb narrow encoding of ADD immediate
 * (adds.n, T1/T2 — inherently flag-setting). r1 is caller-saved scratch
 * and free of harness state on both platforms (see README register
 * contract). No init needed: back-to-back dependent adds, 1 cycle each
 * on Cortex-M4 with full forwarding.
 *
 * Expected per-rep `inner` ≈ 24 + 6 = 30 with I-cache + prefetcher on.
 */
#include "harness.h"

    BENCH
        .rept 24
        adds.n r1, r1, #1
        .endr
    END_BENCH

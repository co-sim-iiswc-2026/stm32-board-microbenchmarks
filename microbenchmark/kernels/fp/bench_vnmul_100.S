/*
 * bench_vnmul_100 — 100 × vnmul.f32 via BENCH harness.
 *
 * Exercises gem5 MFpBinS → SimdFloatMultOp (m_decoder.cc:1048).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s1, #1.0
        .rept 100
        vnmul.f32 s0, s0, s1
        .endr
    END_BENCH

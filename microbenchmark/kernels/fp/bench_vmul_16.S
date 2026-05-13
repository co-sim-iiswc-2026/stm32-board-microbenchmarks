/*
 * bench_vmul_16 — 16 × vmul.f32 via BENCH harness.
 *
 * Exercises gem5 MFpBinS → SimdFloatMultOp (m_decoder.cc:1045).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s1, #1.0
        .rept 16
        vmul.f32 s0, s0, s1
        .endr
    END_BENCH

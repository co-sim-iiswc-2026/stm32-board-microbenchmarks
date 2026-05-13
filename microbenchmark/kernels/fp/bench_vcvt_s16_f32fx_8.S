/*
 * bench_vcvt_s16_f32fx_8 — 8 × vcvt.s16.f32 via BENCH harness.
 *
 * gem5 MFpCvtFixedS, float → 16-bit signed fixed (m_decoder.cc:1243).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s0, #1.0
        .rept 8
        vcvt.s16.f32 s0, s0, #1
        .endr
    END_BENCH

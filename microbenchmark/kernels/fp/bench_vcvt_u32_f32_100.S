/*
 * bench_vcvt_u32_f32_100 — 100 × vcvt.u32.f32 via BENCH harness.
 *
 * gem5 MFpCvtS, float→int unsigned (m_decoder.cc:1211).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s1, #1.0
        .rept 100
        vcvt.u32.f32 s0, s1
        .endr
    END_BENCH

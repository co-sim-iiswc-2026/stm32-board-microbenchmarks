/*
 * bench_vcvt_f32_s32_9 — 9 × vcvt.f32.s32 via BENCH harness.
 *
 * gem5 MFpCvtS, int→float signed (m_decoder.cc:1211).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s1, #1.0
        .rept 9
        vcvt.f32.s32 s0, s1
        .endr
    END_BENCH

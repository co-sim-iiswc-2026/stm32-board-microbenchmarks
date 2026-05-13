/*
 * bench_vcvt_f32_u16fx_9 — 9 × vcvt.f32.u16 via BENCH harness.
 *
 * gem5 MFpCvtFixedS, 16-bit unsigned fixed → float (m_decoder.cc:1243).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s0, #1.0
        .rept 9
        vcvt.f32.u16 s0, s0, #1
        .endr
    END_BENCH

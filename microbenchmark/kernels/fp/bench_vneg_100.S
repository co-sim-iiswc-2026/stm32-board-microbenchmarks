/*
 * bench_vneg_100 — 100 × vneg.f32 via BENCH harness.
 *
 * gem5 MFpUnaryS → SimdFloatMiscOp (m_decoder.cc:1132).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s1, #1.0
        .rept 100
        vneg.f32 s0, s1
        .endr
    END_BENCH

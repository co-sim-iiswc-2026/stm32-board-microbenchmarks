/*
 * bench_vfma_100 — 100 × vfma.f32 via BENCH harness.
 *
 * Fused MAC; gem5 MFpFusedMulAddS → SimdFloatMultAccOp (m_decoder.cc:1098).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s1, #1.0
        vmov.f32 s2, #2.0
        .rept 100
        vfma.f32 s0, s1, s2
        .endr
    END_BENCH

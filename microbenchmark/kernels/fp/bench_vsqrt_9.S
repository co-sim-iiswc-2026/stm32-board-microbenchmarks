/*
 * bench_vsqrt_9 — 9 × vsqrt.f32 via BENCH harness.
 *
 * gem5 MFpUnaryS → SimdFloatSqrtOp (m_decoder.cc:1137). Non-pipelined on Cortex-M4 (~14c).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s1, #2.0
        .rept 9
        vsqrt.f32 s0, s1
        .endr
    END_BENCH

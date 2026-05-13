/*
 * bench_vdiv_9 — 9 × vdiv.f32 via BENCH harness.
 *
 * gem5 MFpBinS → SimdFloatDivOp (m_decoder.cc:1066). Non-pipelined on Cortex-M4 (~14c).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s1, #2.0
        vmov.f32 s2, #3.0
        .rept 9
        vdiv.f32 s0, s1, s2
        .endr
    END_BENCH

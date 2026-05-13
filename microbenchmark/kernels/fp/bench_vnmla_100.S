/*
 * bench_vnmla_100 — 100 × vnmla.f32 via BENCH harness.
 *
 * Non-fused MAC; gem5 MFpTernaryS → SimdFloatMultAccOp (m_decoder.cc:1035).
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s1, #1.0
        vmov.f32 s2, #2.0
        .rept 100
        vnmla.f32 s0, s1, s2
        .endr
    END_BENCH

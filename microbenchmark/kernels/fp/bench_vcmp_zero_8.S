/*
 * bench_vcmp_zero_8 — 8 × vcmp.f32 Sd, #0.0 via BENCH harness.
 *
 * gem5 MFpCmpS, zero-compare form (m_decoder.cc:1173). Writes FPSCR NZCV.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s0, #1.0
        .rept 8
        vcmp.f32 s0, #0.0
        .endr
    END_BENCH

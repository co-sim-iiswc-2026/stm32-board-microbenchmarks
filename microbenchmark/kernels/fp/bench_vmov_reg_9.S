/*
 * bench_vmov_reg_9 — 9 × vmov.f32 Sd, Sm via BENCH harness.
 *
 * gem5 MFpMovRegS (m_decoder.cc:1123). FP register-to-register copy.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s1, #1.0
        .rept 9
        vmov.f32 s0, s1
        .endr
    END_BENCH

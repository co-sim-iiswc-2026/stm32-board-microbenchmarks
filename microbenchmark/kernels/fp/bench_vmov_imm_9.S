/*
 * bench_vmov_imm_9 — 9 × vmov.f32 Sd, #imm via BENCH harness.
 *
 * gem5 MFpMovImmS (m_decoder.cc:1116). 8-bit modified FP immediate.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        .rept 9
        vmov.f32 s0, #1.0
        .endr
    END_BENCH

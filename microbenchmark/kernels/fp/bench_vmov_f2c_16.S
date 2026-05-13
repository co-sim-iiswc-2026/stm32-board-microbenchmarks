/*
 * bench_vmov_f2c_16 — 16 × vmov Rt, Sn (FPU→core) via BENCH harness.
 *
 * FPU-to-core single-precision transfer (m_decoder.cc:858). r1 is harness-free scratch.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        vmov.f32 s0, #1.0
        .rept 16
        vmov r1, s0
        .endr
    END_BENCH

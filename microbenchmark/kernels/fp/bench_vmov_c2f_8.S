/*
 * bench_vmov_c2f_8 — 8 × vmov Sn, Rt (core→FPU) via BENCH harness.
 *
 * Core-to-FPU single-precision transfer (m_decoder.cc:860). r1 is harness-free scratch.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        movs r1, #1
        .rept 8
        vmov s0, r1
        .endr
    END_BENCH

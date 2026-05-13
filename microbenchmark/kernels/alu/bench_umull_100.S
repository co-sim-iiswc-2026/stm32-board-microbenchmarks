/*
 * bench_umull_100 — 100 × umull r12, r2, r1, r1 via BENCH harness.
 *
 * 32x32→64 unsigned multiply long; writes RdLo:RdHi pair. Cortex-M4 =
 * 1 cycle per errata. RdLo=r12, RdHi=r2 (both harness-free scratch);
 * Rn=Rm=r1 (squared). Same-source-register form sidesteps the "need 4
 * distinct free regs" constraint without touching AAPCS callee-saved
 * registers.
 *
 * One-shot setup (constant across all sizes — cancels in N=100 − N=8
 * differencing) goes before .rept inside BENCH.
 */
#include "harness.h"

    BENCH
        movw r1, #0x1234
        .rept 100
        umull r12, r2, r1, r1
        .endr
    END_BENCH

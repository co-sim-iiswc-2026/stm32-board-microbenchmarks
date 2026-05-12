/*
 * bench_nop16_100 — 100 × 16-bit Thumb NOPs (nop.n), measured via the
 * BENCH harness: one cold warmup call followed by INNER_REPS measured
 * calls, each bracketed by its own inner-ROI DWT snap pair.
 *
 * Naming: `bench` = a runnable benchmark target, `nop16` = the 16-bit
 * Thumb NOP encoding, `100` = the body emits 100 of them.
 *
 * Expected per-rep `inner` cycles ≈ 106 (with I-cache + prefetcher on):
 *   100  cycles — 100 nop.n at CPI=1.0 in warm cache
 *   + 2  cycles — bl (P=1, target PC-relative, prefetcher-predicted)
 *   + 3  cycles — bx lr (P=2, indirect-branch refill)
 *   + ~1 cycle  — start-snap ldr tail to end-snap ldr head
 *   ≈ 106
 *
 * Run:
 *   cmake --build build/hw-stm32g474re -j4 --target bench_nop16_100.elf
 *   python3 ./test/test_board_run.py hw-stm32g474re bench_nop16_100
 *
 * Output (one line per rep, INNER_REPS reps total):
 *   MICROBENCH name=bench_nop16_100 rep=0 inner=106
 *   MICROBENCH name=bench_nop16_100 rep=1 inner=106
 *   ...
 */
#include "harness.h"

    BENCH
        .rept 100
        nop.n
        .endr
    END_BENCH

/*
 * Benchmark 1: NOP Sled — Baseline pipeline throughput.
 * Expected: ~100 cycles (1 NOP per cycle on Cortex-M4).
 * Validates: pipeline throughput, no stalls on independent instructions.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    /* warmup */
    .rept 100
    nop
    .endr

    BENCH_START

    .rept 100
    nop
    .endr

    BENCH_END

    VECTOR_TABLE

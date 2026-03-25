/*
 * Benchmark: Memory Barrier Latency — DMB, DSB, ISB.
 *
 * Measures the cycle cost of memory barrier instructions.  On Cortex-M4,
 * these are used in real firmware for peripheral access ordering,
 * self-modifying code, and interrupt handling.
 *
 * DDI0439D Table 3-1: DMB=1cy, DSB=1cy, ISB=1cy (pipeline flush).
 * However, ISB flushes the pipeline, which may cause additional fetch
 * penalty beyond the 1-cycle instruction latency.
 *
 * Part A: 20 x DMB (data memory barrier)
 * Part B: 20 x DSB (data synchronization barrier)
 * Part C: 10 x ISB (instruction synchronization barrier)
 *
 * Expected: ~50 + ISB pipeline flush cost
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    /* warmup */
    .rept 10
    dmb sy
    dsb sy
    isb sy
    .endr

    BENCH_START

    /* Part A: 20 x DMB */
    .rept 20
    dmb sy
    .endr

    /* Part B: 20 x DSB */
    .rept 20
    dsb sy
    .endr

    /* Part C: 10 x ISB */
    .rept 10
    isb sy
    .endr

    BENCH_END

    VECTOR_TABLE

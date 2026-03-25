/*
 * Benchmark 2: ALU Throughput — ADD/SUB/AND/ORR.
 * Expected: ~100 cycles (4 ops x 25 iterations, all 1 cycle each).
 * Validates: single-cycle ALU operations with no data dependencies.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    mov r0, #1
    mov r1, #2
    mov r2, #3
    mov r3, #4

    /* warmup */
    .rept 25
    add   r4, r0, r1
    sub   r5, r2, r3
    and.w r4, r0, r2
    orr.w r5, r1, r3
    .endr

    BENCH_START

    .rept 25
    add   r4, r0, r1
    sub   r5, r2, r3
    and.w r4, r0, r2
    orr.w r5, r1, r3
    .endr

    BENCH_END

    VECTOR_TABLE

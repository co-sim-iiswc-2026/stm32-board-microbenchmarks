/*
 * Benchmark 3: Multiply Throughput.
 * Expected: ~100 cycles (M4 has single-cycle 32x32 multiplier).
 * Validates: MUL is truly 1-cycle.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    mov r0, #7
    mov r1, #13

    /* warmup */
    .rept 100
    mul.w r2, r0, r1
    .endr

    BENCH_START

    .rept 100
    mul.w r2, r0, r1
    .endr

    BENCH_END

    VECTOR_TABLE

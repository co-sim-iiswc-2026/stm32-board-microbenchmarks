/*
 * Benchmark 4: Integer Division Latency.
 * Worst case: large dividend / 1 (12 cycles each on real M4).
 * gem5 model uses opLat=7 (representative average).
 * Validates: division latency.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r0, =0x7FFFFFFF
    mov r1, #1

    /* warmup */
    .rept 20
    sdiv r2, r0, r1
    .endr

    BENCH_START

    .rept 20
    sdiv r2, r0, r1
    .endr

    BENCH_END

    VECTOR_TABLE

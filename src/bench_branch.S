/*
 * Benchmark 8: Branch Penalty — tight loop.
 * 100-iteration loop: each iteration = SUBS (1 cy) + BNE taken (1+P cy).
 * Expected: 99*(1 + 1+P) + (1 + 1) = ~300-500 cycles depending on P.
 * Validates: branch taken penalty, pipeline refill cost.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    /* warmup: fills I-cache + trains BP on the same loop */
    mov r0, #100
.Lwarmup:
    subs r0, r0, #1
    bne .Lwarmup

    BENCH_START

    mov r0, #100
.Lloop:
    subs r0, r0, #1
    bne .Lloop

    BENCH_END

    VECTOR_TABLE

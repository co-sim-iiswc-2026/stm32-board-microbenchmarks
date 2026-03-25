/*
 * Benchmark 7: PUSH/POP Multi-Register Transfer.
 * Expected: 10 + 10 + 5 + 5 = 30 cycles (1+N formula).
 * Validates: multi-register transfer timing.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    mov r0, #0
    mov r1, #1
    mov r2, #2
    mov r3, #3
    mov r4, #4
    mov r5, #5

    /* warmup */
    push {r0-r7, lr}
    pop  {r0-r7, lr}
    push {r0-r3}
    pop  {r0-r3}

    BENCH_START

    push {r0-r7, lr}
    pop  {r0-r7, lr}
    push {r0-r3}
    pop  {r0-r3}

    BENCH_END

    VECTOR_TABLE

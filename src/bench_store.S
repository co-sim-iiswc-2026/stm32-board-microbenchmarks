/*
 * Benchmark 6: Store Latency to SRAM.
 * 50 STR to same SRAM address.
 * Expected: effectively ~1 cycle each with write buffer (50-75 total).
 * Validates: store latency, write buffer behavior.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =0x20000200
    mov r0, #42

    /* warmup */
    .rept 50
    str r0, [r6]
    .endr

    BENCH_START

    .rept 50
    str r0, [r6]
    .endr

    BENCH_END

    VECTOR_TABLE

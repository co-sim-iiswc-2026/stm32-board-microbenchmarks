/*
 * Benchmark 5: Load Latency from SRAM.
 * 50 LDR from same SRAM address (zero wait-state).
 * Expected: ~2 cycles each on real M4, with pipelining ~75-100 total.
 * Validates: load latency, bus overhead.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =0x20000200

    /* warmup */
    .rept 50
    ldr r0, [r6]
    .endr

    BENCH_START

    .rept 50
    ldr r0, [r6]
    .endr

    BENCH_END

    VECTOR_TABLE

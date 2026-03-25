/*
 * Benchmark: Flash Literal Pool Load — ART D-Cache path.
 *
 * LDR Rx, =const generates a PC-relative load from a literal pool in
 * Flash.  This exercises the DCode bus → ART D-Cache → flash_bus → Flash
 * path, which no other benchmark tests.
 *
 * 50 PC-relative loads from Flash literal pool.  Each loads a different
 * constant to avoid the decoder merging them.
 *
 * Expected with ART D-Cache:    ~104 cy (after warmup, D-Cache hits)
 * Expected without ART D-Cache: ~254 cy (50 fetches, but Flash reads ~5 cy)
 *
 * Note: The literal pool must be close enough to the LDR for the
 * PC-relative offset to reach (within ±4KB for Thumb-2 LDR).
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    /* warmup: load same literals to fill ART D-Cache */
    .irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24
    ldr r0, =0xDEAD0000 + \i
    ldr r1, =0xBEEF0000 + \i
    .endr

    BENCH_START

    /* Measured: 50 literal pool loads from Flash */
    .irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24
    ldr r0, =0xDEAD0000 + \i
    ldr r1, =0xBEEF0000 + \i
    .endr

    BENCH_END

    VECTOR_TABLE

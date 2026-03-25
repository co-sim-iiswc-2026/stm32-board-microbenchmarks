/*
 * Benchmark: 16-bit ALU Throughput — ADDS/MOVS/EORS/ORRS.
 *
 * bench_alu uses all 32-bit Thumb-2 encodings (add.w, sub.w, and.w, orr.w),
 * giving 1 instruction per 4-byte fetch.  This benchmark forces 16-bit
 * Thumb encodings (adds, subs, movs, eors) to test 2 instructions per
 * 4-byte fetch.
 *
 * 100 ALU ops (25 iterations x 4 ops), all 16-bit, all 1-cycle.
 *
 * Expected with ART:    ~104 cy (100 x 1 + 4 overhead)
 * Expected without ART: ~254 cy (50 fetches x 5 cy; 2 ops/fetch)
 * Key comparison: bench_alu (32-bit) without ART = ~504 cy (1 op/fetch)
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    movs r0, #1
    movs r1, #2
    movs r2, #3
    movs r3, #4

    /* warmup */
    .rept 25
    adds r4, r0, r1       /* 16-bit T1 encoding */
    subs r5, r2, r3       /* 16-bit T1 encoding */
    eors r4, r4, r2       /* 16-bit T1 encoding */
    orrs r5, r5, r3       /* 16-bit T1 encoding */
    .endr

    BENCH_START

    .rept 25
    adds r4, r0, r1
    subs r5, r2, r3
    eors r4, r4, r2
    orrs r5, r5, r3
    .endr

    BENCH_END

    VECTOR_TABLE

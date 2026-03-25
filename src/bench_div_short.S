/*
 * Benchmark: SDIV Fast Path — small operands (few leading zeros).
 *
 * bench_div uses worst-case operands (0x7FFFFFFF / 1 = 12 cycles).
 * This benchmark uses small operands (15 / 3 = 5) to measure the
 * fast path of the data-dependent SDIV.
 *
 * DDI0439D Table 3-1 footnote (a): "The number of cycles required is
 * dependent on the values of the input operands."  Range: 2-12 cycles.
 *
 * 20 SDIV with small operands.
 *
 * Expected with ART:    ~44-84 cy (20 x 2-4 + 4 overhead)
 * Expected without ART: ~same (execution-bound, SDIV >> fetch)
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    mov r0, #15
    mov r1, #3

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

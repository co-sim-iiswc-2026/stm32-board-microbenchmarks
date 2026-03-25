/*
 * Benchmark: Mixed 16/32-bit Instruction Stream.
 *
 * Alternates between 16-bit and 32-bit instructions to test how the
 * pipeline handles fetch boundaries when a 32-bit instruction straddles
 * two 4-byte fetches.
 *
 * Pattern per iteration: NOP(16) + AND.W(32) + NOP(16) + ORR.W(32)
 *   = 2 + 4 + 2 + 4 = 12 bytes per iteration
 *
 * 25 iterations = 100 instructions = 300 bytes.
 * Fetch alignment: some 32-bit instructions will straddle fetch boundaries,
 * requiring 2 fetches for 1 instruction.
 *
 * Expected with ART:    ~104 cy (100 x 1 + 4 overhead)
 * Expected without ART: >254 cy (straddle fetches add extra penalty)
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
    nop                     /* 16-bit: 2 bytes */
    and.w r4, r0, r2       /* 32-bit: 4 bytes */
    nop                     /* 16-bit: 2 bytes */
    orr.w r5, r1, r3       /* 32-bit: 4 bytes */
    .endr

    BENCH_START

    .rept 25
    nop
    and.w r4, r0, r2
    nop
    orr.w r5, r1, r3
    .endr

    BENCH_END

    VECTOR_TABLE

/*
 * Branch Prediction RE #6: Branch Target Alignment — tests P vs alignment.
 *
 * DDI0439D p.3-4: P depends on "the alignment and width of the target
 * instruction."  This benchmark tests three alignment cases:
 *
 * Part A: Target at 4-byte boundary (word-aligned)
 * Part B: Target at 2-byte boundary (halfword-aligned, not word-aligned)
 * Part C: Target is a 32-bit instruction at 2-byte boundary (straddles)
 *
 * 100 iterations each.  Compare cycles to determine alignment effect on P.
 *
 * Expected: P may increase when target is misaligned or straddles a
 * fetch boundary, requiring an extra fetch cycle.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:

    /* ===== Part A: target at 4-byte (word) aligned address ===== */
    /* warmup */
    mov r0, #100
    .balign 4
.Lw_alignA:
    subs r0, r0, #1
    bne .Lw_alignA

    BENCH_START

    mov r0, #100
    .balign 4                 /* force target to 4-byte boundary */
.LloopA:
    subs r0, r0, #1
    bne .LloopA

    /* ===== Part B: target at halfword boundary (not word-aligned) ===== */
    nop                       /* 2-byte NOP shifts next label to +2 offset */
    mov r0, #100
.LloopB:                      /* this label is at an odd halfword boundary */
    subs r0, r0, #1
    bne .LloopB

    /* ===== Part C: 32-bit target at halfword boundary (straddle) ===== */
    nop                       /* shift alignment again */
    mov r0, #100
.LloopC:
    sub.w r0, r0, #1         /* 32-bit SUBS at potentially misaligned addr */
    bne .LloopC

    BENCH_END

    VECTOR_TABLE

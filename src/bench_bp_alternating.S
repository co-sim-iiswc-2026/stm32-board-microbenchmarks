/*
 * Branch Prediction RE #4: Alternating Taken/Not-Taken pattern.
 *
 * Tests whether the M4 has a pattern predictor (like a 2-bit saturating
 * counter) or just a static predictor.
 *
 * Pattern: even iterations → branch NOT taken, odd → taken.
 * A 2-bit counter will be confused and mispredict ~50%.
 * A static "always not-taken" predictor hits 50%.
 *
 * Implementation: use bit 0 of the counter to decide direction.
 *   ANDS r1, r0, #1; BNE .Lskip (taken when counter is odd)
 *
 * 200 iterations total (100 taken, 100 not-taken).
 * Per iteration: ANDS(1) + BNE(1+P if taken, 1 if not) + SUBS(1) + BNE(1+P back).
 *
 * The backward BNE to .Lloop is always taken (loop control).
 * The forward BNE to .Lskip alternates.
 *
 * Expected: compare cycles/iter against bench_bp_tight to extract
 * the penalty for alternating vs always-taken.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    /* warmup */
    mov r0, #200
.Lwarmup:
    ands r1, r0, #1          /* test bit 0 */
    bne .Lwskip               /* taken on odd iterations */
    nop                       /* executed on even iterations */
.Lwskip:
    subs r0, r0, #1
    bne .Lwarmup

    BENCH_START

    mov r0, #200
.Lloop:
    ands r1, r0, #1          /* test bit 0: Z=1 if even */
    bne .Lskip                /* taken on odd iterations */
    nop                       /* executed on even iterations */
.Lskip:
    subs r0, r0, #1
    bne .Lloop

    BENCH_END

    VECTOR_TABLE

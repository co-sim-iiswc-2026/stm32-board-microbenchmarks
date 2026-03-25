/*
 * Branch Prediction RE #2: Long Loop Body — does body length affect P?
 *
 * Same backward BNE as bench_bp_tight, but with 8 NOPs between SUBS
 * and BNE.  If the M4's speculation depends on recognizing the loop
 * pattern (SUBS+BNE adjacent), a longer body may increase P.
 *
 * 100 iterations x (8 NOPs + SUBS + BNE) = 100 x 10 instructions.
 * Branch overhead only: 100 x (1 + 1+P) = 100 x (2+P) cycles.
 * NOP overhead: 100 x 8 = 800 cycles.
 *
 *   P=1: 100 x 3 + 800 = 1100 cy (11 cy/iter)
 *   P=2: 100 x 4 + 800 = 1200 cy (12 cy/iter)
 *   P=3: 100 x 5 + 800 = 1300 cy (13 cy/iter)
 *
 * Compare with bench_bp_tight to see if P changes with body length.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    /* warmup */
    mov r0, #100
.Lwarmup:
    .rept 8
    nop
    .endr
    subs r0, r0, #1
    bne .Lwarmup

    BENCH_START

    mov r0, #100
.Lloop:
    .rept 8
    nop
    .endr
    subs r0, r0, #1
    bne .Lloop

    BENCH_END

    VECTOR_TABLE

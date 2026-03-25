/*
 * Branch Prediction RE #1: Tight Loop — backward BNE, 2 instructions.
 *
 * The simplest possible loop: SUBS + BNE.  This is the baseline for
 * measuring the branch penalty P in the M4.
 *
 * DDI0439D p.3-4: P = 1 to 3, depending on "the alignment and width
 * of the target instruction, and whether the processor manages to
 * speculate the address early."
 *
 * If the M4 has any loop speculation, this is where it will show:
 * a tight backward branch to a nearby 16-bit target is the best case.
 *
 * 200 iterations.  Per iteration: SUBS(1cy) + BNE taken(1+P cy).
 *   P=1: 200 x 3 = 600 cy
 *   P=2: 200 x 4 = 800 cy
 *   P=3: 200 x 5 = 1000 cy
 *
 * Run with ART to eliminate fetch effects.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    /* warmup: same loop shape to train any speculation */
    mov r0, #200
.Lwarmup:
    subs r0, r0, #1
    bne .Lwarmup

    BENCH_START

    mov r0, #200
.Lloop:
    subs r0, r0, #1
    bne .Lloop

    BENCH_END

    VECTOR_TABLE

/*
 * Branch Prediction RE #5: Nested Loops — tests if speculation
 * handles multiple active loop targets.
 *
 * Two nested loops: outer (20 iter) x inner (10 iter).
 * The inner BNE and outer BNE compete for any speculation resources.
 * If the M4 can only speculate one branch target, the outer loop's
 * re-entry branch will have a higher P than the inner loop's.
 *
 * Inner loop: 10 x (SUBS + BNE) = 10 x (2+P_inner)
 * Outer loop: 20 iterations, each containing inner + SUBS + BNE
 *
 * Total taken branches: 20x10 inner + 20 outer = 220 branches.
 *
 * Compare P_inner and P_outer by comparing:
 *   - Total cycles / 220 = average penalty per branch
 *   - vs bench_bp_tight (single loop) P
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    /* warmup */
    mov r4, #20
.Lw_outer:
    mov r5, #10
.Lw_inner:
    subs r5, r5, #1
    bne .Lw_inner
    subs r4, r4, #1
    bne .Lw_outer

    BENCH_START

    mov r4, #20
.Louter:
    mov r5, #10
.Linner:
    subs r5, r5, #1
    bne .Linner
    subs r4, r4, #1
    bne .Louter

    BENCH_END

    VECTOR_TABLE

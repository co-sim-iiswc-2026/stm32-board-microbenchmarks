/*
 * Branch Prediction RE #3: Forward Branch — BEQ skipping over code.
 *
 * Tests forward conditional branch penalty vs backward.  If the M4's
 * speculation only works for backward branches (loops), forward branches
 * should always pay the full P penalty.
 *
 * Pattern: CMP + BEQ (forward, taken) + NOP padding + target.
 * The CMP always sets Z=1 (so BEQ is always taken).
 *
 * 100 iterations of: CMP(1) + BEQ taken(1+P) = 100 x (2+P).
 *   P=1: 100 x 3 = 300 cy
 *   P=2: 100 x 4 = 400 cy
 *   P=3: 100 x 5 = 500 cy
 *
 * Compare with bench_bp_tight (backward) to isolate direction effect.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    mov r4, #0               /* loop counter */

    /* warmup: 100 forward branches */
    mov r5, #100
.Lwarmup:
    cmp r4, r4               /* always sets Z=1 */
    beq .Lwskip              /* forward branch, always taken */
    nop                       /* never executed (skipped) */
    nop
.Lwskip:
    subs r5, r5, #1
    bne .Lwarmup

    BENCH_START

    mov r5, #100
.Lloop:
    cmp r4, r4               /* sets Z=1 */
    beq .Lskip               /* forward branch, always taken */
    nop                       /* never executed */
    nop
.Lskip:
    subs r5, r5, #1
    bne .Lloop

    BENCH_END

    VECTOR_TABLE

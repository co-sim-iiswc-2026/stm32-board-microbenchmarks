/*
 * Benchmark: Exception Entry with FP Context — extended stack frame.
 *
 * When FP registers are active (CONTROL.FPCA=1), exception entry pushes
 * an extended frame: 8 integer + 18 FP registers = 26 words (104 bytes)
 * instead of the standard 8 words (32 bytes).
 *
 * DDI0439D §3.9.1: "When the processor stacks the FP context, the
 * exception entry time increases to 29 cycles maximum" (vs 12 without FP).
 *
 * Setup: Touch an FP register before enabling SysTick to activate FPCA.
 *
 * Expected with ART:    ~33-37 cy (29 entry + setup + handler)
 * Expected without ART: ~37-41 cy (same, mostly SRAM-bound)
 */
    .include "src/bench_macros.inc"
    DEFAULT_HANDLER_IMPL

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =SCS_BASE

    /* Activate FP context: touch an FP register to set FPCA */
    vmov s0, #1.0
    vmov s1, #2.0
    vadd.f32 s2, s0, s1     /* Now CONTROL.FPCA = 1 */

    /* SysTick: LOAD=1, fire after 2 cycles */
    mov r0, #1
    str r0, [r6, #0x14]        /* SYST_RVR = 1 */
    mov r0, #0
    str r0, [r6, #0x18]        /* SYST_CVR = 0 */

    /* START MARKER */
    BENCH_START

    /* Enable SysTick (CLKSOURCE=1, TICKINT=1, ENABLE=1) */
    mov r0, #7
    str r0, [r6, #0x10]        /* SYST_CSR = 7 */

    /* NOP sled — SysTick fires during this (with FP context stacking) */
    .rept 200
    nop
    .endr
    b .

    .global SysTick_Handler
    .thumb_func
    .type SysTick_Handler, %function
SysTick_Handler:
    /* END MARKER (in handler) */
    ldr r0, =END_MARK
    str r0, [r7]                /* r7 still has MARKER_ADDR from BENCH_START */

    /* Disable SysTick */
    ldr r6, =SCS_BASE
    mov r0, #0
    str r0, [r6, #0x10]

    /* PASS + semihosting exit */
    ldr r1, =RESULT_ADDR
    ldr r0, =PASS_VAL
    str r0, [r1]
    mov r0, #0x18
    ldr r1, =0x20026
    bkpt #0xab
    b .

    VECTOR_TABLE_FULL

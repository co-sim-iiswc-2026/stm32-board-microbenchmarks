/*
 * Benchmark 9: Exception Entry Latency via SysTick.
 * Configures SysTick to fire quickly, measures from SysTick enable to
 * first instruction in SysTick_Handler.
 * Expected: ~12 cycles entry latency on real M4.
 * Validates: stacking + vector fetch + mode switch.
 */
    .include "src/bench_macros.inc"
    DEFAULT_HANDLER_IMPL

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =SCS_BASE

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

    /* NOP sled — SysTick fires during this */
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

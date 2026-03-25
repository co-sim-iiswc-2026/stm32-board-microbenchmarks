/*
 * Benchmark 10: Exception Return Latency.
 * Measures from last instruction in SysTick_Handler (just before BX LR)
 * to first instruction back in thread mode.
 * Expected: ~10 cycles on real M4.
 * Validates: unstacking + register restore + pipeline refill.
 */
    .include "src/bench_macros.inc"
    DEFAULT_HANDLER_IMPL

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =SCS_BASE

    /* SysTick: LOAD=1, fire quickly */
    mov r0, #1
    str r0, [r6, #0x14]
    mov r0, #0
    str r0, [r6, #0x18]

    /* Enable SysTick */
    mov r0, #7
    str r0, [r6, #0x10]

    /* Wait for SysTick to fire */
    .rept 200
    nop
    .endr

.Lreturn_point:
    /* END MARKER (back in thread mode after exception return) */
    ldr r7, =MARKER_ADDR
    ldr r0, =END_MARK
    str r0, [r7]

    ldr r1, =RESULT_ADDR
    ldr r0, =PASS_VAL
    str r0, [r1]
    mov r0, #0x18
    ldr r1, =0x20026
    bkpt #0xab
    b .

    .global SysTick_Handler
    .thumb_func
    .type SysTick_Handler, %function
SysTick_Handler:
    /* Disable SysTick to prevent re-fire */
    ldr r6, =SCS_BASE
    mov r0, #0
    str r0, [r6, #0x10]

    /* START MARKER (in handler, just before return) */
    ldr r7, =MARKER_ADDR
    ldr r0, =START_MARK
    str r0, [r7]

    /* Return from exception */
    bx lr

    VECTOR_TABLE_FULL

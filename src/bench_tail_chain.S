/*
 * Benchmark: Tail-Chained Exception — back-to-back exceptions.
 *
 * When a second exception is pending while returning from the first,
 * the processor tail-chains: it skips the unstack/restack and goes
 * directly to the second handler.
 *
 * DDI0439D §3.9.1: "Tail-chaining reduces the latency of back-to-back
 * interrupts from the stack pop and push overhead."  Tail-chain = 6 cycles.
 *
 * Strategy:
 *   1. Set SysTick to fire (pend SysTick exception)
 *   2. In SysTick_Handler, pend IRQ0 via NVIC_ISPR0 (software-triggered)
 *   3. When SysTick_Handler returns, IRQ0 is pending → tail-chain
 *   4. IRQ0_Handler writes END_MARK
 *
 * Measures: START_MARK (in SysTick_Handler, just before pend+return)
 *           → END_MARK (in IRQ0_Handler)
 * Delta includes: SysTick return + tail-chain to IRQ0 + IRQ0 preamble.
 *
 * Expected: ~10-12 cy (6 cy tail-chain + handler preamble)
 */
    .include "src/bench_macros.inc"
    DEFAULT_HANDLER_IMPL

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =SCS_BASE

    /* Enable IRQ0 in NVIC: ISER0 bit 0 */
    mov r0, #1
    str r0, [r6, #0x100]       /* NVIC_ISER0 = 1 */

    /* Set IRQ0 to lower priority than SysTick so it doesn't preempt.
       SysTick priority (SHPR3[31:24]) = 0x00 (highest configurable).
       IRQ0 priority (NVIC_IPR0[7:0]) = 0x40 (lower). */
    mov r0, #0x40
    str r0, [r6, #0x400]       /* NVIC_IPR0 = 0x40 */

    /* SysTick: LOAD=1, fire quickly */
    mov r0, #1
    str r0, [r6, #0x14]        /* SYST_RVR = 1 */
    mov r0, #0
    str r0, [r6, #0x18]        /* SYST_CVR = 0 */

    /* Enable SysTick (CLKSOURCE=1, TICKINT=1, ENABLE=1) */
    mov r0, #7
    str r0, [r6, #0x10]        /* SYST_CSR = 7 */

    /* NOP sled — SysTick fires during this */
    .rept 200
    nop
    .endr
    b .

    /* ----- SysTick_Handler: pend IRQ0, then START_MARK, then return ----- */
    .global SysTick_Handler
    .thumb_func
    .type SysTick_Handler, %function
SysTick_Handler:
    /* Disable SysTick to prevent re-fire */
    ldr r6, =SCS_BASE
    mov r0, #0
    str r0, [r6, #0x10]        /* SYST_CSR = 0 */

    /* Pend IRQ0 via software: NVIC_ISPR0 bit 0 */
    mov r0, #1
    str r0, [r6, #0x200]       /* NVIC_ISPR0 = 1 */

    /* START MARKER — just before return (tail-chain starts here) */
    BENCH_START

    /* Return from SysTick — IRQ0 is pending → tail-chain */
    bx lr

    /* ----- IRQ0_Handler: write END_MARK ----- */
    .global IRQ0_Handler
    .thumb_func
    .type IRQ0_Handler, %function
IRQ0_Handler:
    /* END MARKER */
    ldr r0, =END_MARK
    str r0, [r7]                /* r7 from BENCH_START */

    /* PASS + semihosting exit */
    ldr r1, =RESULT_ADDR
    ldr r0, =PASS_VAL
    str r0, [r1]
    mov r0, #0x18
    ldr r1, =0x20026
    bkpt #0xab
    b .

    /* Vector table: need SysTick + IRQ0 (IRQ1 unused but required by macro) */
    .global IRQ1_Handler
    .thumb_func
    .type IRQ1_Handler, %function
IRQ1_Handler:
    b .

    VECTOR_TABLE_WITH_IRQ

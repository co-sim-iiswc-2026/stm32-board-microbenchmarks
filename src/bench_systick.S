/*
 * Benchmark 11: SysTick Precision — polling mode.
 * Sets LOAD=99 (fires every 100 cycles), polls COUNTFLAG.
 * Expected: ~100 cycles + polling overhead.
 * Validates: SysTick (LOAD+1) cycle timing, COUNTFLAG behavior.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =SCS_BASE

    /* SysTick LOAD=99 (fires every 100 cycles) */
    mov r0, #99
    str r0, [r6, #0x14]        /* SYST_RVR = 99 */
    mov r0, #0
    str r0, [r6, #0x18]        /* SYST_CVR = 0 */

    BENCH_START

    /* Enable SysTick in polling mode (CLKSOURCE=1, TICKINT=0, ENABLE=1) */
    mov r0, #5
    str r0, [r6, #0x10]

    /* Poll COUNTFLAG */
.Lpoll:
    ldr r0, [r6, #0x10]        /* Read SYST_CSR */
    lsls r0, r0, #15           /* Shift COUNTFLAG (bit 16) into sign bit */
    bpl .Lpoll

    BENCH_END

    VECTOR_TABLE

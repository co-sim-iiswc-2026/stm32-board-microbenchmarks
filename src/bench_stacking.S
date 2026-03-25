/*
 * Benchmark: Pure Exception Stacking Overhead (no FP context).
 *
 * Isolates the stacking cost by measuring from immediately before
 * exception entry to immediately after — without SysTick setup or
 * handler preamble polluting the measurement.
 *
 * Strategy: Use PendSV (lowest configurable priority, software-triggered).
 *   1. Write START_MARK
 *   2. Pend PendSV via ICSR.PENDSVSET
 *   3. ISB to force immediate exception entry
 *   4. PendSV_Handler writes END_MARK immediately
 *
 * This measures: ISB pipeline flush + stacking (8 words to SRAM) +
 * vector fetch + first handler instruction.
 *
 * DDI0439D §3.9.1: 12 cycles maximum (0 WS, no FP context).
 *
 * Expected with ART:    ~14-18 cy (12 stacking + ISB + handler overhead)
 * Expected without ART: ~18-22 cy (vector fetch from Flash adds ~5 cy)
 */
    .include "src/bench_macros.inc"
    DEFAULT_HANDLER_IMPL

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =SCS_BASE

    /* warmup: pend and handle PendSV once to fill I-Cache */
    ldr r0, =0x10000000      /* ICSR.PENDSVSET = bit 28 */
    str r0, [r6, #0xD04]     /* SCB_ICSR */
    isb
    .rept 10
    nop
    .endr

    /* START MARKER — as close to exception trigger as possible */
    BENCH_START

    /* Trigger PendSV: write PENDSVSET bit in SCB_ICSR (0xE000ED04) */
    ldr r0, =0x10000000      /* bit 28 = PENDSVSET */
    str r0, [r6, #0xD04]     /* SCB_ICSR = PENDSVSET */
    isb                       /* force pipeline flush, exception taken now */

    /* Should not reach here — PendSV preempts immediately after ISB */
    .rept 50
    nop
    .endr
    b .

    /* ----- PendSV_Handler ----- */
    .global PendSV_Handler
    .thumb_func
    .type PendSV_Handler, %function
PendSV_Handler:
    /* END MARKER — first thing in handler */
    ldr r0, =END_MARK
    str r0, [r7]             /* r7 from BENCH_START */

    /* PASS + semihosting exit */
    ldr r1, =RESULT_ADDR
    ldr r0, =PASS_VAL
    str r0, [r1]
    mov r0, #0x18
    ldr r1, =0x20026
    bkpt #0xab
    b .

    /* Vector table: need PendSV at position 14 */
    .section .isr_vector, "a", %progbits
    .word _estack
    .word Reset_Handler
    .word Default_Handler     /* 2:  NMI */
    .word Default_Handler     /* 3:  HardFault */
    .word Default_Handler     /* 4:  MemManage */
    .word Default_Handler     /* 5:  BusFault */
    .word Default_Handler     /* 6:  UsageFault */
    .word 0                   /* 7:  Reserved */
    .word 0                   /* 8:  Reserved */
    .word 0                   /* 9:  Reserved */
    .word 0                   /* 10: Reserved */
    .word Default_Handler     /* 11: SVCall */
    .word Default_Handler     /* 12: DebugMon */
    .word 0                   /* 13: Reserved */
    .word PendSV_Handler      /* 14: PendSV */
    .word Default_Handler     /* 15: SysTick */

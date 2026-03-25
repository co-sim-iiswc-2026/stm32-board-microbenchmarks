/*
 * Benchmark: Pure Exception Stacking Overhead WITH FP Context.
 *
 * Same as bench_stacking but with FP context active (CONTROL.FPCA=1).
 * The extended stack frame pushes 26 words (8 integer + 18 FP) instead
 * of 8 words, increasing stacking from 12 to 29 cycles.
 *
 * DDI0439D §3.9.1: 29 cycles maximum (0 WS, with FP context).
 * The extra 17 cycles = 18 FP registers stacked.
 *
 * Compare: bench_stacking (no FP) vs bench_stacking_fp (with FP).
 * Delta = pure FP stacking cost = ~17 cycles (18 extra words).
 *
 * Expected with ART:    ~31-35 cy (29 stacking + ISB + handler)
 * Expected without ART: ~35-39 cy (vector fetch from Flash)
 */
    .include "src/bench_macros.inc"
    DEFAULT_HANDLER_IMPL

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =SCS_BASE

    /* Activate FP context: touch FP registers to set CONTROL.FPCA=1 */
    vmov s0, #1.0
    vmov s1, #2.0
    vadd.f32 s2, s0, s1     /* Now FPCA=1 → extended stacking */

    /* warmup: pend and handle PendSV once to fill I-Cache */
    ldr r0, =0x10000000
    str r0, [r6, #0xD04]
    isb
    .rept 10
    nop
    .endr

    /* Re-touch FP to ensure FPCA is still set */
    vadd.f32 s3, s0, s1

    /* START MARKER */
    BENCH_START

    /* Trigger PendSV */
    ldr r0, =0x10000000
    str r0, [r6, #0xD04]     /* SCB_ICSR = PENDSVSET */
    isb

    .rept 50
    nop
    .endr
    b .

    /* ----- PendSV_Handler ----- */
    .global PendSV_Handler
    .thumb_func
    .type PendSV_Handler, %function
PendSV_Handler:
    /* END MARKER */
    ldr r0, =END_MARK
    str r0, [r7]

    /* PASS + semihosting exit */
    ldr r1, =RESULT_ADDR
    ldr r0, =PASS_VAL
    str r0, [r1]
    mov r0, #0x18
    ldr r1, =0x20026
    bkpt #0xab
    b .

    /* Vector table with PendSV */
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

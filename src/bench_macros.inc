/*
 * Common macros for STM32G474RE microbenchmarks.
 *
 * Timing protocol:
 *   Firmware writes START_MARK to MARKER_ADDR, runs the code under test,
 *   then writes END_MARK.  A post-processing script reads the gem5 Exec
 *   trace to find the tick of each marker store and computes the delta.
 */

    .syntax unified
    .cpu cortex-m4
    .fpu fpv4-sp-d16
    .thumb

    .equ MARKER_ADDR, 0x20000110
    .equ RESULT_ADDR, 0x20000100
    .equ PASS_VAL,    0xCAFECAFE
    .equ START_MARK,  0xAAAA0001
    .equ END_MARK,    0xAAAA0002

    .equ SCS_BASE,    0xE000E000
    .equ SYSTICK_CSR, SCS_BASE + 0x010
    .equ SYSTICK_RVR, SCS_BASE + 0x014
    .equ SYSTICK_CVR, SCS_BASE + 0x018
    .equ SCB_SHPR3,   SCS_BASE + 0xD20
    .equ NVIC_ISER0,  SCS_BASE + 0x100
    .equ NVIC_ISPR0,  SCS_BASE + 0x200
    .equ NVIC_IPR0,   SCS_BASE + 0x400

/*
 * BENCH_START: load marker address into r7, write start marker.
 * Clobbers: r0, r7.
 */
.macro BENCH_START
    ldr   r7, =MARKER_ADDR
    ldr   r0, =START_MARK
    str   r0, [r7]
.endm

/*
 * BENCH_END: write end marker, write PASS, then exit via semihosting.
 * Clobbers: r0, r1.
 */
.macro BENCH_END
    ldr   r0, =END_MARK
    str   r0, [r7]
    ldr   r1, =RESULT_ADDR
    ldr   r0, =PASS_VAL
    str   r0, [r1]
    mov   r0, #0x18
    ldr   r1, =0x20026
    bkpt  #0xab
    b     .
.endm

/*
 * VECTOR_TABLE: minimal vector table with initial SP and reset handler.
 * Extra entries can be appended after this macro.
 */
.macro VECTOR_TABLE
    .section .isr_vector, "a", %progbits
    .word _estack
    .word Reset_Handler
.endm

/*
 * VECTOR_TABLE_FULL: vector table with SysTick handler at position 15.
 * Positions 2-14 are filled with a default infinite loop.
 */
.macro VECTOR_TABLE_FULL
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
    .word Default_Handler     /* 14: PendSV */
    .word SysTick_Handler     /* 15: SysTick */
.endm

/*
 * VECTOR_TABLE_WITH_IRQ: full vector table with SysTick + IRQ0 + IRQ1.
 */
.macro VECTOR_TABLE_WITH_IRQ
    VECTOR_TABLE_FULL
    .word IRQ0_Handler        /* 16: IRQ 0 */
    .word IRQ1_Handler        /* 17: IRQ 1 */
.endm

.macro DEFAULT_HANDLER_IMPL
    .section .text
    .thumb_func
    .type Default_Handler, %function
Default_Handler:
    b .
.endm

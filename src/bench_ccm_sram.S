/*
 * Benchmark: CCM SRAM Load/Store — core-coupled memory.
 *
 * The STM32G474RE has 32KB of CCM SRAM at 0x10000000 that is directly
 * connected to the D-bus (no AHB bus matrix arbitration) [RM0440 §2.1].
 * This should give the lowest possible memory latency.
 *
 * Compares against bench_load (SRAM1 at 0x20000000) which goes through
 * the AHB bus matrix (system_bus in gem5).
 *
 * Part A: 50 independent LDR from CCM SRAM
 * Part B: 50 STR to CCM SRAM
 *
 * Expected: same as SRAM (0 WS), but no bus arbitration overhead.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =0x10000200     /* CCM SRAM address */
    mov r0, #42
    str r0, [r6]             /* initialize */

    /* warmup */
    .rept 50
    ldr r0, [r6]
    .endr
    .rept 50
    str r0, [r6]
    .endr

    BENCH_START

    /* Part A: 50 loads from CCM SRAM */
    .rept 50
    ldr r0, [r6]
    .endr

    /* Part B: 50 stores to CCM SRAM */
    .rept 50
    str r0, [r6]
    .endr

    BENCH_END

    VECTOR_TABLE

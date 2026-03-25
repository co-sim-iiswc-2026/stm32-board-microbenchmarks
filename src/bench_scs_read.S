/*
 * Benchmark: SCS Register Read Latency.
 *
 * Reads from System Control Space registers (NVIC, SCB, SysTick) via
 * the system bus (PPB at 0xE000E000).  These are MMIO accesses that
 * go through the system_bus in gem5.
 *
 * Tests multiple SCS registers to measure the PPB access latency:
 *   - CPUID (0xE000ED00) — read-only, always accessible
 *   - ICSR  (0xE000ED04) — interrupt control state
 *   - SYST_CVR (0xE000E018) — SysTick current value
 *
 * 50 reads total (mix of registers to avoid merging).
 *
 * Expected: 2-4 cy per read (PPB is 0 WS but through system bus)
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =SCS_BASE       /* 0xE000E000 */

    /* warmup */
    .rept 10
    ldr r0, [r6, #0x18]     /* SYST_CVR */
    .endr

    BENCH_START

    /* 50 SCS register reads — mix of registers */
    .rept 25
    ldr r0, [r6, #0x18]     /* SYST_CVR:  SCS_BASE + 0x018 */
    ldr r1, [r6, #0x10]     /* SYST_CSR:  SCS_BASE + 0x010 */
    .endr

    BENCH_END

    VECTOR_TABLE

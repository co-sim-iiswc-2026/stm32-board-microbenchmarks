/*
 * Benchmark: SCS Register Store Latency.
 *
 * Companion to bench_scs_read.  Writes to SCS registers go through
 * the system bus to the PPB region (0xE000E000).  SCS writes can have
 * side effects (e.g., enabling interrupts, clearing pending bits), so
 * we pick safe registers.
 *
 * We write to SYST_CVR (0xE000E018) which clears the counter — safe
 * to write repeatedly without side effects beyond resetting the timer.
 * Also write to NVIC_ICPR0 (0xE000E280) to clear pending bits (no-op
 * if nothing is pending).
 *
 * 50 SCS register writes.
 *
 * Expected: 1-2 cy per write (PPB is 0 WS, write-buffered through system bus)
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =SCS_BASE       /* 0xE000E000 */
    mov r0, #0

    /* warmup */
    .rept 10
    str r0, [r6, #0x18]     /* SYST_CVR: clear */
    .endr

    BENCH_START

    /* 50 SCS register writes — mix of registers */
    .rept 25
    str r0, [r6, #0x18]     /* SYST_CVR:   SCS_BASE + 0x018 */
    str r0, [r6, #0x280]    /* NVIC_ICPR0: SCS_BASE + 0x280 */
    .endr

    BENCH_END

    VECTOR_TABLE

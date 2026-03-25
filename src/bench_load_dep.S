/*
 * Benchmark: Dependent LDR Chain — serialized load latency.
 *
 * bench_load uses independent loads (LDR r0, [r6], same address, no dep).
 * The M4 TRM (DDI0439D §3.3.2 p.3-12) says: "If the next instruction is
 * an LDR or STR, and the destination of the first LDR is not used to
 * compute the address for the next instruction, then one cycle is removed."
 *
 * This benchmark creates a dependent chain where each LDR's result is
 * used as the address for the next: LDR r6, [r6].  This prevents the
 * pipelining optimization and forces the full 2-cycle LDR latency.
 *
 * Setup: SRAM[0x20000200] = 0x20000200 (self-pointer).
 * 50 dependent LDRs.
 *
 * Expected with ART:    ~104 cy (50 x 2 + 4 overhead)
 * Expected without ART: ~129 cy (25 fetches x 5 cy, but exec-bound: 100 cy)
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    /* Set up self-referencing pointer: MEM[0x20000200] = 0x20000200 */
    ldr r6, =0x20000200
    str r6, [r6]

    /* warmup */
    .rept 50
    ldr r6, [r6]
    .endr

    /* Reload pointer (may have been clobbered if warmup address changed) */
    ldr r6, =0x20000200

    BENCH_START

    .rept 50
    ldr r6, [r6]           /* dependent: result → next address */
    .endr

    BENCH_END

    VECTOR_TABLE

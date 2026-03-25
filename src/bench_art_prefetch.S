/*
 * Benchmark: ART Prefetch Buffer — Sequential 16-bit instruction throughput.
 *
 * Validates the ART accelerator's prefetch mechanism from the STM32G4 Flash
 * PDF (slide 16):
 *   - On miss: instruction fetched from Flash (WS penalty), 64-bit line
 *     copied to currentBuffer and I-Cache.
 *   - With prefetch enabled: next sequential 64-bit line fetched into
 *     prefetchBuffer in parallel.
 *   - Subsequent sequential accesses served from currentBuffer (0 WS).
 *   - prefetchBuffer promoted to currentBuffer, new prefetch started.
 *
 * Test: 200 sequential 16-bit NOP instructions after warmup.
 *
 * Expected results:
 *   With ART prefetch (0 WS): ~200 cycles (1 cycle/instruction)
 *   Without ART (raw flash, 4 WS @ 170MHz): ~1000 cycles
 *
 * Each 4-byte CPU fetch carries 2 x 16-bit NOPs.
 * Each 8-byte ART buffer line carries 4 x 16-bit NOPs.
 * With prefetch, flash latency is hidden after initial cold miss.
 *
 * The warmup section fills the ART pipeline so the measured region starts
 * in steady state.  We use .align 8 to ensure the measured section starts
 * on an 8-byte (double-word) boundary matching the ART buffer alignment.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    /*
     * Warmup: run enough NOPs to fill the ART pipeline (currentBuffer,
     * prefetchBuffer, and I-Cache).  This ensures the first measured
     * instruction hits in the ART buffers, not a cold miss.
     * 64 NOPs = 128 bytes = 16 double-words — more than enough to
     * warm up the 2-buffer ART prefetcher.
     */
    .rept 64
    nop
    .endr

    /* Align measured region to 8-byte boundary (ART double-word). */
    .balign 8

    BENCH_START

    /*
     * Measured region: 200 sequential 16-bit NOP instructions.
     *   200 NOPs x 2 bytes = 400 bytes = 50 double-words.
     *   With ART prefetch: expect ~200 cycles (1 cy/NOP).
     *   Without ART: expect ~200 + (50 fetches x WS) cycles.
     */
    .rept 200
    nop
    .endr

    BENCH_END

    VECTOR_TABLE

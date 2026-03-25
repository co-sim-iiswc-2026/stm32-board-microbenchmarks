/*
 * Benchmark: ART I-Cache Capacity Miss.
 *
 * The ART I-Cache is 1KB (32 lines x 4 x 8B sectors) [RM0440 §4.2].
 * This benchmark loops through a code body larger than 1KB to force
 * capacity misses on every pass through the loop.
 *
 * Strategy: Create a ~2KB NOP sled (1024 NOPs x 2 bytes = 2048 bytes),
 * then loop through it.  On the second iteration, the beginning of the
 * sled has been evicted from the 1KB I-Cache, causing misses.
 *
 * 4 iterations of the 2KB sled = ~4096 NOPs.
 *
 * Expected with ART (steady state): cache miss rate ~50%.
 *   Half the NOPs hit, half miss (each miss = 5 cy Flash fetch).
 *   Estimate: 4096 x ~1.5 cy = ~6000 cy
 *
 * Expected without ART: 4096 x 2.5 cy = ~10240 cy (all miss)
 *
 * Comparing this against bench_nop (100% I-Cache hit) isolates the
 * ART cache miss penalty.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    mov r4, #0               /* iteration counter */

    /* warmup: 1 pass through the sled */
    .rept 1024
    nop
    .endr

    BENCH_START

    /* Loop 4 times through a 2KB NOP sled */
.Louter:
    .rept 1024
    nop                       /* 1024 NOPs = 2048 bytes = 2KB */
    .endr

    adds r4, r4, #1
    cmp r4, #4
    bne .Louter

    BENCH_END

    VECTOR_TABLE

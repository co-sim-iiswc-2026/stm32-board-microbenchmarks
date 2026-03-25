/*
 * Benchmark: Store Buffer Saturation — rapid STR to different addresses.
 *
 * bench_store writes to the same address (0x20000200) repeatedly.  The
 * write buffer can merge/coalesce same-address writes.  This benchmark
 * writes to 50 consecutive SRAM addresses to test write buffer depth
 * and saturation behavior.
 *
 * DDI0439D §3.3.2 p.3-11: "STR Rx,[Ry,#imm] is always one cycle."
 * But this assumes the write buffer is not full.  When the buffer fills,
 * the pipeline stalls until a slot frees up.
 *
 * 50 STR to different SRAM addresses (stride = 4 bytes).
 *
 * Expected with ART:    ~54 cy if buffer never fills (50 x 1 + 4)
 *                        higher if buffer saturates
 * Expected without ART: ~129 cy (fetch-bound: 25 fetches x 5 cy)
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    ldr r6, =0x20000200
    mov r0, #42

    /* warmup */
    .set OFF, 0
    .rept 50
    str r0, [r6, #OFF]
    .set OFF, OFF + 4
    .endr

    /* Reset base for measured region */
    ldr r6, =0x20000200

    BENCH_START

    /* 50 stores to consecutive SRAM addresses */
    .set OFF, 0
    .rept 50
    str r0, [r6, #OFF]
    .set OFF, OFF + 4
    .endr

    BENCH_END

    VECTOR_TABLE

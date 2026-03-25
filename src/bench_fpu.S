/*
 * Benchmark 12: FPU Basic Operations.
 * Part A: 20 iterations of VADD+VMUL (1 cy each) = 40 cycles.
 * Part B: 5 iterations of VDIV (14 cy each on real M4) = 70 cycles.
 * Expected total: 110 cycles on real M4.
 * gem5 model: VDIV uses opLat=1 (known gap), so expect ~45 cycles.
 * Validates: FPU single-cycle ops vs multi-cycle VDIV.
 */
    .include "src/bench_macros.inc"

    .section .text
    .global Reset_Handler
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    vmov s0, #1.0
    vmov s1, #2.0

    /* warmup */
    .rept 20
    vadd.f32 s2, s0, s1
    vmul.f32 s3, s0, s1
    .endr
    .rept 5
    vdiv.f32 s4, s0, s1
    .endr

    BENCH_START

    .rept 20
    vadd.f32 s2, s0, s1
    vmul.f32 s3, s0, s1
    .endr
    .rept 5
    vdiv.f32 s4, s0, s1
    .endr

    BENCH_END

    VECTOR_TABLE

#ifndef KERNELS_SDIV_CALIBRATION_H
#define KERNELS_SDIV_CALIBRATION_H

// SDIV latency-calibration kernels.
//
// Each kernel:
//   1. Loads the dividend into r0 and divisor into r1.
//   2. Issues N back-to-back `sdiv r2, r0, r1` instructions.
//
// By measuring the same body at multiple N values per dividend, the
// linear fit `cycles(N) = N * per_sdiv_cy + glue_cy` separates the
// per-SDIV latency (slope) from the per-call glue (intercept).
//
// Each kernel is decorated `static inline void __attribute__((always_inline))`
// (locally re-defined as `KERNEL_INLINE` below — `kernels_inline.h` undefs
// the macro at its end of file, so this header re-defines its own copy).
//
// IMPORTANT: keep the dividend-load form identical to the original
// bench-div / bench-div_short kernels — the compiler should emit
// `mvn r0, #0x80000000` for 0x7FFFFFFF and `mov.w r0, #imm` for
// small immediates.  Any deviation here changes the kernel-body
// layout and the slope measurement.

#define KERNEL_INLINE static inline void __attribute__((always_inline))

// Baseline: dividend setup + bx_lr, zero SDIVs.  Pure per-call glue
// measurement.
KERNEL_INLINE bench_sdiv_cal_baseline_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mvn r0, #0x80000000 \n"   // r0 = 0x7FFFFFFF
        "mov r1, #1          \n"
        ::: "r0", "r1", "memory"
    );
}

// =========================================================================
// Dividend = 0x7FFFFFFF (sigBits = 31, formula = 12 cy)
// =========================================================================
KERNEL_INLINE bench_sdiv_cal_max_10_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mvn r0, #0x80000000 \n"
        "mov r1, #1          \n"
        ".rept 10            \n"
        "sdiv r2, r0, r1    \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "memory"
    );
}

KERNEL_INLINE bench_sdiv_cal_max_20_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mvn r0, #0x80000000 \n"
        "mov r1, #1          \n"
        ".rept 20            \n"
        "sdiv r2, r0, r1    \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "memory"
    );
}

KERNEL_INLINE bench_sdiv_cal_max_40_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mvn r0, #0x80000000 \n"
        "mov r1, #1          \n"
        ".rept 40            \n"
        "sdiv r2, r0, r1    \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "memory"
    );
}

// =========================================================================
// Dividend = 0xFF (sigBits = 8, formula = 6 cy) — single mid-point
// =========================================================================
KERNEL_INLINE bench_sdiv_cal_mid_20_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #0xFF       \n"
        "mov r1, #1          \n"
        ".rept 20            \n"
        "sdiv r2, r0, r1    \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "memory"
    );
}

// =========================================================================
// Dividend = 15 (sigBits = 4, formula = 5 cy)
// =========================================================================
KERNEL_INLINE bench_sdiv_cal_short_10_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #15         \n"
        "mov r1, #3          \n"
        ".rept 10            \n"
        "sdiv r2, r0, r1    \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "memory"
    );
}

KERNEL_INLINE bench_sdiv_cal_short_20_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #15         \n"
        "mov r1, #3          \n"
        ".rept 20            \n"
        "sdiv r2, r0, r1    \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "memory"
    );
}

KERNEL_INLINE bench_sdiv_cal_short_40_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #15         \n"
        "mov r1, #3          \n"
        ".rept 40            \n"
        "sdiv r2, r0, r1    \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "memory"
    );
}

#undef KERNEL_INLINE

#endif // KERNELS_SDIV_CALIBRATION_H

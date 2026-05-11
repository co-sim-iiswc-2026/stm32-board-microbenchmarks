#ifndef KERNELS_FPU_CALIBRATION_H
#define KERNELS_FPU_CALIBRATION_H

// FPU-ALU latency-calibration kernels.
//
// Each kernel:
//   1. Loads operands into S/D/R registers OUTSIDE the .rept block
//      (so per-iteration cost is only the target inst, not setup).
//   2. Issues 100 back-to-back instances of one FPU-ALU instruction.
//
// Each kernel is decorated `static inline void __attribute__((always_inline))`
// (locally re-defined as `KERNEL_INLINE` below — `kernels_inline.h`
// undefs the macro at its end of file, so this header defines its
// own copy, mirroring `sdiv_calibration/kernels.h`).
//
// Operand-setup rules (avoid traps / denormal cascades over 100 iters):
//   - Arithmetic / fused: s0=1.0, s1=2.0 (encodable in VMOV.F32 imm).
//   - VDIV: s0=8.0, s1=2.0  → quotient = 4.0 stays normal.
//   - VSQRT: s0=4.0          → result   = 2.0 stays normal.
//   - VABS/VNEG: s0=-1.5     (normal, non-zero, non-NaN).
//   - VCVT s32→f32: r0=42 → vmov s0,r0 (int bit pattern in s0).
//   - VCVT f32→s32: s0=16.0 (round-trip-safe integer-valued float).
//   - VMRS / VMSR: r0=0 for VMSR (keeps FPSCR clean).
//   - VCMP / VCMPE: s0=1.0, s1=2.0 (compares cleanly).
//
// Scope: FP-ALU only.  Memory FPU (VLDR/VSTR/VLDM/VSTM/VPUSH/VPOP)
// is excluded — those hit the LSQ/flash subsystem and are tracked in
// a separate calibration.

#define KERNEL_INLINE static inline void __attribute__((always_inline))

// =========================================================================
// Baseline — setup only, no FPU op.  Per-call cycle = pure glue.
// =========================================================================
KERNEL_INLINE bench_fpu_cal_baseline_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        "vmov.f32 s1, #2.0   \n"
        ::: "s0", "s1", "memory"
    );
}

// =========================================================================
// MFpBinS — VADD, VSUB, VMUL, VNMUL, VDIV
// =========================================================================
KERNEL_INLINE bench_fpu_cal_vadd_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        "vmov.f32 s1, #2.0   \n"
        ".rept 100           \n"
        "vadd.f32 s2, s0, s1 \n"
        ".endr               \n"
        ::: "s0", "s1", "s2", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vsub_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #2.0   \n"
        "vmov.f32 s1, #1.0   \n"
        ".rept 100           \n"
        "vsub.f32 s2, s0, s1 \n"
        ".endr               \n"
        ::: "s0", "s1", "s2", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vmul_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        "vmov.f32 s1, #2.0   \n"
        ".rept 100           \n"
        "vmul.f32 s2, s0, s1 \n"
        ".endr               \n"
        ::: "s0", "s1", "s2", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vnmul_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0    \n"
        "vmov.f32 s1, #2.0    \n"
        ".rept 100            \n"
        "vnmul.f32 s2, s0, s1 \n"
        ".endr                \n"
        ::: "s0", "s1", "s2", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vdiv_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #8.0   \n"   // dividend
        "vmov.f32 s1, #2.0   \n"   // divisor; quotient=4.0 stays normal
        ".rept 100           \n"
        "vdiv.f32 s2, s0, s1 \n"
        ".endr               \n"
        ::: "s0", "s1", "s2", "memory"
    );
}

// =========================================================================
// MFpTernaryS — VMLA, VMLS (non-fused multiply-accumulate, 2 roundings)
// =========================================================================
// VMLA writes s2 = s2 + (s0 * s1).  Each iter overwrites s2, so even
// though s2 grows mathematically across iters it never escalates —
// gcc will hold s2 in a register and the kernel runs forever fine.
// We deliberately initialize s2 to a finite value before the .rept.
KERNEL_INLINE bench_fpu_cal_vmla_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        "vmov.f32 s1, #2.0   \n"
        "vmov.f32 s2, #0.5   \n"   // accumulator
        ".rept 100           \n"
        "vmla.f32 s2, s0, s1 \n"
        ".endr               \n"
        ::: "s0", "s1", "s2", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vmls_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        "vmov.f32 s1, #2.0   \n"
        "vmov.f32 s2, #0.5   \n"
        ".rept 100           \n"
        "vmls.f32 s2, s0, s1 \n"
        ".endr               \n"
        ::: "s0", "s1", "s2", "memory"
    );
}

// =========================================================================
// MFpFusedMulAddS — VFMA, VFMS (fused multiply-add, 1 rounding)
// =========================================================================
KERNEL_INLINE bench_fpu_cal_vfma_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        "vmov.f32 s1, #2.0   \n"
        "vmov.f32 s2, #0.5   \n"
        ".rept 100           \n"
        "vfma.f32 s2, s0, s1 \n"
        ".endr               \n"
        ::: "s0", "s1", "s2", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vfms_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        "vmov.f32 s1, #2.0   \n"
        "vmov.f32 s2, #0.5   \n"
        ".rept 100           \n"
        "vfms.f32 s2, s0, s1 \n"
        ".endr               \n"
        ::: "s0", "s1", "s2", "memory"
    );
}

// =========================================================================
// MFpUnaryS — VNEG, VABS, VSQRT
// =========================================================================
KERNEL_INLINE bench_fpu_cal_vneg_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #-1.5  \n"
        ".rept 100           \n"
        "vneg.f32 s1, s0     \n"
        ".endr               \n"
        ::: "s0", "s1", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vabs_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #-1.5  \n"
        ".rept 100           \n"
        "vabs.f32 s1, s0     \n"
        ".endr               \n"
        ::: "s0", "s1", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vsqrt_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #4.0   \n"   // sqrt(4.0) = 2.0, stays normal
        ".rept 100           \n"
        "vsqrt.f32 s1, s0    \n"
        ".endr               \n"
        ::: "s0", "s1", "memory"
    );
}

// =========================================================================
// MFpMov*S — VMOV variants
// =========================================================================
// VMOV immediate: a different immediate per iter would defeat the
// purpose (we'd be measuring assembler unrolling, not the inst); use
// the same immediate every time.
KERNEL_INLINE bench_fpu_cal_vmov_imm_kernel() {
    asm volatile(
        ".balign 16          \n"
        ".rept 100           \n"
        "vmov.f32 s0, #1.0   \n"
        ".endr               \n"
        ::: "s0", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vmov_reg_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        ".rept 100           \n"
        "vmov.f32 s1, s0     \n"
        ".endr               \n"
        ::: "s0", "s1", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vmov_core_to_s_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #42         \n"
        ".rept 100           \n"
        "vmov s0, r0         \n"
        ".endr               \n"
        ::: "r0", "s0", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vmov_s_to_core_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        ".rept 100           \n"
        "vmov r0, s0         \n"
        ".endr               \n"
        ::: "r0", "s0", "memory"
    );
}

// =========================================================================
// MFpCmpS — VCMP, VCMPE
// =========================================================================
// VCMP / VCMPE update FPSCR.NZCV.  This is harmless across iterations
// — each iter sets the same flag state given identical operands.
KERNEL_INLINE bench_fpu_cal_vcmp_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        "vmov.f32 s1, #2.0   \n"
        ".rept 100           \n"
        "vcmp.f32 s0, s1     \n"
        ".endr               \n"
        ::: "s0", "s1", "memory"
    );
}

KERNEL_INLINE bench_fpu_cal_vcmpe_kernel() {
    asm volatile(
        ".balign 16          \n"
        "vmov.f32 s0, #1.0   \n"
        "vmov.f32 s1, #2.0   \n"
        ".rept 100           \n"
        "vcmpe.f32 s0, s1    \n"
        ".endr               \n"
        ::: "s0", "s1", "memory"
    );
}

// =========================================================================
// MFpCvtS — integer ↔ float conversions
// =========================================================================
// VCVT.F32.S32: interprets sm as a signed 32-bit int, converts to f32 in sd.
// We pre-load r0=42 into s0 (as int bits) so the input is integer-valued.
KERNEL_INLINE bench_fpu_cal_vcvt_f32_s32_kernel() {
    asm volatile(
        ".balign 16            \n"
        "mov r0, #42           \n"
        "vmov s0, r0           \n"   // s0 holds bit pattern of int 42
        ".rept 100             \n"
        "vcvt.f32.s32 s1, s0   \n"
        ".endr                 \n"
        ::: "r0", "s0", "s1", "memory"
    );
}

// VCVT.S32.F32: converts f32 in sm to s32 (truncating) in sd.
KERNEL_INLINE bench_fpu_cal_vcvt_s32_f32_kernel() {
    asm volatile(
        ".balign 16            \n"
        "vmov.f32 s0, #16.0    \n"   // round-trip-safe integer
        ".rept 100             \n"
        "vcvt.s32.f32 s1, s0   \n"
        ".endr                 \n"
        ::: "s0", "s1", "memory"
    );
}

// =========================================================================
// MFpMrs / MFpMsr — FPSCR access
// =========================================================================
KERNEL_INLINE bench_fpu_cal_vmrs_kernel() {
    asm volatile(
        ".balign 16          \n"
        ".rept 100           \n"
        "vmrs r0, fpscr      \n"
        ".endr               \n"
        ::: "r0", "memory"
    );
}

// VMSR writes FPSCR.  r0=0 preserves "round-to-nearest, no exceptions,
// no flush-to-zero" — a clean state so the kernel doesn't accidentally
// destabilize floating-point behavior across iterations.
KERNEL_INLINE bench_fpu_cal_vmsr_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #0          \n"
        ".rept 100           \n"
        "vmsr fpscr, r0      \n"
        ".endr               \n"
        ::: "r0", "memory"
    );
}

#undef KERNEL_INLINE

#endif // KERNELS_FPU_CALIBRATION_H

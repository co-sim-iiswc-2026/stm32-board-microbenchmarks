#ifndef KERNELS_V2_INLINE_H
#define KERNELS_V2_INLINE_H

// V2 kernels: match the register usage from the original standalone
// benchmarks in src/*.S (between BENCH_START and BENCH_END).
//
// Key differences vs v1:
//   - Independent destination registers (r4/r5) where originals use them,
//     eliminating data dependencies present in v1
//   - pushpop matches original: push/pop {r0-r7, lr} + push/pop {r0-r3}
//   - bp_forward/bp_nested use r4/r5 as in originals
//
// Encoding note: "mov Rd, #imm" generates 32-bit mov.w in both standalone
// .S and inline asm under .syntax unified. This matches the originals.

#define KERNEL_V2_INLINE static inline void __attribute__((always_inline))

// =========================================================================
// Compute
// =========================================================================

// v1: writes to r0/r2 (data dependencies, all 32-bit add.w/sub.w)
// v2: writes to r4/r5 (independent), add/sub without .w still 32-bit
//     in unified syntax — matching original encoding
KERNEL_V2_INLINE bench_alu_v2_kernel() {
    asm volatile(
        ".balign 16          \n"
        ".rept 25            \n"
        "add   r4, r0, r1   \n"
        "sub   r5, r2, r3   \n"
        "and.w r4, r0, r2   \n"
        "orr.w r5, r1, r3   \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "r3", "r4", "r5", "memory"
    );
}

// v1: writes to r0/r2 (data deps)
// v2: writes to r4/r5 (independent, matches original)
KERNEL_V2_INLINE bench_alu16_v2_kernel() {
    asm volatile(
        ".balign 16          \n"
        ".rept 25            \n"
        "adds r4, r0, r1    \n"
        "subs r5, r2, r3    \n"
        "eors r4, r4, r2    \n"
        "orrs r5, r5, r3    \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "r3", "r4", "r5", "memory"
    );
}

// v1: 8x mov (r0-r7), push/pop {r0-r7} (no lr), extra push/pop {r4-r7}
// v2: 6x mov (r0-r5), push/pop {r0-r7, lr}, push/pop {r0-r3}
//     matches original between BENCH_START and BENCH_END
KERNEL_V2_INLINE bench_pushpop_v2_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #0          \n"
        "mov r1, #1          \n"
        "mov r2, #2          \n"
        "mov r3, #3          \n"
        "mov r4, #4          \n"
        "mov r5, #5          \n"
        "push {r0-r7, lr}    \n"
        "pop  {r0-r7, lr}    \n"
        "push {r0-r3}        \n"
        "pop  {r0-r3}        \n"
        ::: "r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "lr", "memory"
    );
}

// v1: writes to r0/r2 (data deps)
// v2: writes to r4/r5 (independent, matches original)
KERNEL_V2_INLINE bench_mixed_width_v2_kernel() {
    asm volatile(
        ".balign 16          \n"
        ".rept 25            \n"
        "nop                 \n"
        "and.w r4, r0, r2   \n"
        "nop                 \n"
        "orr.w r5, r1, r3   \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "r3", "r4", "r5", "memory"
    );
}

// =========================================================================
// Branch — only those with different registers from v1
// =========================================================================

// v1: r0/r1; v2: r4/r5 (matches original)
KERNEL_V2_INLINE bench_bp_forward_v2_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r4, #0          \n"
        "mov r5, #100        \n"
        "1:                  \n"
        "cmp r4, r4          \n"
        "beq 2f              \n"
        "nop                 \n"
        "nop                 \n"
        "2:                  \n"
        "subs r5, r5, #1    \n"
        "bne 1b              \n"
        ::: "r4", "r5", "memory"
    );
}

// v1: r0/r1; v2: r4/r5 (matches original)
KERNEL_V2_INLINE bench_bp_nested_v2_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r4, #20         \n"
        "1:                  \n"
        "mov r5, #10         \n"
        "2:                  \n"
        "subs r5, r5, #1    \n"
        "bne 2b              \n"
        "subs r4, r4, #1    \n"
        "bne 1b              \n"
        ::: "r4", "r5", "memory"
    );
}

#undef KERNEL_V2_INLINE
#endif // KERNELS_V2_INLINE_H

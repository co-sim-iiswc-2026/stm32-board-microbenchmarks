#ifndef KERNELS_FETCH_CHAR_H
#define KERNELS_FETCH_CHAR_H

// Fetch characterization benchmarks for STM32G474RE ART accelerator.
// Designed to isolate flash fetch behavior, branch taken cost,
// prefetch buffer depth, and ART cache capacity.

#define KERNEL_FC_INLINE static inline void __attribute__((always_inline))

// =========================================================================
// Group 1: Flash Fetch Baseline & Wait State Validation
// =========================================================================

// Straight-line 16-bit NOPs — varying length
KERNEL_FC_INLINE bench_fetch_nop16_8_kernel() {
    asm volatile(".balign 16 \n" ".rept 8  \n nop \n .endr" ::: "memory");
}
KERNEL_FC_INLINE bench_fetch_nop16_16_kernel() {
    asm volatile(".balign 16 \n" ".rept 16 \n nop \n .endr" ::: "memory");
}
KERNEL_FC_INLINE bench_fetch_nop16_32_kernel() {
    asm volatile(".balign 16 \n" ".rept 32 \n nop \n .endr" ::: "memory");
}
KERNEL_FC_INLINE bench_fetch_nop16_64_kernel() {
    asm volatile(".balign 16 \n" ".rept 64 \n nop \n .endr" ::: "memory");
}
KERNEL_FC_INLINE bench_fetch_nop16_128_kernel() {
    asm volatile(".balign 16 \n" ".rept 128 \n nop \n .endr" ::: "memory");
}
KERNEL_FC_INLINE bench_fetch_nop16_256_kernel() {
    asm volatile(".balign 16 \n" ".rept 256 \n nop \n .endr" ::: "memory");
}

// Straight-line 32-bit instructions — varying length
// add.w r0, r0, #0 is a 32-bit NOP-equivalent (no side effects except flags)
KERNEL_FC_INLINE bench_fetch_nop32_8_kernel() {
    asm volatile(".balign 16 \n" ".rept 8   \n add.w r0, r0, #0 \n .endr" ::: "r0", "memory");
}
KERNEL_FC_INLINE bench_fetch_nop32_16_kernel() {
    asm volatile(".balign 16 \n" ".rept 16  \n add.w r0, r0, #0 \n .endr" ::: "r0", "memory");
}
KERNEL_FC_INLINE bench_fetch_nop32_32_kernel() {
    asm volatile(".balign 16 \n" ".rept 32  \n add.w r0, r0, #0 \n .endr" ::: "r0", "memory");
}
KERNEL_FC_INLINE bench_fetch_nop32_64_kernel() {
    asm volatile(".balign 16 \n" ".rept 64  \n add.w r0, r0, #0 \n .endr" ::: "r0", "memory");
}
KERNEL_FC_INLINE bench_fetch_nop32_128_kernel() {
    asm volatile(".balign 16 \n" ".rept 128 \n add.w r0, r0, #0 \n .endr" ::: "r0", "memory");
}

// Clock/counter validation: tight cached loop, known cycle count
// 100 × (subs + bne) = 100 × 3 = 300 cycles with cache ON
KERNEL_FC_INLINE bench_fetch_ws_validate_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "1:                  \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "memory"
    );
}

// =========================================================================
// Group 2: Branch Taken Fetch Cost
// =========================================================================

// Backward branch with varying body size: N NOPs + subs + bne
// Measures how branch distance affects refetch cost

KERNEL_FC_INLINE bench_br_back_0_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "1:                  \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_br_back_1_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "1:                  \n"
        "nop                 \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_br_back_2_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "1:                  \n"
        ".rept 2 \n nop \n .endr \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_br_back_4_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "1:                  \n"
        ".rept 4 \n nop \n .endr \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_br_back_8_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "1:                  \n"
        ".rept 8 \n nop \n .endr \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_br_back_16_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "1:                  \n"
        ".rept 16 \n nop \n .endr \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_br_back_32_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "1:                  \n"
        ".rept 32 \n nop \n .endr \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_br_back_64_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "1:                  \n"
        ".rept 64 \n nop \n .endr \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "memory"
    );
}

// Forward branch with varying skip distance
// 100 iterations: cmp r1,r1 + beq(fwd, skip N nops) + N nops + subs + bne(back)

KERNEL_FC_INLINE bench_br_fwd_0_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "mov r1, #0          \n"
        "1:                  \n"
        "cmp r1, r1          \n"
        "beq 2f              \n"
        "2:                  \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_br_fwd_2_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "mov r1, #0          \n"
        "1:                  \n"
        "cmp r1, r1          \n"
        "beq 2f              \n"
        ".rept 2 \n nop \n .endr \n"
        "2:                  \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_br_fwd_4_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "mov r1, #0          \n"
        "1:                  \n"
        "cmp r1, r1          \n"
        "beq 2f              \n"
        ".rept 4 \n nop \n .endr \n"
        "2:                  \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_br_fwd_8_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "mov r1, #0          \n"
        "1:                  \n"
        "cmp r1, r1          \n"
        "beq 2f              \n"
        ".rept 8 \n nop \n .endr \n"
        "2:                  \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_br_fwd_16_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "mov r1, #0          \n"
        "1:                  \n"
        "cmp r1, r1          \n"
        "beq 2f              \n"
        ".rept 16 \n nop \n .endr \n"
        "2:                  \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_br_fwd_32_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "mov r1, #0          \n"
        "1:                  \n"
        "cmp r1, r1          \n"
        "beq 2f              \n"
        ".rept 32 \n nop \n .endr \n"
        "2:                  \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "r1", "memory"
    );
}

// Not-taken branch baseline
// 100 iterations: cmp + bne(never taken) + nop + subs + bne(back)
KERNEL_FC_INLINE bench_br_nottaken_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100        \n"
        "mov r1, #0          \n"
        "1:                  \n"
        "cmp r1, #1          \n"
        "bne 2f              \n"
        "nop                 \n"
        "2:                  \n"
        "subs r0, r0, #1    \n"
        "bne 1b              \n"
        ::: "r0", "r1", "memory"
    );
}

// =========================================================================
// Group 3: Fetch Pipeline / Prefetch Buffer
// =========================================================================

// Sequential code crossing cache line boundaries (8-byte aligned)
KERNEL_FC_INLINE bench_fetch_seq_4_kernel() {
    asm volatile(".balign 16 \n" ".balign 8 \n .rept 4  \n nop \n .endr" ::: "memory");
}
KERNEL_FC_INLINE bench_fetch_seq_8_kernel() {
    asm volatile(".balign 16 \n" ".balign 8 \n .rept 8  \n nop \n .endr" ::: "memory");
}
KERNEL_FC_INLINE bench_fetch_seq_16_kernel() {
    asm volatile(".balign 16 \n" ".balign 8 \n .rept 16 \n nop \n .endr" ::: "memory");
}
KERNEL_FC_INLINE bench_fetch_seq_32_kernel() {
    asm volatile(".balign 16 \n" ".balign 8 \n .rept 32 \n nop \n .endr" ::: "memory");
}

// Interleave multi-cycle ops with NOPs to test prefetch overlap
// Pattern A: mul.w (1-cycle on M4) + 3 NOPs, repeated 25 times = 100 instructions
KERNEL_FC_INLINE bench_fetch_interleave_mul_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #7          \n"
        "mov r1, #13         \n"
        ".rept 25            \n"
        "mul.w r2, r0, r1   \n"
        "nop                 \n"
        "nop                 \n"
        "nop                 \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "memory"
    );
}

// Pattern B: sdiv (multi-cycle) + NOPs — div gives prefetcher more time
KERNEL_FC_INLINE bench_fetch_interleave_div_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #15         \n"
        "mov r1, #3          \n"
        ".rept 20            \n"
        "sdiv r2, r0, r1    \n"
        "nop                 \n"
        "nop                 \n"
        "nop                 \n"
        "nop                 \n"
        ".endr               \n"
        ::: "r0", "r1", "r2", "memory"
    );
}

// =========================================================================
// Group 4: ART Cache Capacity
// =========================================================================

// Loop bodies of increasing size to find ART cache capacity transition
// N NOPs + subs + bne, 100 iterations each

KERNEL_FC_INLINE bench_art_cap_32_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 32 \n nop \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_art_cap_64_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 64 \n nop \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_art_cap_128_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 128 \n nop \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_art_cap_256_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 256 \n nop \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "memory"
    );
}

KERNEL_FC_INLINE bench_art_cap_512_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 512 \n nop \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "memory"
    );
}

// Too large for inline asm. Defined in kernel_art_cap_1024.S.
extern "C" void bench_art_cap_1024_asm(void);
KERNEL_FC_INLINE bench_art_cap_1024_kernel() {
    bench_art_cap_1024_asm();
}

// =========================================================================
// Group 4b: ART Cache Capacity — 32-bit instructions
// =========================================================================

// Same structure as 16-bit art_cap but using add.w r0, r0, #0 (32-bit NOP)
// N 32-bit instructions + subs + bne, 100 iterations

KERNEL_FC_INLINE bench_art_cap32_64_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 64 \n add.w r1, r1, #0 \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_art_cap32_128_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 128 \n add.w r1, r1, #0 \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_art_cap32_256_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 256 \n add.w r1, r1, #0 \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "r1", "memory"
    );
}

// =========================================================================
// Group 4c: ART Cache Capacity — Mixed width (alternating 16+32)
// =========================================================================

// Alternating nop (16-bit) + add.w (32-bit) = 6 bytes per pair
// N pairs = N*2 instructions, 100 iterations

KERNEL_FC_INLINE bench_art_capmix_32_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 32 \n nop \n add.w r1, r1, #0 \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_art_capmix_64_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 64 \n nop \n add.w r1, r1, #0 \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_art_capmix_128_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 128 \n nop \n add.w r1, r1, #0 \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_art_capmix_256_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 256 \n nop \n add.w r1, r1, #0 \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "r1", "memory"
    );
}

// =========================================================================
// Group 4d: ART Cache Capacity — Different mix ratios
// =========================================================================
// Naming: art_mix<16count>x<32count>_<total_pairs>
// Bytes per pair shown in comments

// 3:1 ratio — three 16-bit + one 32-bit = 10 bytes per 4 instructions (2.5 bytes/instr)
KERNEL_FC_INLINE bench_art_mix3x1_64_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 64 \n nop \n nop \n nop \n add.w r1, r1, #0 \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "r1", "memory"
    );
}

KERNEL_FC_INLINE bench_art_mix3x1_128_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 128 \n nop \n nop \n nop \n add.w r1, r1, #0 \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "r1", "memory"
    );
}

// 1:3 ratio — one 16-bit + three 32-bit = 14 bytes per 4 instructions (3.5 bytes/instr)
KERNEL_FC_INLINE bench_art_mix1x3_64_kernel() {
    asm volatile(
        ".balign 16          \n"
        "mov r0, #100 \n 1: \n"
        ".rept 64 \n nop \n add.w r1, r1, #0 \n add.w r2, r2, #0 \n add.w r3, r3, #0 \n .endr \n"
        "subs r0, r0, #1 \n bne 1b \n"
        ::: "r0", "r1", "r2", "r3", "memory"
    );
}

// Too large for inline asm. Defined in kernel_art_mix1x3_128.S.
extern "C" void bench_art_mix1x3_128_asm(void);
KERNEL_FC_INLINE bench_art_mix1x3_128_kernel() {
    bench_art_mix1x3_128_asm();
}

#undef KERNEL_FC_INLINE
#endif // KERNELS_FETCH_CHAR_H

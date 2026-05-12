/*
 * Low-overhead microbenchmark harness for Cortex-M4 — BENCH /
 * END_BENCH macro pair plus internal KERNEL_BEGIN / KERNEL_END helpers.
 *
 * Design goal: every measured rep brackets ONLY the second call into
 * the kernel body, so the warm-cache cycle floor is ~6 cycles on
 * hardware regardless of body size. The harness:
 *
 *   1. emits the user's code as `kernel_body` in its own .text
 *      section (own cache lines), and
 *   2. emits a `bench_entry` wrapper pinned at FLASH+0x400 that calls
 *      `kernel_body` once to warm the I-cache, then loops
 *      INNER_REPS times bracketing each measured call with a snap pair.
 *
 * On hardware the snap pair is two `ldr [DWT_CYCCNT]` reads; on gem5
 * it is `m5_work_begin` / `m5_work_end` BKPT pairs.
 *
 * Section layout inside `.bench_kernel`:
 *
 *   .bench_prologue        ; variable size, untimed setup (e.g. load
 *                          ; DWT_CYCCNT address into r0 on hardware).
 *   (linker FILLs with NOPs to offset 0x70)
 *   .bench_prologue_snap   ; exactly 16 bytes of NOPs — pure filler,
 *                          ; no instrumentation. Kept to satisfy the
 *                          ; linker's 16-byte slot ASSERT and to pin
 *                          ; `_bench_body_start` at offset 0x80.
 *   .bench_body            ; warmup + INNER_REPS measured reps. Starts
 *                          ; at offset 0x80 (= flash 0x08000480).
 *   .bench_epilogue        ; bx lr
 *
 * Register contract for hardware kernels:
 *   - The harness reserves r0 (holds DWT_CYCCNT address) and r4 (holds
 *     start CYCCNT) across each rep's measured call. Kernel bodies
 *     that need these MUST save/restore them. For pure-NOP /
 *     register-free kernels there's no constraint.
 *
 * gem5 kernels have no register contract — every rep reloads r0/r1
 * from scratch around the bkpt.
 *
 * Include this once at the top of a kernel .S file. The file must be
 * compiled with -x assembler-with-cpp so the #ifdef branches work.
 */
#ifndef MICROBENCH_HARNESS_H
#define MICROBENCH_HARNESS_H

#include "m5ops_semi.h"
#include "dwt.h"

#if !defined(PLATFORM_GEM5) && !defined(PLATFORM_HARDWARE)
# error "Define -DPLATFORM_GEM5 or -DPLATFORM_HARDWARE"
#endif

#ifdef __ASSEMBLER__

    .syntax unified
    .cpu cortex-m4
    .fpu fpv4-sp-d16
    .thumb

#ifdef PLATFORM_GEM5
    /*
     * gem5 KERNEL_BEGIN scaffolding — the per-rep m5_work_begin /
     * m5_work_end pairs are emitted inline in .bench_body (by
     * END_BENCH) around each measured call. The START_/END_ROI macros
     * below exist only to fill the prologue / snap-slot / epilogue
     * with no-op padding so the KERNEL_BEGIN-emitted sections satisfy
     * the linker's pinning + 16-byte ASSERT without firing any m5op
     * at the wrong time.
     */
    .macro START_ROI_SETUP
        nop                             @ untimed; keeps .bench_prologue non-empty
    .endm

    /* Exactly 16 bytes of NOPs, no m5op — m5_work_begin lives in
     * .bench_body (emitted by END_BENCH), not here. */
    .macro START_ROI_SNAP
        .balign 2
        .rept 8
        nop
        .endr
    .endm

    .macro END_ROI
        nop                             @ harmless filler in .bench_epilogue
    .endm
#endif /* PLATFORM_GEM5 */

#ifdef PLATFORM_HARDWARE
    /*
     * Hardware KERNEL_BEGIN scaffolding:
     *   SETUP   (.bench_prologue, untimed): load DWT_CYCCNT addr into r0
     *                                       — bench_entry uses r0 for
     *                                       per-rep inner snaps below.
     *   SNAP    (.bench_prologue_snap):     16 bytes of NOPs — pure
     *                                       filler to satisfy the
     *                                       snap-slot linker ASSERT.
     *   END_ROI (.bench_epilogue):          NOP — nothing to close.
     */
    .macro START_ROI_SETUP
        movw  r0, #0x1004               @ DWT_CYCCNT lower 16
        movt  r0, #0xe000               @ DWT_CYCCNT upper 16  → r0 = 0xE0001004
    .endm

    .macro START_ROI_SNAP
        .balign 2
        .rept 8
        nop                             @ 16 bytes of filler — no snap
        .endr
    .endm

    .macro END_ROI
        nop                             @ no outer ROI
    .endm
#endif /* PLATFORM_HARDWARE */

    /*
     * KERNEL_BEGIN <name>:
     *   - place function symbol in .bench_prologue (pinned @ 0x08000400)
     *   - emit START_ROI_SETUP there (early, untimed)
     *   - switch to .bench_prologue_snap and emit START_ROI_SNAP
     *     (16 bytes of NOPs ending at 0x0800047F)
     *   - switch to .bench_body so user code lands at the pinned
     *     0x08000480
     *
     * After KERNEL_BEGIN, the first instruction at 0x08000480 is the
     * start of the warmup + measured-rep loop.
     */
    .macro KERNEL_BEGIN name
        .section .bench_prologue,"ax",%progbits
        .syntax unified
        .thumb
        .balign 4
        .global \name
        .thumb_func
        .type \name, %function
\name :
        START_ROI_SETUP

        .section .bench_prologue_snap,"ax",%progbits
        .syntax unified
        .thumb
        START_ROI_SNAP

        .section .bench_body,"ax",%progbits
        .syntax unified
        .thumb
        .balign 4
    .endm

    /*
     * KERNEL_END: emit END_ROI in .bench_epilogue then return.
     */
    .macro KERNEL_END
        .section .bench_epilogue,"ax",%progbits
        .syntax unified
        .thumb
        .balign 4
        END_ROI
        bx    lr
    .endm

    /*
     * BENCH ... END_BENCH:
     *
     * The user-facing macro pair. Wraps the kernel body and produces:
     *
     *   1. `kernel_body` — the user's instruction sequence,
     *      emitted as a Thumb function in its own .text section (so
     *      it gets its own cache lines).
     *   2. `bench_entry` — pinned at FLASH+0x400; calls
     *      `kernel_body` once cold to populate the I-cache,
     *      then loops INNER_REPS times bracketing each measured call
     *      with a snap pair and storing the cycle delta into the
     *      next slot of `_inner_delta_cyc[]`.
     *
     * In both platforms, the warmup call is NOT instrumented. Only
     * the per-rep measured calls are bracketed.
     *
     * Usage:
     *     BENCH
     *         .rept 100
     *         nop.n
     *         .endr
     *     END_BENCH
     *
     * AAPCS register contract: kernel body is a function callee.
     *   - free to clobber: r0-r3, r12 (caller-saved)
     *   - must preserve:   r4-r11 (callee-saved)
     *   - lr, sp:          managed by the harness; do not touch
     *   - DO NOT emit `bx lr` — END_BENCH does it for you.
     *
     * Body must fit in the target board's I-cache for the warmup to
     * fully prime it on hardware (1 KiB on STM32G474RE; the size
     * comes from board/<board>/board.cmake and the build fails at
     * post-link if the kernel exceeds it, unless
     * -DALLOW_KERNEL_EXCEED_ICACHE=ON).
     *
     * Kernels that want their flash-resident data checked against the
     * board's D-cache size should declare that data in a
     * `.rodata.kernel_data` input section (or `.rodata.kernel_data.*`).
     * The linker brackets that region with __kernel_data_start /
     * __kernel_data_end sentinels; the post-link guard fails the build
     * if `end - start` exceeds DCACHE_SIZE_BYTES unless
     * -DALLOW_KERNEL_EXCEED_DCACHE=ON. Kernels without a
     * `.rodata.kernel_data` section have a zero-byte data footprint.
     */
    .macro BENCH
        .section .text.kernel_body,"ax",%progbits
        .balign 16
        .syntax unified
        .thumb
        .global kernel_body
        .thumb_func
        .type kernel_body, %function
kernel_body:
    .endm

#ifdef PLATFORM_HARDWARE
    /*
     * Hardware END_BENCH — emits bench_entry pinned at .bench_kernel
     * (FLASH+0x400) via KERNEL_BEGIN. Sequence:
     *
     *   1. Single warmup call to kernel_body — populates the
     *      FLITF I-cache. Not in any ROI.
     *   2. INNER_REPS iterations of: snap, bl kernel_body, snap,
     *      store delta into the next slot of _inner_delta_cyc[].
     *
     * Each rep's inner-ROI delta lands in _inner_delta_cyc[i]; main()
     * prints one MICROBENCH line per slot after bench_entry returns.
     */
    .macro END_BENCH
        bx    lr
        .size kernel_body, . - kernel_body

        KERNEL_BEGIN bench_entry
            push  {r3, r4, r5, lr}

            bl    kernel_body        @ WARMUP — populates I-cache

            @ Set up rep loop:
            @   r3 = &_inner_delta_cyc[0]  (post-incremented per rep)
            @   r5 = remaining rep count
            movw  r3, #:lower16:_inner_delta_cyc
            movt  r3, #:upper16:_inner_delta_cyc
            movs  r5, #INNER_REPS

1:                                        @ rep loop start
            ldr   r4, [r0]                @ inner start snap
            bl    kernel_body        @ MEASURED CALL
            ldr   r1, [r0]                @ inner end snap
            subs  r1, r1, r4              @ delta = end - start
            str   r1, [r3], #4            @ _inner_delta_cyc[i++] = delta
            subs  r5, r5, #1
            bne   1b

            pop   {r3, r4, r5, lr}
        KERNEL_END
    .endm
#endif /* PLATFORM_HARDWARE */

#ifdef PLATFORM_GEM5
    /*
     * gem5 END_BENCH — bench_entry pinned at .bench_kernel = FLASH+0x400
     * via KERNEL_BEGIN (same as hardware). Sequence:
     *
     *   1. Single warmup call to kernel_body — no m5op around it.
     *   2. INNER_REPS iterations of: m5_work_begin, bl kernel_body,
     *      m5_work_end. Each rep is its own work region in gem5's stats.
     *
     * Cycles inside each work region:
     *   = bl + body + bx + 3 setup instr before m5_work_end's bkpt
     *   ≈ N + 8 cycles
     */
    .macro END_BENCH
        bx    lr
        .size kernel_body, . - kernel_body

        KERNEL_BEGIN bench_entry
            push  {r5, lr}

            bl    kernel_body        @ WARMUP — no m5op

            movs  r5, #INNER_REPS

1:                                        @ rep loop
            @ m5_work_begin — open work region for this rep
            mov.w r0, #0x100
            movw  r1, #:lower16:m5_pb_begin
            movt  r1, #:upper16:m5_pb_begin
            bkpt  #0xab

            bl    kernel_body        @ MEASURED CALL

            @ m5_work_end — close work region
            mov.w r0, #0x100
            movw  r1, #:lower16:m5_pb_end
            movt  r1, #:upper16:m5_pb_end
            bkpt  #0xab

            subs  r5, r5, #1
            bne   1b

            pop   {r5, lr}
        KERNEL_END
    .endm
#endif /* PLATFORM_GEM5 */

#endif /* __ASSEMBLER__ */

#endif /* MICROBENCH_HARNESS_H */

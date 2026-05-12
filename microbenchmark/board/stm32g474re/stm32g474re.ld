/*
 * Linker script for STM32G474RE low-overhead microbenchmarks.
 *
 * Memory map matches the entobench-generated G474RE.ld that the parent
 * tree's build-stm32 / build-gem5 directories use: 512 KB flash,
 * 128 KB RAM, stack at top of RAM. Section list and DISCARDs also
 * mirror entobench so binaries built here are placed the same way as
 * the existing entobench builds, modulo three pinned sections at the
 * front of flash.
 *
 * Pinned regions (all addresses stable across gem5 + hardware variants):
 *
 *   0x08000000  .isr_vector              (64 B; Cortex-M vector table)
 *   0x08000400  .bench_kernel            (≤ 0xc00 B; bench_entry wrapper,
 *                                          .bench_prologue + 16-byte snap
 *                                          slot + .bench_body + .bench_epilogue)
 *   0x08001000  .text.kernel_body        (1 KiB reserved = ICACHE_SIZE_BYTES;
 *                                          the user's kernel)
 *   0x08001400  .rodata.kernel_data      (256 B reserved = DCACHE_SIZE_BYTES;
 *                                          flash-resident data the kernel
 *                                          opts into via .rodata.kernel_data*)
 *   0x08001500  .text                    (everything else: Reset_Handler,
 *                                          main, system_init, …)
 *
 * The point of the pins: kernel_body and kernel_data live at the same
 * flash addresses in every build (gem5 + all 4 hardware variants), so
 * I/D-cache set indices and branch-target alignment are identical.
 * Without that, harness/main changes that grow .text would shift the
 * kernel and invalidate cross-build cache-effect comparisons.
 *
 * The reserved slot sizes (1 KiB / 256 B) match the board's I-cache
 * and D-cache so the post-link kernel-size checks
 * (scripts/check_kernel_size.py) and the linker ASSERTs both fail the
 * build at the same boundary.
 */

ENTRY(Reset_Handler)

_estack = 0x20000000 + 128K;
_Min_Heap_Size = 0x200;
_Min_Stack_Size = 0x400;

/* Pin offsets and slot sizes — see top-of-file comment. */
_bench_kernel_pin = ORIGIN(FLASH) + 0x400;
_kernel_body_pin  = ORIGIN(FLASH) + 0x1000;
_kernel_data_pin  = ORIGIN(FLASH) + 0x1400;
_kernel_body_max  = 0x400;   /* = ICACHE_SIZE_BYTES on stm32g474re */
_kernel_data_max  = 0x100;   /* = DCACHE_SIZE_BYTES on stm32g474re */

MEMORY
{
    FLASH (rx)      : ORIGIN = 0x8000000, LENGTH = 512K
    RAM (xrw)      : ORIGIN = 0x20000000, LENGTH = 128K
}

SECTIONS
{
    .isr_vector :
    {
        . = ALIGN(4);
        KEEP(*(.isr_vector))
        . = ALIGN(4);
    } > FLASH

    /*
     * .bench_kernel — the bench_entry wrapper, pinned at FLASH + 0x400.
     *
     * Layout inside the 128-byte prologue + body region:
     *
     *   0x08000400  ┐ .bench_prologue       — untimed setup: load
     *               │                          DWT_CYCCNT addr into r0
     *               │   Fill: Thumb NOPs   (padding to the 16-byte slot)
     *   0x08000470  ┤
     *               │ .bench_prologue_snap — exactly 16 bytes of NOPs.
     *               │                          Historical: this slot used
     *               │                          to hold the start-snap
     *               │                          instruction. The current
     *               │                          harness puts per-rep snaps
     *               │                          inside .bench_body, so this
     *               │                          slot is pure filler kept
     *               │                          only to pin _bench_body_start
     *               │                          at offset 0x80.
     *   0x08000480  ┴── _bench_body_start  (pinned, byte-identical across
     *               │                          all 4 hardware variants)
     *               │ .bench_body          — warmup + INNER_REPS measured
     *               │                          reps. Each rep emits its
     *               │                          own snap pair around the
     *               │                          measured `bl kernel_body`.
     *
     * ld stores FILL in big-endian, so 0x00BF00BF on disk becomes
     * bytes 00 BF 00 BF → halfword 0xBF00 in little-endian → Thumb NOP.
     *
     * The section must end before _kernel_body_pin (0x08001000); the
     * ASSERT at the end of this block catches overflow at link time.
     */
    .bench_kernel _bench_kernel_pin :
    {
        _bench_kernel_start = .;
        FILL(0x00bf00bf)
        KEEP(*(.bench_prologue))
        . = _bench_kernel_start + 0x80 - 0x10;   /* reserve 16-byte snap slot */
        _bench_snap_start = .;
        KEEP(*(.bench_prologue_snap))
        ASSERT(. == _bench_kernel_start + 0x80,
            "ERROR: .bench_prologue_snap must be exactly 16 bytes");
        _bench_body_start = .;
        KEEP(*(.bench_body))
        _bench_body_end = .;
        . = ALIGN(4);
        KEEP(*(.bench_epilogue))
        . = ALIGN(4);
        _bench_kernel_end = .;
        ASSERT(_bench_kernel_end <= _kernel_body_pin,
            "ERROR: .bench_kernel grew past the kernel_body pin (0x08001000)");
    } > FLASH

    /*
     * .text.kernel_body — pinned at FLASH + 0x1000 with a slot size of
     * _kernel_body_max (= ICACHE_SIZE_BYTES on this board). The BENCH
     * macro emits the kernel as an input section also named
     * .text.kernel_body, which the KEEP() below claims so the generic
     * .text wildcard further down can't double-match it.
     *
     * `kernel_body` lands at FLASH+0x1000 in every build (gem5 + all 4
     * hardware variants) because the section is .balign 16 and the pin
     * is 16-aligned. Same bytes, same address, same cache-line offset.
     */
    .text.kernel_body _kernel_body_pin :
    {
        . = ALIGN(16);
        KEEP(*(.text.kernel_body))
        . = ALIGN(4);
        ASSERT(. <= _kernel_body_pin + _kernel_body_max,
            "ERROR: kernel_body exceeded its reserved 1 KiB slot — set -DALLOW_KERNEL_EXCEED_ICACHE=ON or shrink the kernel");
    } > FLASH

    /*
     * .rodata.kernel_data — pinned at FLASH + 0x1400 with a slot size
     * of _kernel_data_max (= DCACHE_SIZE_BYTES on this board). A kernel
     * opts into the D-cache size check by emitting flash-resident data
     * into a `.rodata.kernel_data` (or `.rodata.kernel_data.*`) input
     * section; the sentinels __kernel_data_start / __kernel_data_end
     * bracket the actually-used bytes. Kernels without an opt-in
     * declaration get a zero-byte data footprint (the sentinels
     * collapse to the same address).
     */
    .rodata.kernel_data _kernel_data_pin :
    {
        __kernel_data_start = .;
        KEEP(*(.rodata.kernel_data .rodata.kernel_data.*))
        __kernel_data_end = .;
        . = ALIGN(4);
        ASSERT(. <= _kernel_data_pin + _kernel_data_max,
            "ERROR: kernel_data exceeded its reserved 256 B slot — set -DALLOW_KERNEL_EXCEED_DCACHE=ON or shrink it");
    } > FLASH

    .text :
    {
        . = ALIGN(4);
        *(.text)
        *(.text*)
        *(.glue_7)
        *(.glue_7t)
        *(.eh_frame)

        KEEP (*(.init))
        KEEP (*(.fini))

        . = ALIGN(4);
        _etext = .;
    } > FLASH

    .rodata :
    {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);
    } > FLASH

    .ARM.extab : { *(.ARM.extab* .gnu.linkonce.armextab.*) } > FLASH
    .ARM :
    {
        __exidx_start = .;
        *(.ARM.exidx*)
        __exidx_end = .;
    } > FLASH

    .preinit_array :
    {
        PROVIDE_HIDDEN (__preinit_array_start = .);
        KEEP (*(.preinit_array*))
        PROVIDE_HIDDEN (__preinit_array_end = .);
    } > FLASH

    .init_array :
    {
        PROVIDE_HIDDEN (__init_array_start = .);
        KEEP (*(SORT(.init_array.*)))
        KEEP (*(.init_array*))
        PROVIDE_HIDDEN (__init_array_end = .);
    } > FLASH

    .fini_array :
    {
        PROVIDE_HIDDEN (__fini_array_start = .);
        KEEP (*(SORT(.fini_array.*)))
        KEEP (*(.fini_array*))
        PROVIDE_HIDDEN (__fini_array_end = .);
    } > FLASH

    _sidata = LOADADDR(.data);

    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data)
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT> FLASH

    . = ALIGN(4);
    .bss :
    {
        _sbss = .;
        __bss_start__ = _sbss;
        *(.bss)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
        __bss_end__ = _ebss;
    } > RAM

    ._user_heap_stack :
    {
        . = ALIGN(8);
        PROVIDE ( end = . );
        PROVIDE ( _end = . );
        . = . + _Min_Heap_Size;
        . = . + _Min_Stack_Size;
        . = ALIGN(8);
    } > RAM

    /DISCARD/ :
    {
        libc.a ( * )
        libm.a ( * )
        libgcc.a ( * )
    }

    .ARM.attributes 0 : { *(.ARM.attributes) }
}

/*
 * Linker script for STM32G474RE low-overhead microbenchmarks.
 *
 * Memory map matches the entobench-generated G474RE.ld that the parent
 * tree's build-stm32 / build-gem5 directories use: 512 KB flash,
 * 128 KB RAM, stack at top of RAM. Section list and DISCARDs also
 * mirror entobench so binaries built here are placed the same way as
 * the existing entobench builds, modulo the .bench_kernel pin.
 *
 * The one addition vs. entobench is the .bench_kernel section, pinned
 * at FLASH + 0x400, which keeps the kernel BODY bytes
 * (_bench_body_start) at a fixed address (0x08000480) across every
 * build variant. Without that pin, any change to harness / main / etc.
 * would shift the kernel and invalidate cache / branch-predictor /
 * alignment comparisons between gem5 and the board.
 */

ENTRY(Reset_Handler)

_estack = 0x20000000 + 128K;
_Min_Heap_Size = 0x200;
_Min_Stack_Size = 0x400;

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
     * Kernel layout inside the 128-byte prologue + body region:
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
     * .rodata defines linker sentinels __kernel_data_start /
     * __kernel_data_end that bracket any `.rodata.kernel_data*` input
     * sections; the post-link D-cache check measures `end - start`.
     */
    .bench_kernel ORIGIN(FLASH) + 0x400 :
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
        /*
         * Kernel-declared flash-resident data, bracketed by sentinel
         * symbols so the post-link D-cache size check can measure
         * how many bytes of flash data the kernel touches. A kernel
         * opts in by putting its data in a `.rodata.kernel_data`
         * input section (and any number of `.rodata.kernel_data.*`
         * sub-sections). Kernels without an opt-in declaration get
         * a zero-byte data footprint (the symbols collapse to the
         * same address).
         */
        __kernel_data_start = .;
        *(.rodata.kernel_data .rodata.kernel_data.*)
        __kernel_data_end = .;
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

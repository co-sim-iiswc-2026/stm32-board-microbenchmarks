/*
 * Linker script for STM32G474RE microbenchmarks on gem5.
 *
 * Memory map matches STM32G474RE (RM0440):
 *   Flash Bank 1: 256KB @ 0x08000000
 *   Flash Bank 2: 256KB @ 0x08040000
 *   SRAM1:         80KB @ 0x20000000
 *   SRAM2:         16KB @ 0x20014000
 *   CCM SRAM:      32KB @ 0x10000000
 */

ENTRY(Reset_Handler)

_estack = 0x20014000;  /* Top of SRAM1 (80KB from 0x20000000) */

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 256K
    SRAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 80K
}

SECTIONS
{
    .isr_vector :
    {
        . = ALIGN(4);
        KEEP(*(.isr_vector))
        . = ALIGN(4);
    } > FLASH

    .text :
    {
        . = ALIGN(4);
        *(.text)
        *(.text*)
        . = ALIGN(4);
    } > FLASH

    .rodata :
    {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);
    } > FLASH

    .data :
    {
        . = ALIGN(4);
        *(.data)
        *(.data*)
        . = ALIGN(4);
    } > SRAM AT> FLASH

    .bss :
    {
        . = ALIGN(4);
        *(.bss)
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
    } > SRAM
}

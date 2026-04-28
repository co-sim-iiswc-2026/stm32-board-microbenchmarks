@ HAND-WRITTEN — see kernel_wfi_100us.note for codegen-side stub.
@
@ Single WFI archetype. SysTick is already armed by the harness's setup()
@ (SysTick_Setup() in entobench, 1 ms tick — see ento-mcu/systick_config.c).
@ The active SysTick interrupt wakes the core within ~1 ms; for "exactly
@ 100 µs" we'd need a custom timer pre-armed with reload=170*100. v1 ships
@ with the existing 1 ms tick — slot is named wfi_100us as a placeholder
@ but the actual wake is whatever SysTick fires first. Note this in the
@ paper if the floor power matters at sub-1ms granularity.
@
@ Critical: the SysTick handler must be enabled and global IRQs unmasked
@ before this kernel runs. The MultiHarness setup() does both via the
@ SysTick_Setup() + __enable_irq() calls in main(). If those are skipped
@ the WFI sleeps forever and the binary hangs.

.syntax unified
.cpu cortex-m4
.fpu fpv4-sp-d16
.thumb

.section .text.kernel_wfi_100us, "ax", %progbits
.balign 16
.global  kernel_wfi_100us
.type    kernel_wfi_100us, %function
.thumb_func
kernel_wfi_100us:
    @ DSB before WFI ensures all pending memory/peripheral writes commit
    @ (matches Cortex-M4 architectural recommendation, ARM DDI 0439B B1.5).
    dsb 0xF
    wfi
    @ ISB on wake to flush any speculatively prefetched instructions during
    @ sleep — keeps the post-ROI cycle count clean.
    isb 0xF
    bx lr
.size kernel_wfi_100us, .-kernel_wfi_100us

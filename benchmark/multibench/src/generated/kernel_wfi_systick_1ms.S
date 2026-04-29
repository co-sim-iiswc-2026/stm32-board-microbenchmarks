@ HAND-WRITTEN — see kernel_wfi_systick_1ms.note for codegen-side stub.
@
@ Single WFI archetype. SysTick is already armed by the harness's setup()
@ (SysTick_Setup() in entobench, 1 ms tick — see ento-mcu/systick_config.c).
@ The active SysTick interrupt wakes the core within ~1 ms; the slot is
@ named accordingly.
@
@ A true 100 us wake would need a custom timer pre-armed at 170*100 cycles
@ (or temporary SysTick LOAD reload around the WFI). Deferred to v2 — for
@ v1, the energy analyzer extracts T from the latency_pin pulse width, so
@ P_floor = energy / T_measured works regardless of nominal wake time.
@
@ Critical: the SysTick handler must be enabled and global IRQs unmasked
@ before this kernel runs. The MultiHarness setup() does both via the
@ SysTick_Setup() + __enable_irq() calls in main(). If those are skipped
@ the WFI sleeps forever and the binary hangs.

.syntax unified
.cpu cortex-m4
.fpu fpv4-sp-d16
.thumb

.section .text.kernel_wfi_systick_1ms, "ax", %progbits
.balign 16
.global  kernel_wfi_systick_1ms
.type    kernel_wfi_systick_1ms, %function
.thumb_func
kernel_wfi_systick_1ms:
    @ DSB before WFI ensures all pending memory/peripheral writes commit
    @ (matches Cortex-M4 architectural recommendation, ARM DDI 0439B B1.5).
    dsb sy
    wfi
    @ ISB on wake to flush any speculatively prefetched instructions during
    @ sleep — keeps the post-ROI cycle count clean.
    isb sy
    bx lr
.size kernel_wfi_systick_1ms, .-kernel_wfi_systick_1ms

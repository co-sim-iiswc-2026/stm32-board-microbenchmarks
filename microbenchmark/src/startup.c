/*
 * Minimal startup for STM32G474RE — vector table, Reset_Handler, .data
 * copy from flash, .bss zero, IRQ unmask, then jump to main().
 *
 * Only the core Cortex-M exceptions are populated. No NVIC peripheral
 * vectors are wired up by the harness itself, but Reset_Handler
 * explicitly unmasks IRQs (cpsie i) before calling main() so that any
 * kernel or future feature enabling a specific NVIC source via
 * NVIC->ISER will actually take interrupts. The 0x08000000 vector
 * table is exactly 64 bytes (16 entries × 4 bytes) so .bench_kernel
 * can be pinned at 0x08000400 with plenty of slack.
 *
 * Why C and not assembly: nothing in startup needs anything the
 * compiler can't generate. Keeping it in C means there's one less
 * dialect to maintain. The two memory loops are written as plain C
 * pointer walks; -fno-builtin (set in CMakeLists.txt's COMMON_FLAGS)
 * prevents the compiler from rewriting them into libc memcpy/memset
 * calls that the -nostdlib link wouldn't resolve.
 */
#include <stdint.h>

extern uint32_t _estack;
extern uint32_t _sdata, _edata, _sidata;
extern uint32_t _sbss, _ebss;

extern int main(void);

void Reset_Handler(void);
void Default_Handler(void);
void NMI_Handler(void);
void HardFault_Handler(void);
void MemManage_Handler(void);
void BusFault_Handler(void);
void UsageFault_Handler(void);

/*
 * The Cortex-M vector table. Slot 0 is the initial stack pointer
 * (taken by the CPU at reset, NOT executed); the remaining slots are
 * function pointers. `used` keeps it through LTO and dead-code
 * elimination; the linker script anchors it at FLASH 0x08000000.
 */
__attribute__((section(".isr_vector"), used))
void (* const _isr_vector[16])(void) = {
    (void (*)(void))(uintptr_t)&_estack,   /*  0: Initial SP        */
    Reset_Handler,                         /*  1: Reset             */
    NMI_Handler,                           /*  2: NMI               */
    HardFault_Handler,                     /*  3: HardFault         */
    MemManage_Handler,                     /*  4: MemManage         */
    BusFault_Handler,                      /*  5: BusFault          */
    UsageFault_Handler,                    /*  6: UsageFault        */
    0, 0, 0, 0,                            /*  7-10: Reserved       */
    Default_Handler,                       /* 11: SVCall            */
    Default_Handler,                       /* 12: DebugMon          */
    0,                                     /* 13: Reserved          */
    Default_Handler,                       /* 14: PendSV            */
    Default_Handler,                       /* 15: SysTick           */
};

__attribute__((section(".text.Reset_Handler"), used, noreturn))
void Reset_Handler(void)
{
    /*
     * The Cortex-M auto-loads SP from [0x08000000] at reset, so this
     * is normally redundant. Keep it as a belt-and-suspenders measure
     * for re-entry from a stuck-handler scenario where SP could be
     * scrambled.
     */
    __asm__ volatile ("ldr sp, =_estack");

    /* Copy initialised .data from flash to SRAM. */
    uint32_t *dst = &_sdata;
    uint32_t *src = &_sidata;
    while (dst < &_edata) {
        *dst++ = *src++;
    }

    /* Zero-fill .bss. */
    dst = &_sbss;
    while (dst < &_ebss) {
        *dst++ = 0;
    }

    /*
     * Unmask IRQs at the CPU level. PRIMASK is already 0 at reset on
     * Cortex-M, so this is a no-op on the normal boot path — but it
     * guarantees we land in main() with interrupts unmasked even on
     * re-entry from a stuck-handler state where PRIMASK might be set.
     * Individual NVIC sources still need NVIC->ISER to fire; this only
     * gates whether the CPU accepts any IRQ at all.
     */
    __asm__ volatile ("cpsie i" ::: "memory");

    main();

    /*
     * main() should never return. If it does, spin here. We avoid BKPT
     * because a BKPT in a state where DEBUGEN isn't set escalates to a
     * fault — and if this site is reached from inside a fault handler
     * (e.g. HardFault chain) that compounds to LOCKUP, which makes the
     * chip very hard to recover via SWD.
     */
    for (;;) ;
}

/*
 * Fault handlers: each is its own labelled infinite loop so the PC
 * reported by `openocd halt` distinguishes which fault fired. We avoid
 * BKPT for the same LOCKUP reason as above. `noinline` keeps each
 * function at a distinct address — without it, identical-bodied
 * functions can be merged by `-fipa-icf` at higher optimisation levels.
 */
__attribute__((noinline, noreturn))
static void spin(void) { for (;;) ; }

__attribute__((noinline)) void Default_Handler(void)    { spin(); }
__attribute__((noinline)) void NMI_Handler(void)        { spin(); }
__attribute__((noinline)) void HardFault_Handler(void)  { spin(); }
__attribute__((noinline)) void MemManage_Handler(void)  { spin(); }
__attribute__((noinline)) void BusFault_Handler(void)   { spin(); }
__attribute__((noinline)) void UsageFault_Handler(void) { spin(); }

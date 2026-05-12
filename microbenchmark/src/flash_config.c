/*
 * FLASH->ACR setup per hardware variant.
 *
 * Bit layout (RM0440 §3.7.1):
 *   [3:0]  LATENCY (wait states)
 *   [8]    PRFTEN  prefetch enable
 *   [9]    ICEN    instruction cache enable
 *   [10]   DCEN    data cache enable
 *
 * For gem5 builds we skip the write entirely — the simulator doesn't model
 * FLASH ACR and writes to that MMIO address are harmless but pointless.
 */
#include <stdint.h>

#ifndef ENABLE_ICACHE
# define ENABLE_ICACHE   1
#endif
#ifndef ENABLE_DCACHE
# define ENABLE_DCACHE   1
#endif
#ifndef ENABLE_PREFETCH
# define ENABLE_PREFETCH 1
#endif

#define FLASH_ACR (*(volatile uint32_t *)0x40022000u)

void apply_flash_acr(void)
{
#ifdef PLATFORM_HARDWARE
    /* system_init() has already set LATENCY=4 for the 170 MHz PLL path.
     * Here we only modify the cache + prefetch bits per variant —
     * preserve LATENCY and any other bits. */
    uint32_t acr = FLASH_ACR & ~((1u << 8) | (1u << 9) | (1u << 10));
# if ENABLE_PREFETCH
    acr |= (1u << 8);
# endif
# if ENABLE_ICACHE
    acr |= (1u << 9);
# endif
# if ENABLE_DCACHE
    acr |= (1u << 10);
# endif
    FLASH_ACR = acr;
    __asm__ volatile("dsb" ::: "memory");
    __asm__ volatile("isb" ::: "memory");
#endif
}

/*
 * Clock + FPU init, modelled on entobench's `sys_clk_cfg()`
 * (external/ento-bench/src/ento-mcu/clk_util.c lines 101–152) which is
 * known to work on this exact STM32G474RE board.
 *
 * Sequence for 170 MHz:
 *   1. enable SYSCFG + PWR peripheral clocks
 *   2. set FLASH LATENCY = 4 and *poll* until the flash controller
 *      adopts it (read-back is required — DSB/ISB alone is not enough)
 *   3. enable Range 1 Boost mode (PWR_CR5.R1MODE = 0)
 *   4. ensure HSI16 is on (default at reset, but be explicit)
 *   5. configure PLL: HSI16 / 4 * 85 / 2 = 170 MHz
 *   6. enable PLL, wait PLLRDY
 *   7. switch SYSCLK to PLL with AHB prescaler = /2 (intermediate boost
 *      transition step required by RM0440 when crossing 80 MHz)
 *   8. wait at least 1 µs at the intermediate speed (using DWT)
 *   9. set AHB prescaler back to /1, APB1/APB2 = /1
 *
 * Then enable FPU CP10/CP11.
 *
 * For gem5 builds (PLATFORM_HARDWARE not defined), this is a no-op
 * except for the FPU enable — gem5 doesn't model RCC/PWR/FLASH.
 */
#include <stdint.h>

#define SCB_CPACR_ADDR  0xE000ED88u
#define SCB_CPACR       (*(volatile uint32_t *)SCB_CPACR_ADDR)

#ifdef PLATFORM_HARDWARE

#define RCC_BASE        0x40021000u
#define RCC_CR          (*(volatile uint32_t *)(RCC_BASE + 0x00))
#define RCC_ICSCR       (*(volatile uint32_t *)(RCC_BASE + 0x04))
#define RCC_CFGR        (*(volatile uint32_t *)(RCC_BASE + 0x08))
#define RCC_PLLCFGR     (*(volatile uint32_t *)(RCC_BASE + 0x0C))
#define RCC_APB1ENR1    (*(volatile uint32_t *)(RCC_BASE + 0x58))
#define RCC_APB2ENR     (*(volatile uint32_t *)(RCC_BASE + 0x60))

#define PWR_BASE        0x40007000u
#define PWR_CR5         (*(volatile uint32_t *)(PWR_BASE + 0x80))

#define FLASH_BASE      0x40022000u
#define FLASH_ACR       (*(volatile uint32_t *)(FLASH_BASE + 0x00))

#define DEMCR_ADDR_     0xE000EDFCu
#define DEMCR           (*(volatile uint32_t *)DEMCR_ADDR_)
#define DWT_CTRL_ADDR_  0xE0001000u
#define DWT_CTRL        (*(volatile uint32_t *)DWT_CTRL_ADDR_)
#define DWT_CYCCNT_ADDR_ 0xE0001004u
#define DWT_CYCCNT      (*(volatile uint32_t *)DWT_CYCCNT_ADDR_)

#endif /* PLATFORM_HARDWARE */

void system_init(void)
{
#ifdef PLATFORM_HARDWARE
    /* 1. Enable SYSCFG (APB2 bit 0) and PWR (APB1ENR1 bit 28) clocks. */
    RCC_APB2ENR  |= (1u << 0);
    (void)RCC_APB2ENR;                       /* HAL-style read-back delay */
    RCC_APB1ENR1 |= (1u << 28);
    (void)RCC_APB1ENR1;

    /* 2. FLASH LATENCY = 4 (170 MHz requires 4 wait states). Poll until
     *    the controller adopts the new value. */
    {
        uint32_t acr = FLASH_ACR;
        acr &= ~0xFu;
        acr |= 4u;
        FLASH_ACR = acr;
        while ((FLASH_ACR & 0xFu) != 4u)
            ;
    }

    /* 3. Range 1 Boost mode: clear PWR_CR5.R1MODE (bit 0). */
    PWR_CR5 &= ~(1u << 0);

    /* 4. HSI16 on (default at reset), wait HSIRDY (bit 10). */
    RCC_CR |= (1u << 8);                     /* HSION */
    while (!(RCC_CR & (1u << 10)))
        ;

    /* HSI calibration trimming = 64 (entobench style). RCC_ICSCR HSITRIM = bits [30:24]. */
    RCC_ICSCR = (RCC_ICSCR & ~(0x7Fu << 24)) | (64u << 24);

    /* 5. PLLCFGR: PLLSRC=HSI16(10), PLLM=4 (field=M-1=3), PLLN=85, PLLR=00 (/2), PLLREN=1. */
    RCC_PLLCFGR = (2u << 0)
                | ((4u - 1u) << 4)
                | (85u << 8)
                | (0u << 25)
                | (1u << 24);

    /* 6. PLL on, wait PLLRDY (RCC_CR bit 25). */
    RCC_CR |= (1u << 24);
    while (!(RCC_CR & (1u << 25)))
        ;

    /* 7. Switch SYSCLK to PLL (CFGR.SW=11) with AHB prescaler = /2 (HPRE=1000). */
    {
        uint32_t cfgr = RCC_CFGR;
        cfgr &= ~(0xFu << 4);                /* clear HPRE[3:0] = CFGR[7:4] */
        cfgr |= (0x8u << 4);                 /* HPRE = 1000 = /2 */
        cfgr &= ~0x3u;
        cfgr |= 0x3u;                        /* SW = 11 = PLL */
        RCC_CFGR = cfgr;
        /* Wait SWS = PLL (CFGR[3:2] = 11). */
        while (((RCC_CFGR >> 2) & 0x3u) != 0x3u)
            ;
    }

    /* 8. Hold at intermediate speed for >1 µs using DWT CYCCNT. At 170/2=85 MHz,
     *    100 cycles ≈ 1.18 µs. */
    DEMCR    |= (1u << 24);                  /* TRCENA */
    DWT_CYCCNT = 0;
    DWT_CTRL |= 0x1u;                        /* CYCCNTENA */
    while (DWT_CYCCNT < 100u)
        ;

    /* 9. AHB prescaler back to /1, APB1/APB2 = /1. */
    {
        uint32_t cfgr = RCC_CFGR;
        cfgr &= ~(0xFu << 4);                /* HPRE = 0xxx = /1 */
        cfgr &= ~(0x7u << 8);                /* PPRE1 = 0xx = /1 */
        cfgr &= ~(0x7u << 11);               /* PPRE2 = 0xx = /1 */
        RCC_CFGR = cfgr;
    }
#endif /* PLATFORM_HARDWARE */

    /* FPU CP10/CP11 full access — needed for -mfloat-abi=hard binaries. */
    SCB_CPACR |= (0xFu << 20);
    __asm__ volatile("dsb" ::: "memory");
    __asm__ volatile("isb" ::: "memory");
}

/*
 * DWT (Data Watchpoint and Trace) CYCCNT helpers for Cortex-M4.
 *
 * Register addresses (ARMv7-M ARM, B3.4):
 *   DEMCR     0xE000EDFC   bit24 TRCENA = master enable for DWT
 *   DWT_CTRL  0xE0001000   bit0  CYCCNTENA
 *   DWT_CYCCNT 0xE0001004
 */
#ifndef MICROBENCH_DWT_H
#define MICROBENCH_DWT_H

#define DEMCR_ADDR       0xE000EDFC
#define DEMCR_TRCENA_MSK (1u << 24)

#define DWT_CTRL_ADDR    0xE0001000
#define DWT_CYCCNT_ADDR  0xE0001004
#define DWT_CTRL_CYCCNTENA_MSK 0x1

#ifndef __ASSEMBLER__

#include <stdint.h>

#define DEMCR     (*(volatile uint32_t *)DEMCR_ADDR)
#define DWT_CTRL  (*(volatile uint32_t *)DWT_CTRL_ADDR)
#define DWT_CYCCNT (*(volatile uint32_t *)DWT_CYCCNT_ADDR)

static inline void dwt_enable(void)
{
    DEMCR    |= DEMCR_TRCENA_MSK;
    DWT_CYCCNT = 0;
    DWT_CTRL  |= DWT_CTRL_CYCCNTENA_MSK;
}

static inline void dwt_disable(void)
{
    DWT_CTRL &= ~DWT_CTRL_CYCCNTENA_MSK;
}

static inline uint32_t dwt_read(void)
{
    return DWT_CYCCNT;
}

#endif /* !__ASSEMBLER__ */

#endif /* MICROBENCH_DWT_H */

/*
 * gem5 pseudo-ops via M-profile semihosting (BKPT #0xab).
 *
 * Calling convention (gem5 ArmSemihosting):
 *   R0 = 0x100 (SYS_GEM5_PSEUDO_OP)
 *   R1 = &param_block
 *   param_block[0] = func_code << 8   (decodeAddrOffset reads bits[15:8])
 *   param_block[1] = arg0
 *   param_block[2] = arg1
 *
 * Op codes (from gem5 include/gem5/asm/generic/m5ops.h):
 */
#ifndef MICROBENCH_M5OPS_SEMI_H
#define MICROBENCH_M5OPS_SEMI_H

#define SYS_GEM5_PSEUDO_OP      0x100

#define M5OP_EXIT               0x21
#define M5OP_RESET_STATS        0x40
#define M5OP_DUMP_STATS         0x41
#define M5OP_DUMP_RESET_STATS   0x42
#define M5OP_WORK_BEGIN         0x5a
#define M5OP_WORK_END           0x5b

#ifndef __ASSEMBLER__

#include <stdint.h>

__attribute__((noinline))
static uint32_t m5_semi_call(uint8_t func, uint32_t arg0, uint32_t arg1)
{
    static volatile uint32_t param_block[3];
    param_block[0] = (uint32_t)func << 8;
    param_block[1] = arg0;
    param_block[2] = arg1;

    register uint32_t r0 __asm__("r0") = SYS_GEM5_PSEUDO_OP;
    register uint32_t r1 __asm__("r1") = (uint32_t)&param_block[0];

    __asm__ volatile(
        "bkpt #0xab"
        : "+r"(r0)
        : "r"(r1)
        : "memory"
    );
    return r0;
}

static inline void m5_reset_stats(void)      { m5_semi_call(M5OP_RESET_STATS, 0, 0); }
static inline void m5_dump_reset_stats(void) { m5_semi_call(M5OP_DUMP_RESET_STATS, 0, 0); }
static inline void m5_work_begin(void)       { m5_semi_call(M5OP_WORK_BEGIN, 0, 0); }
static inline void m5_work_end(void)         { m5_semi_call(M5OP_WORK_END, 0, 0); }
static inline void m5_exit(uint32_t code)    { m5_semi_call(M5OP_EXIT, code, 0); }

#endif /* !__ASSEMBLER__ */

#endif /* MICROBENCH_M5OPS_SEMI_H */

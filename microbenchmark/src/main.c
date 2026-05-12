/*
 * Microbenchmark harness entry point.
 *
 * Flow:
 *   1. system_init()      — FPU + (hardware only) PLL170 clock
 *   2. apply_flash_acr()  — cache/prefetch bits per hardware variant
 *   3. dwt_enable()       — hardware only; one-time DEMCR/DWT setup
 *   4. bench_entry()      — runs one warmup + INNER_REPS measured reps
 *   5. semihosting print  — one MICROBENCH line per rep (hardware) or
 *                            just the marker (gem5; cycles via m5out)
 *   6. semi_exit          — m5_exit (gem5) then SYS_EXIT (hardware)
 *
 * On gem5, cycles for each rep are read from m5out/stats.txt — every
 * rep emits its own m5_work_begin / m5_work_end pair (one stats window
 * per rep). On hardware, each rep's DWT->CYCCNT delta is stored into
 * _inner_delta_cyc[i] inside the harness loop, and main() prints one
 * "MICROBENCH name=... rep=<i> inner=<N>" line per rep via ARM
 * semihosting SYS_WRITE0 (OpenOCD relays to the log).
 */
#include <stdint.h>

#include "m5ops_semi.h"
#include "dwt.h"

extern void bench_entry(void);
extern void system_init(void);
extern void apply_flash_acr(void);

/*
 * gem5 param blocks — pre-initialized in .data, copied to SRAM by startup.
 * Referenced by the m5_work_begin / m5_work_end bkpts emitted inline by
 * the BENCH macro in harness.h.
 */
volatile uint32_t m5_pb_begin[3] = { (uint32_t)M5OP_WORK_BEGIN << 8, 0, 0 };
volatile uint32_t m5_pb_end[3]   = { (uint32_t)M5OP_WORK_END   << 8, 0, 0 };

/* Per-rep inner-ROI scratch (hardware only — gem5 reads cycles from stats).
 * END_BENCH's loop writes one cycle delta per measured rep into
 * successive slots; main() then prints one MICROBENCH line per slot. */
#ifndef INNER_REPS
# error "INNER_REPS must be defined (set via CMake add_compile_definitions)"
#endif
volatile uint32_t _inner_delta_cyc[INNER_REPS];

#ifndef BENCH_NAME
#define BENCH_NAME "unknown"
#endif

static void semi_write0(const char *s)
{
    register uint32_t r0 __asm__("r0") = 0x04;       /* SYS_WRITE0 */
    register const char *r1 __asm__("r1") = s;
    __asm__ volatile("bkpt #0xab" :: "r"(r0), "r"(r1) : "memory");
}

/*
 * Build one per-rep cycle-report line in a single buffer and emit it
 * via ONE SYS_WRITE0 call, so OpenOCD's interleaved info messages can't
 * split "MICROBENCH name=... rep=<i> inner=N\n" across multiple log
 * lines.
 *
 * Only the STM32 build calls this; mark unused so the gem5 build
 * doesn't trip -Wunused-function.
 */
static char report_buf[96];

static char *put_str(char *p, const char *s) { while (*s) *p++ = *s++; return p; }

static char *put_u32(char *p, uint32_t v)
{
    char tmp[12];
    int n = 0;
    if (v == 0) {
        tmp[n++] = '0';
    } else {
        while (v) { tmp[n++] = (char)('0' + v % 10); v /= 10; }
    }
    while (n--) *p++ = tmp[n];
    return p;
}

__attribute__((unused))
static void emit_report(const char *name, uint32_t rep, uint32_t inner)
{
    char *p = report_buf;
    p = put_str(p, "MICROBENCH name=");
    p = put_str(p, name);
    p = put_str(p, " rep=");
    p = put_u32(p, rep);
    p = put_str(p, " inner=");
    p = put_u32(p, inner);
    *p++ = '\n';
    *p   = '\0';
    semi_write0(report_buf);
}

static __attribute__((noreturn)) void semi_exit(uint32_t code)
{
#ifdef PLATFORM_GEM5
    m5_exit(code);
#endif
    register uint32_t r0 __asm__("r0") = 0x18;       /* SYS_EXIT */
    register uint32_t r1 __asm__("r1") = 0x20026;    /* ADP_Stopped_ApplicationExit */
    (void)code;
    __asm__ volatile("bkpt #0xab" :: "r"(r0), "r"(r1) : "memory");
    /* Plain spin if SYS_EXIT didn't halt — no BKPT (which would emit
     * "unsupported call 0" noise via the semihosting handler). */
    for (;;) ;
}

int main(void)
{
    /*
     * Order matters:
     *   system_init() handles FLASH LATENCY + PLL + sysclk switch (it
     *     sets LATENCY=4 BEFORE raising the clock to 170 MHz, mirroring
     *     entobench's sys_clk_cfg).
     *   apply_flash_acr() then OVERLAYS the per-variant cache/prefetch
     *     bits, preserving LATENCY.
     */
    system_init();
    apply_flash_acr();

#ifdef PLATFORM_HARDWARE
    /* One-time DWT enable, outside the ROI. */
    *(volatile uint32_t *)DEMCR_ADDR    |= DEMCR_TRCENA_MSK;
    *(volatile uint32_t *)DWT_CYCCNT_ADDR = 0;
    *(volatile uint32_t *)DWT_CTRL_ADDR |= DWT_CTRL_CYCCNTENA_MSK;
#endif

    bench_entry();

#ifdef PLATFORM_HARDWARE
    /* One report line per measured rep — the harness ran INNER_REPS
     * warm-cache iterations and stored each one's DWT delta. */
    for (uint32_t i = 0; i < INNER_REPS; i++) {
        emit_report(BENCH_NAME, i, _inner_delta_cyc[i]);
    }
#else
    /* gem5: cycles for each rep come from m5out/stats.txt (one work
     * region per rep). Just emit a single marker so the parser knows
     * which kernel this stats file is for. */
    semi_write0("MICROBENCH name=" BENCH_NAME "\n");
#endif

    semi_exit(0);
}

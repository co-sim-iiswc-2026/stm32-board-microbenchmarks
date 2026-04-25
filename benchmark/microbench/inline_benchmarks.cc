// Inline-asm microbenchmarks with ROI inside the function.
// The compiler controls code layout; no separate .S kernel needed.

#include <ento-bench/roi.h>
#include <ento-bench/bench_config.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>
#include <cstdio>
#include <cstdlib>

extern "C" void initialise_monitor_handles(void);

#ifndef REPS
#define REPS 5000
#endif

// ---------------------------------------------------------------
void __attribute__((noinline)) bench_nop_inline()
{
    start_roi();
    for (int i = 0; i < REPS; i++)
        asm volatile(
            ".balign 16 \n"
            ".rept 100  \n"
            "nop        \n"
            ".endr      \n"
            ::: "memory"
        );
    end_roi();
}

// ---------------------------------------------------------------
void __attribute__((noinline)) bench_alu16_inline()
{
    start_roi();
    for (int i = 0; i < REPS; i++)
        asm volatile(
            ".balign 16           \n"
            ".rept 25             \n"
            "adds r0, r0, r1     \n"
            "subs r2, r2, r3     \n"
            "eors r0, r0, r2     \n"
            "orrs r2, r2, r3     \n"
            ".endr                \n"
            :
            :
            : "r0", "r1", "r2", "r3"
        );
    end_roi();
}

// ---------------------------------------------------------------
void __attribute__((noinline)) bench_mul64_inline()
{
    start_roi();
    for (int i = 0; i < REPS; i++)
        asm volatile(
            ".balign 16            \n"
            "mov r8, #1            \n"
            ".rept 8               \n"
            "mul r0, r0, r8        \n"
            "mul r1, r1, r8        \n"
            "mul r2, r2, r8        \n"
            "mul r3, r3, r8        \n"
            "mul r4, r4, r8        \n"
            "mul r5, r5, r8        \n"
            "mul r6, r6, r8        \n"
            "mul r7, r7, r8        \n"
            ".endr                 \n"
            :
            :
            : "r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8"
        );
    end_roi();
}

// ---------------------------------------------------------------
struct BenchEntry {
    const char* name;
    void (*fn)();
    int ops_per_rep;
};

static const BenchEntry benchmarks[] = {
    { "nop_inline",   bench_nop_inline,   100 },
    { "alu16_inline", bench_alu16_inline, 100 },
    { "mul64_inline", bench_mul64_inline,  64 },
};

int main()
{
    initialise_monitor_handles();
#if !defined(GEM5_SIM) && !defined(QEMU_SIM)
    sys_clk_cfg();
#endif
    SysTick_Setup();
    __enable_irq();
#if !defined(GEM5_SIM) && !defined(QEMU_SIM)
    ENTO_BENCH_SETUP();
#endif
    init_roi_tracking();

    for (const auto& b : benchmarks) {
        b.fn();
        ROIMetrics m = get_roi_stats();

        uint32_t total_cycles = (uint32_t)m.elapsed_cycles;
        uint32_t per_call = total_cycles / REPS;
        uint32_t total_ops = REPS * b.ops_per_rep;

        printf("%-16s total=%10u  per_call=%5u  ops=%10u  CPI=%u.%02u\n",
               b.name,
               total_cycles,
               per_call,
               total_ops,
               total_cycles / total_ops,
               (total_cycles * 100 / total_ops) % 100);
    }

    exit(0);
    return 0;
}

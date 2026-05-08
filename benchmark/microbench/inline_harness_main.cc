// Inline-asm microbenchmark using the EntoBench harness.
// The kernel is a lambda with inline asm so the compiler can inline it
// into the harness loop — no function pointer indirection.

#include <ento-bench/harness.h>
#include <ento-bench/bench_config.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

#if !defined(KERNEL_ASM)
#error "Define KERNEL_ASM as the inline asm string"
#endif

#if !defined(KERNEL_CLOBBER)
#define KERNEL_CLOBBER "memory"
#endif

#define XSTR(x) #x
#define STR(x) XSTR(x)

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
    ENTO_BENCH_PRINT_CONFIG();

    auto problem = EntoBench::make_basic_problem([]() __attribute__((always_inline)) {
        asm volatile(KERNEL_ASM ::: KERNEL_CLOBBER);
    });
    ENTO_BENCH_HARNESS_TYPE(decltype(problem));
    BenchHarness harness(problem, STR(KERNEL_NAME));
    harness.run();

    exit(0);
    return 0;
}

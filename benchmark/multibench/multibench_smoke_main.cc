// Multibench main — smoke 5-bench subset.
//
// Used to verify the MultiHarness scaffold builds end-to-end before
// expanding to the full 35-bench core/memory split. Bench list is
// hard-coded in src/generated/multibench_smoke_table.h; regenerate via:
//   python3 benchmark/multibench/tools/gen_kernels.py --smoke-only

#include <ento-bench/multi_harness.h>
#include <ento-bench/bench_config.h>

#ifdef STM32_BUILD
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>
#endif

#include "generated/multibench_smoke_table.h"

#include <cstdlib>

extern "C" void initialise_monitor_handles(void);

int main()
{
    initialise_monitor_handles();

#if defined(STM32_BUILD) && !defined(GEM5_SIM)
    sys_clk_cfg();
#endif

#ifdef STM32_BUILD
    SysTick_Setup();
    __enable_irq();
#endif

#if !defined(GEM5_SIM)
    ENTO_BENCH_SETUP();
#endif
    ENTO_BENCH_PRINT_CONFIG();

    EntoBench::MultiHarness h(BENCHES_SMOKE, "multibench_smoke");
    h.setup();
    h.run();
    h.teardown();

    std::exit(0);
    return 0;
}

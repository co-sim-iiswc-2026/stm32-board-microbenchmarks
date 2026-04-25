// Minimal VLDMIA d-register variant: single d-reg, no writeback.
// Tests the simplest form of vldmia-with-d-register that Eigen emits.
//   vldmia rN, {d0}   — load 8 bytes into d0 (= s0,s1 pair)

#include <cstdint>
#include <cstring>

#include <ento-bench/bench_config.h>
#include <ento-bench/capture_problem.h>
#include <ento-bench/harness.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

class BenchVldmiaD1 : public EntoBench::CaptureProblem<BenchVldmiaD1, 8>
{
public:
  void prepare_impl()
  {
    entry_words_[0] = 0x3f800000u;  // 1.0f -> s0 (low half of d0)
    entry_words_[1] = 0x40000000u;  // 2.0f -> s1 (high half of d0)
    std::memset(exit_, 0, sizeof(exit_));
    uint32_t fpscr_init = 0u;
    __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr_init));
  }

  void solve_impl()
  {
    __asm__ volatile(
      "vldmia %0, {d0}\n\t"
      "vstr.32 s0, [%1, #0]\n\t"
      "vstr.32 s1, [%1, #4]\n\t"
      :
      : "r"(entry_words_), "r"(exit_)
      : "s0", "s1", "memory"
    );
  }

private:
  alignas(8) uint32_t entry_words_[2]{};
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
  ENTO_BENCH_PRINT_CONFIG();

  BenchVldmiaD1 problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_vldmia_d1");
  harness.run();

  exit(0);
  return 0;
}

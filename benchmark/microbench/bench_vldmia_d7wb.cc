// EXACT matvec repro: VLDMIA with d7 AND writeback.
//   vldmia rN!, {d7}   — load 8 bytes into d7 (= s14,s15), advance rN by 8
// This is the specific instruction emitted at 0x800551c in bench-matvec-12x12.elf
// that causes gem5's decoder to segfault.

#include <cstdint>
#include <cstring>

#include <ento-bench/bench_config.h>
#include <ento-bench/capture_problem.h>
#include <ento-bench/harness.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

class BenchVldmiaD7Wb : public EntoBench::CaptureProblem<BenchVldmiaD7Wb, 12>
{
public:
  void prepare_impl()
  {
    entry_words_[0] = 0x3f800000u;  // 1.0f -> s14 (low half of d7)
    entry_words_[1] = 0x40000000u;  // 2.0f -> s15 (high half of d7)
    std::memset(exit_, 0, sizeof(exit_));
    uint32_t fpscr_init = 0u;
    __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr_init));
  }

  void solve_impl()
  {
    uint32_t* base = entry_words_;
    __asm__ volatile(
      "vldmia %0!, {d7}\n\t"          // writeback — base advances by 8
      "vstr.32 s14, [%1, #0]\n\t"     // dump s14 (low half of d7)
      "vstr.32 s15, [%1, #4]\n\t"     // dump s15 (high half of d7)
      "str  %0, [%1, #8]\n\t"         // dump updated base to verify writeback
      : "+r"(base)
      : "r"(exit_)
      : "s14", "s15", "memory"
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

  BenchVldmiaD7Wb problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_vldmia_d7wb");
  harness.run();

  exit(0);
  return 0;
}

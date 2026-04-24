// Range VSTMIA: store 4 d-regs (= 8 floats) to memory.
//   vstmia rN, {d0-d3}
// Tests whether gem5 decoder handles multi-d-reg vstmia.
// s0..s7 loaded individually via proven vldr first, then bulk-stored via vstmia.

#include <cstdint>
#include <cstring>

#include <ento-bench/bench_config.h>
#include <ento-bench/capture_problem.h>
#include <ento-bench/harness.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

class BenchVstmiaDRangeCapture : public EntoBench::CaptureProblem<BenchVstmiaDRangeCapture, 32>
{
public:
  void prepare_impl()
  {
    for (int i = 0; i < 8; ++i) {
      float f = static_cast<float>(i + 1);
      std::memcpy(&entry_words_[i], &f, 4);
    }
    std::memset(exit_, 0, sizeof(exit_));
    uint32_t fpscr_init = 0u;
    __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr_init));
  }

  void solve_impl()
  {
    __asm__ volatile(
      "vldr.32 s0, [%0, #0]\n\t"
      "vldr.32 s1, [%0, #4]\n\t"
      "vldr.32 s2, [%0, #8]\n\t"
      "vldr.32 s3, [%0, #12]\n\t"
      "vldr.32 s4, [%0, #16]\n\t"
      "vldr.32 s5, [%0, #20]\n\t"
      "vldr.32 s6, [%0, #24]\n\t"
      "vldr.32 s7, [%0, #28]\n\t"
      "vstmia %1, {d0-d3}\n\t"        // the instruction under test
      :
      : "r"(entry_words_), "r"(exit_)
      : "s0","s1","s2","s3","s4","s5","s6","s7", "memory"
    );
  }

private:
  alignas(8) uint32_t entry_words_[8]{};
};

int main()
{
  initialise_monitor_handles();
#ifndef GEM5_SIM
  sys_clk_cfg();
#endif
  SysTick_Setup();
  __enable_irq();
#ifndef GEM5_SIM
  ENTO_BENCH_SETUP();
#endif
  ENTO_BENCH_PRINT_CONFIG();

  BenchVstmiaDRangeCapture problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_vstmia_d_range_capture");
  harness.run();

  exit(0);
  return 0;
}

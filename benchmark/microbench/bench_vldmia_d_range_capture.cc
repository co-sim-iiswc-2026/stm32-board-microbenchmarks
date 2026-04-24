// Range VLDMIA: multiple d-regs, no writeback.
//   vldmia rN, {d0-d3}  — load 32 bytes into d0..d3 (= s0..s7)
// Tests whether gem5 decoder handles multi-d-reg vldmia.

#include <cstdint>
#include <cstring>

#include <ento-bench/bench_config.h>
#include <ento-bench/capture_problem.h>
#include <ento-bench/harness.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

class BenchVldmiaDRangeCapture : public EntoBench::CaptureProblem<BenchVldmiaDRangeCapture, 32>
{
public:
  void prepare_impl()
  {
    for (int i = 0; i < 8; ++i) {
      // 1.0, 2.0, 3.0, ..., 8.0 as IEEE 754 bit patterns
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
      "vldmia %0, {d0-d3}\n\t"         // load 4 d-regs = 8 floats (s0..s7)
      "vstr.32 s0, [%1, #0]\n\t"
      "vstr.32 s1, [%1, #4]\n\t"
      "vstr.32 s2, [%1, #8]\n\t"
      "vstr.32 s3, [%1, #12]\n\t"
      "vstr.32 s4, [%1, #16]\n\t"
      "vstr.32 s5, [%1, #20]\n\t"
      "vstr.32 s6, [%1, #24]\n\t"
      "vstr.32 s7, [%1, #28]\n\t"
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

  BenchVldmiaDRangeCapture problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_vldmia_d_range_capture");
  harness.run();

  exit(0);
  return 0;
}

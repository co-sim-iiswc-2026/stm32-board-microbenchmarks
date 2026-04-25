// Preamble-zeroing unit test. Isolates the "zero s0..s31" path.
//
// Strategy under test: 32x vldr.32 sN, [zero_buf + N*4] from a zero-filled
// buffer. Junk-load uses vldr from a separate 0xDEADBEEF buffer — same
// encoding but different data, to confirm the memory path actually
// overwrites previously-loaded values.
// Expected capture: 128 B of zero (s0..s31) + FPSCR = 0.

#include <cstdint>

#include <ento-bench/bench_config.h>
#include <ento-bench/capture_problem.h>
#include <ento-bench/harness.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

namespace {

class BenchPreambleZeroVldr
  : public EntoBench::CaptureProblem<BenchPreambleZeroVldr, 132>
{
public:
  void prepare_impl()
  {
    for (int i = 0; i < 32; ++i) junk_[i] = 0xDEADBEEFu;
    // zero_[] is default-initialized to 0 by the alignas(8) ... {} above.
    uint32_t fpscr_init = 0u;
    __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr_init));
  }

  void solve_impl()
  {
    __asm__ volatile(
      // Load 0xDEADBEEF into s0..s31 via vldr from junk_.
      "vldr.32 s0,  [%0, #0]\n\t"
      "vldr.32 s1,  [%0, #4]\n\t"
      "vldr.32 s2,  [%0, #8]\n\t"
      "vldr.32 s3,  [%0, #12]\n\t"
      "vldr.32 s4,  [%0, #16]\n\t"
      "vldr.32 s5,  [%0, #20]\n\t"
      "vldr.32 s6,  [%0, #24]\n\t"
      "vldr.32 s7,  [%0, #28]\n\t"
      "vldr.32 s8,  [%0, #32]\n\t"
      "vldr.32 s9,  [%0, #36]\n\t"
      "vldr.32 s10, [%0, #40]\n\t"
      "vldr.32 s11, [%0, #44]\n\t"
      "vldr.32 s12, [%0, #48]\n\t"
      "vldr.32 s13, [%0, #52]\n\t"
      "vldr.32 s14, [%0, #56]\n\t"
      "vldr.32 s15, [%0, #60]\n\t"
      "vldr.32 s16, [%0, #64]\n\t"
      "vldr.32 s17, [%0, #68]\n\t"
      "vldr.32 s18, [%0, #72]\n\t"
      "vldr.32 s19, [%0, #76]\n\t"
      "vldr.32 s20, [%0, #80]\n\t"
      "vldr.32 s21, [%0, #84]\n\t"
      "vldr.32 s22, [%0, #88]\n\t"
      "vldr.32 s23, [%0, #92]\n\t"
      "vldr.32 s24, [%0, #96]\n\t"
      "vldr.32 s25, [%0, #100]\n\t"
      "vldr.32 s26, [%0, #104]\n\t"
      "vldr.32 s27, [%0, #108]\n\t"
      "vldr.32 s28, [%0, #112]\n\t"
      "vldr.32 s29, [%0, #116]\n\t"
      "vldr.32 s30, [%0, #120]\n\t"
      "vldr.32 s31, [%0, #124]\n\t"
      // Strategy under test: zero via vldr from zero_ buffer.
      "vldr.32 s0,  [%2, #0]\n\t"
      "vldr.32 s1,  [%2, #4]\n\t"
      "vldr.32 s2,  [%2, #8]\n\t"
      "vldr.32 s3,  [%2, #12]\n\t"
      "vldr.32 s4,  [%2, #16]\n\t"
      "vldr.32 s5,  [%2, #20]\n\t"
      "vldr.32 s6,  [%2, #24]\n\t"
      "vldr.32 s7,  [%2, #28]\n\t"
      "vldr.32 s8,  [%2, #32]\n\t"
      "vldr.32 s9,  [%2, #36]\n\t"
      "vldr.32 s10, [%2, #40]\n\t"
      "vldr.32 s11, [%2, #44]\n\t"
      "vldr.32 s12, [%2, #48]\n\t"
      "vldr.32 s13, [%2, #52]\n\t"
      "vldr.32 s14, [%2, #56]\n\t"
      "vldr.32 s15, [%2, #60]\n\t"
      "vldr.32 s16, [%2, #64]\n\t"
      "vldr.32 s17, [%2, #68]\n\t"
      "vldr.32 s18, [%2, #72]\n\t"
      "vldr.32 s19, [%2, #76]\n\t"
      "vldr.32 s20, [%2, #80]\n\t"
      "vldr.32 s21, [%2, #84]\n\t"
      "vldr.32 s22, [%2, #88]\n\t"
      "vldr.32 s23, [%2, #92]\n\t"
      "vldr.32 s24, [%2, #96]\n\t"
      "vldr.32 s25, [%2, #100]\n\t"
      "vldr.32 s26, [%2, #104]\n\t"
      "vldr.32 s27, [%2, #108]\n\t"
      "vldr.32 s28, [%2, #112]\n\t"
      "vldr.32 s29, [%2, #116]\n\t"
      "vldr.32 s30, [%2, #120]\n\t"
      "vldr.32 s31, [%2, #124]\n\t"
      // Capture s0..s31 and FPSCR into exit_.
      "vstr.32 s0,  [%1, #0]\n\t"
      "vstr.32 s1,  [%1, #4]\n\t"
      "vstr.32 s2,  [%1, #8]\n\t"
      "vstr.32 s3,  [%1, #12]\n\t"
      "vstr.32 s4,  [%1, #16]\n\t"
      "vstr.32 s5,  [%1, #20]\n\t"
      "vstr.32 s6,  [%1, #24]\n\t"
      "vstr.32 s7,  [%1, #28]\n\t"
      "vstr.32 s8,  [%1, #32]\n\t"
      "vstr.32 s9,  [%1, #36]\n\t"
      "vstr.32 s10, [%1, #40]\n\t"
      "vstr.32 s11, [%1, #44]\n\t"
      "vstr.32 s12, [%1, #48]\n\t"
      "vstr.32 s13, [%1, #52]\n\t"
      "vstr.32 s14, [%1, #56]\n\t"
      "vstr.32 s15, [%1, #60]\n\t"
      "vstr.32 s16, [%1, #64]\n\t"
      "vstr.32 s17, [%1, #68]\n\t"
      "vstr.32 s18, [%1, #72]\n\t"
      "vstr.32 s19, [%1, #76]\n\t"
      "vstr.32 s20, [%1, #80]\n\t"
      "vstr.32 s21, [%1, #84]\n\t"
      "vstr.32 s22, [%1, #88]\n\t"
      "vstr.32 s23, [%1, #92]\n\t"
      "vstr.32 s24, [%1, #96]\n\t"
      "vstr.32 s25, [%1, #100]\n\t"
      "vstr.32 s26, [%1, #104]\n\t"
      "vstr.32 s27, [%1, #108]\n\t"
      "vstr.32 s28, [%1, #112]\n\t"
      "vstr.32 s29, [%1, #116]\n\t"
      "vstr.32 s30, [%1, #120]\n\t"
      "vstr.32 s31, [%1, #124]\n\t"
      "vmrs r0, fpscr\n\t"
      "str  r0, [%1, #128]\n\t"
      :
      : "r"(junk_), "r"(exit_), "r"(zero_)
      : "r0",
        "s0",  "s1",  "s2",  "s3",  "s4",  "s5",  "s6",  "s7",
        "s8",  "s9",  "s10", "s11", "s12", "s13", "s14", "s15",
        "s16", "s17", "s18", "s19", "s20", "s21", "s22", "s23",
        "s24", "s25", "s26", "s27", "s28", "s29", "s30", "s31",
        "memory"
    );
  }

private:
  alignas(8) uint32_t junk_[32]{};
  alignas(8) uint32_t zero_[32]{};
};

}  // namespace

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

  BenchPreambleZeroVldr problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_preamble_zero_vldr");
  harness.run();

  exit(0);
  return 0;
}

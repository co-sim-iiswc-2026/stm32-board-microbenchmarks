// Preamble-zeroing unit test. Isolates the "zero s0..s31" path used by
// Level A/B tests so any gem5 decoder bug in that path is caught
// independently, not blamed on the sequence under test.
//
// Strategy under test: mov r0,#0; vmov dN, r0, r0 (GP pair -> D-reg).
// Junk-load uses vldr (known-good on board + gem5).
// Expected capture: 128 B of zero (s0..s31) + FPSCR = 0.

#include <cstdint>

#include <ento-bench/bench_config.h>
#include <ento-bench/capture_problem.h>
#include <ento-bench/harness.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

namespace {

class BenchPreambleZeroVmovDpair
  : public EntoBench::CaptureProblem<BenchPreambleZeroVmovDpair, 132>
{
public:
  void prepare_impl()
  {
    for (int i = 0; i < 32; ++i) junk_[i] = 0xDEADBEEFu;
    uint32_t fpscr_init = 0u;
    __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr_init));
  }

  void solve_impl()
  {
    __asm__ volatile(
      // Load 0xDEADBEEF into s0..s31 via vldr (trusted path).
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
      // Strategy under test: zero via vmov GP-pair -> D-reg.
      "mov r0, #0\n\t"
      "vmov d0,  r0, r0\n\t"
      "vmov d1,  r0, r0\n\t"
      "vmov d2,  r0, r0\n\t"
      "vmov d3,  r0, r0\n\t"
      "vmov d4,  r0, r0\n\t"
      "vmov d5,  r0, r0\n\t"
      "vmov d6,  r0, r0\n\t"
      "vmov d7,  r0, r0\n\t"
      "vmov d8,  r0, r0\n\t"
      "vmov d9,  r0, r0\n\t"
      "vmov d10, r0, r0\n\t"
      "vmov d11, r0, r0\n\t"
      "vmov d12, r0, r0\n\t"
      "vmov d13, r0, r0\n\t"
      "vmov d14, r0, r0\n\t"
      "vmov d15, r0, r0\n\t"
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
      : "r"(junk_), "r"(exit_)
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

  BenchPreambleZeroVmovDpair problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_preamble_zero_vmov_dpair");
  harness.run();

  exit(0);
  return 0;
}

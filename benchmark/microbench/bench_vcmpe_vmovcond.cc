// Capture the vcmpe.f32 -> vmrs APSR_nzcv,fpscr -> IT -> vmov{cond}.f32 chain
// that tinympc emits for ADMM box-clamp. None of vcmpe / vmrs / conditional
// vmov are differentially tested in isolation, and they're the strongest
// uncovered suspects for the tinympc gem5 divergence.
//
// Pattern under test (matches bench-tinympc-diff-iter1.elf disasm exactly):
//   vcmpe.f32 sV, sLo ; vmrs APSR_nzcv, fpscr ; it le ; vmovle.f32 sV, sLo
//   vcmpe.f32 sV, sHi ; vmrs APSR_nzcv, fpscr ; it pl ; vmovpl.f32 sV, sHi
//   (clamp up to lo, then down to hi)
//
// Three test vectors exercise all four cond/no-cond branches:
//   v=0.5   in [-1, 1]    -> both le/pl skip -> s0 = 0.5  (predicates correctly NOT taken)
//   v=2.0   above hi=1    -> le skip, pl take -> s1 = 1.0 (vmovpl triggers)
//   v=-2.0  below lo=-1   -> le take, pl skip -> s2 = -1.0 (vmovle triggers)

#include <cstdint>

#include <ento-bench/bench_config.h>
#include <ento-bench/capture_problem.h>
#include <ento-bench/harness.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

namespace {

class BenchVcmpeVmovcond
  : public EntoBench::CaptureProblem<BenchVcmpeVmovcond, 132>
{
public:
  void prepare_impl()
  {
    // IEEE-754 bit patterns
    entry_[0] = 0x3f000000u;  //  0.5  (in-range)
    entry_[1] = 0x40000000u;  //  2.0  (above hi)
    entry_[2] = 0xc0000000u;  // -2.0  (below lo)
    entry_[3] = 0xbf800000u;  // -1.0  (lo)
    entry_[4] = 0x3f800000u;  //  1.0  (hi)
    uint32_t fpscr_init = 0u;
    __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr_init));
  }

  void solve_impl()
  {
    __asm__ volatile(
      // Zero s0..s31 so spectator-register corruption shows up.
      // Use vmov GP -> S-reg (validated path, not vldmia which is broken).
      "mov r0, #0\n\t"
      "vmov s0,  r0\n\t" "vmov s1,  r0\n\t" "vmov s2,  r0\n\t" "vmov s3,  r0\n\t"
      "vmov s4,  r0\n\t" "vmov s5,  r0\n\t" "vmov s6,  r0\n\t" "vmov s7,  r0\n\t"
      "vmov s8,  r0\n\t" "vmov s9,  r0\n\t" "vmov s10, r0\n\t" "vmov s11, r0\n\t"
      "vmov s12, r0\n\t" "vmov s13, r0\n\t" "vmov s14, r0\n\t" "vmov s15, r0\n\t"
      "vmov s16, r0\n\t" "vmov s17, r0\n\t" "vmov s18, r0\n\t" "vmov s19, r0\n\t"
      "vmov s20, r0\n\t" "vmov s21, r0\n\t" "vmov s22, r0\n\t" "vmov s23, r0\n\t"
      "vmov s24, r0\n\t" "vmov s25, r0\n\t" "vmov s26, r0\n\t" "vmov s27, r0\n\t"
      "vmov s28, r0\n\t" "vmov s29, r0\n\t" "vmov s30, r0\n\t" "vmov s31, r0\n\t"

      // Load the three values + bounds via vldr (trusted path).
      "vldr.32 s0,  [%0, #0]\n\t"   // 0.5
      "vldr.32 s1,  [%0, #4]\n\t"   // 2.0
      "vldr.32 s2,  [%0, #8]\n\t"   // -2.0
      "vldr.32 s10, [%0, #12]\n\t"  // lo = -1.0
      "vldr.32 s11, [%0, #16]\n\t"  // hi = 1.0

      // --- Test 1: clamp 0.5 (in-range, both predicates skip) ---
      "vcmpe.f32 s0, s10\n\t"
      "vmrs APSR_nzcv, fpscr\n\t"
      "it le\n\t"
      "vmovle.f32 s0, s10\n\t"
      "vcmpe.f32 s0, s11\n\t"
      "vmrs APSR_nzcv, fpscr\n\t"
      "it pl\n\t"
      "vmovpl.f32 s0, s11\n\t"

      // --- Test 2: clamp 2.0 (above hi, vmovpl triggers) ---
      "vcmpe.f32 s1, s10\n\t"
      "vmrs APSR_nzcv, fpscr\n\t"
      "it le\n\t"
      "vmovle.f32 s1, s10\n\t"
      "vcmpe.f32 s1, s11\n\t"
      "vmrs APSR_nzcv, fpscr\n\t"
      "it pl\n\t"
      "vmovpl.f32 s1, s11\n\t"

      // --- Test 3: clamp -2.0 (below lo, vmovle triggers) ---
      "vcmpe.f32 s2, s10\n\t"
      "vmrs APSR_nzcv, fpscr\n\t"
      "it le\n\t"
      "vmovle.f32 s2, s10\n\t"
      "vcmpe.f32 s2, s11\n\t"
      "vmrs APSR_nzcv, fpscr\n\t"
      "it pl\n\t"
      "vmovpl.f32 s2, s11\n\t"

      // Capture s0..s31 + FPSCR into exit_.
      "vstr.32 s0,  [%1, #0]\n\t"   "vstr.32 s1,  [%1, #4]\n\t"
      "vstr.32 s2,  [%1, #8]\n\t"   "vstr.32 s3,  [%1, #12]\n\t"
      "vstr.32 s4,  [%1, #16]\n\t"  "vstr.32 s5,  [%1, #20]\n\t"
      "vstr.32 s6,  [%1, #24]\n\t"  "vstr.32 s7,  [%1, #28]\n\t"
      "vstr.32 s8,  [%1, #32]\n\t"  "vstr.32 s9,  [%1, #36]\n\t"
      "vstr.32 s10, [%1, #40]\n\t"  "vstr.32 s11, [%1, #44]\n\t"
      "vstr.32 s12, [%1, #48]\n\t"  "vstr.32 s13, [%1, #52]\n\t"
      "vstr.32 s14, [%1, #56]\n\t"  "vstr.32 s15, [%1, #60]\n\t"
      "vstr.32 s16, [%1, #64]\n\t"  "vstr.32 s17, [%1, #68]\n\t"
      "vstr.32 s18, [%1, #72]\n\t"  "vstr.32 s19, [%1, #76]\n\t"
      "vstr.32 s20, [%1, #80]\n\t"  "vstr.32 s21, [%1, #84]\n\t"
      "vstr.32 s22, [%1, #88]\n\t"  "vstr.32 s23, [%1, #92]\n\t"
      "vstr.32 s24, [%1, #96]\n\t"  "vstr.32 s25, [%1, #100]\n\t"
      "vstr.32 s26, [%1, #104]\n\t" "vstr.32 s27, [%1, #108]\n\t"
      "vstr.32 s28, [%1, #112]\n\t" "vstr.32 s29, [%1, #116]\n\t"
      "vstr.32 s30, [%1, #120]\n\t" "vstr.32 s31, [%1, #124]\n\t"
      "vmrs r0, fpscr\n\t"
      "str  r0, [%1, #128]\n\t"
      :
      : "r"(entry_), "r"(exit_)
      : "r0", "cc",
        "s0",  "s1",  "s2",  "s3",  "s4",  "s5",  "s6",  "s7",
        "s8",  "s9",  "s10", "s11", "s12", "s13", "s14", "s15",
        "s16", "s17", "s18", "s19", "s20", "s21", "s22", "s23",
        "s24", "s25", "s26", "s27", "s28", "s29", "s30", "s31",
        "memory"
    );
  }

private:
  alignas(8) uint32_t entry_[5]{};
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

  BenchVcmpeVmovcond problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_vcmpe_vmovcond");
  harness.run();

  exit(0);
  return 0;
}

// VLDM/VSTM round-trip capture test. Loads 4 floats via VLDM, stores back via VSTM.
// If VLDM/VSTM are broken in gem5, the round-trip exit state won't match entry.

#include <cstdint>
#include <span>

#include <ento-bench/bench_config.h>
#include <ento-bench/harness.h>
#include <ento-bench/problem.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

namespace {

class BenchVldmVstmCapture : public EntoBench::EntoProblem<BenchVldmVstmCapture>
{
public:
  static constexpr bool RequiresDataset_  = false;
  static constexpr bool SaveResults_      = false;
  static constexpr bool RequiresPrepare_  = true;

  bool deserialize_impl(const char*) { return true; }
  static constexpr const char* header_impl() { return ""; }
  bool validate_impl() const { return true; }
  void clear_impl() {}

  void prepare_impl()
  {
    entry_[0] = 0x3f800000u;   // 1.0f
    entry_[1] = 0x40000000u;   // 2.0f
    entry_[2] = 0x40400000u;   // 3.0f
    entry_[3] = 0x40800000u;   // 4.0f
    exit_[0] = exit_[1] = exit_[2] = exit_[3] = exit_[4] = 0;
    uint32_t fpscr_init = 0u;
    __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr_init));
  }

  void solve_impl()
  {
    __asm__ volatile(
      "vldm %0, {s0-s3}\n\t"
      "vstm %1, {s0-s3}\n\t"
      "vmrs r0, fpscr\n\t"
      "str  r0, [%1, #16]\n\t"
      :
      : "r"(entry_), "r"(exit_)
      : "s0", "s1", "s2", "s3", "r0", "memory"
    );
  }

  EntoBench::ResultSig result_signature_impl() const
  {
    const uint8_t* p = reinterpret_cast<const uint8_t*>(exit_);
    constexpr size_t n = sizeof(exit_);
    return EntoBench::ResultSig{
      .bytes = std::span<const uint8_t>{p, n},
    };
  }

private:
  alignas(8) uint32_t entry_[4]{};
  alignas(8) uint32_t exit_[5]{};   // 4 floats + FPSCR
};

}  // namespace

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

  BenchVldmVstmCapture problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_vldm_vstm_capture");
  harness.run();

  exit(0);
  return 0;
}

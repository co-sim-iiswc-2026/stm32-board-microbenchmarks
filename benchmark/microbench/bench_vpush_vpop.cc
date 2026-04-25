// VPUSH/VPOP capture test. Loads known value into s4, pushes to stack,
// overwrites s4 with a different value, pops from stack, stores s4.
// If VPUSH/VPOP are broken in gem5, the exit s4 won't be the original value.

#include <cstdint>
#include <span>

#include <ento-bench/bench_config.h>
#include <ento-bench/harness.h>
#include <ento-bench/problem.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

namespace {

class BenchVpushVpop : public EntoBench::EntoProblem<BenchVpushVpop>
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
    entry_[0] = 0x3f800000u;   // 1.0f — original value
    entry_[1] = 0x40000000u;   // 2.0f — clobber value (should be overwritten on pop)
    exit_[0] = 0;
    exit_[1] = 0;
    uint32_t fpscr_init = 0u;
    __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr_init));
  }

  void solve_impl()
  {
    __asm__ volatile(
      "vldr.32 s4, [%0, #0]\n\t"     // s4 = 1.0f (original)
      "vpush {s4}\n\t"               // push 1.0f to stack
      "vldr.32 s4, [%0, #4]\n\t"     // clobber s4 with 2.0f
      "vpop {s4}\n\t"                // restore s4 from stack (should be 1.0f)
      "vstr.32 s4, [%1, #0]\n\t"     // store s4 — expect 1.0f
      "vmrs r0, fpscr\n\t"
      "str  r0, [%1, #4]\n\t"
      :
      : "r"(entry_), "r"(exit_)
      : "s4", "r0", "memory"
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
  alignas(8) uint32_t entry_[2]{};
  alignas(8) uint32_t exit_[2]{};
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

  BenchVpushVpop problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_vpush_vpop");
  harness.run();

  exit(0);
  return 0;
}

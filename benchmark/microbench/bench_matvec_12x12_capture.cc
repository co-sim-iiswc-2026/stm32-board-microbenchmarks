// 12x12 * 12x1 matvec capture test using TinyMPC's actual Adyn and a diverse x.
// Exercises the Eigen-generated matmul asm with the same dynamics matrix that
// TinyMPC's ADMM forward pass uses. If this diverges between board and gem5,
// we've isolated the bug to Eigen-style matvec (a much smaller surface than
// a full TinyMPC solve).

#include <cstdint>
#include <cstring>
#include <Eigen/Dense>

#include <ento-bench/bench_config.h>
#include <ento-bench/capture_problem.h>
#include <ento-bench/harness.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

class BenchMatVec12x12 : public EntoBench::CaptureProblem<BenchMatVec12x12, 48>
{
public:
  void prepare_impl()
  {
    // Adyn — lifted verbatim from TinyMPC's quadrotor model
    // (external/ento-bench/benchmark/control/bench_tinympc.cc:61-73).
    A_ << 1.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0245250f, 0.0000000f, 0.0500000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0002044f, 0.0000000f,
          0.0000000f, 1.0000000f, 0.0000000f, -0.0245250f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0500000f, 0.0000000f, -0.0002044f, 0.0000000f, 0.0000000f,
          0.0000000f, 0.0000000f, 1.0000000f,  0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0500000f,  0.0000000f, 0.0000000f, 0.0000000f,
          0.0000000f, 0.0000000f, 0.0000000f,  1.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f,  0.0250000f, 0.0000000f, 0.0000000f,
          0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 1.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0250000f, 0.0000000f,
          0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0000000f, 1.0000000f, 0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0000000f, 0.0250000f,
          0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.9810000f, 0.0000000f, 1.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0122625f, 0.0000000f,
          0.0000000f, 0.0000000f, 0.0000000f, -0.9810000f, 0.0000000f, 0.0000000f, 0.0000000f, 1.0000000f, 0.0000000f, -0.0122625f, 0.0000000f, 0.0000000f,
          0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 1.0000000f,  0.0000000f, 0.0000000f, 0.0000000f,
          0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f,  1.0000000f, 0.0000000f, 0.0000000f,
          0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 1.0000000f, 0.0000000f,
          0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f, 0.0000000f,  0.0000000f, 0.0000000f, 1.0000000f;

    // Diverse x: mixed signs, spans ~3 orders of magnitude, includes zeros.
    x_ <<  0.1f,    -0.2f,     0.05f,
          -0.3f,     0.4f,     0.0f,
           0.01f,    0.5f,    -0.001f,
           1.5f,    -2.0f,     0.0f;

    std::memset(exit_, 0, sizeof(exit_));
    uint32_t fpscr_init = 0u;
    __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr_init));
  }

  void solve_impl()
  {
    Eigen::Matrix<float, 12, 1> y = A_ * x_;
    std::memcpy(exit_, y.data(), 48);
  }

private:
  Eigen::Matrix<float, 12, 12> A_;
  Eigen::Matrix<float, 12, 1>  x_;
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

  BenchMatVec12x12 problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_matvec_12x12_capture");
  harness.run();

  exit(0);
  return 0;
}

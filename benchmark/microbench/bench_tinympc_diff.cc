// TinyMPC capture test for differential testing between board and gem5.
// Runs one MPC solve with hardcoded Adyn/Bdyn/Q/R/x0/x_ref (no dataset),
// captures the first control input u[0] (4 floats, 16 bytes) as the signature.
// Mirrors bench_tinympc.cc's construction pattern; swaps OptControlProblem
// for a no-dataset capture class.

#include <cstdint>
#include <cstring>
#include <span>
#include <Eigen/Dense>

#include <ento-bench/bench_config.h>
#include <ento-bench/harness.h>
#include <ento-bench/problem.h>
#include <ento-control/tinympc_solver.h>
#include <ento-mcu/cache_util.h>
#include <ento-mcu/flash_util.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

#ifndef TINYMPC_MAX_ITER
#define TINYMPC_MAX_ITER 100
#endif

#ifndef BENCH_NAME
#define BENCH_NAME bench_tinympc_diff
#endif

#define XSTR(x) #x
#define STR(x) XSTR(x)

constexpr int num_states  = 12;
constexpr int num_inputs  = 4;
constexpr int len_horizon = 10;
using Scalar_t = float;
using Solver   = ::TinyMPCSolver<Scalar_t, num_states, num_inputs, len_horizon>;

class BenchTinyMPCDiff : public EntoBench::EntoProblem<BenchTinyMPCDiff>
{
public:
  static constexpr bool RequiresDataset_  = false;
  static constexpr bool SaveResults_      = false;
  static constexpr bool RequiresPrepare_  = true;

  BenchTinyMPCDiff(Solver& solver) : solver_(solver) {}

  bool deserialize_impl(const char*) { return true; }
  static constexpr const char* header_impl() { return ""; }
  bool validate_impl() const { return true; }
  void clear_impl() {}

  void prepare_impl()
  {
    // Fixed initial state: small position offset, zero velocity/attitude.
    Eigen::Matrix<Scalar_t, num_states, 1> x0;
    x0 <<  0.1f,  0.2f, -0.1f,
           0.0f,  0.0f,  0.0f,
           0.0f,  0.0f,  0.0f,
           0.0f,  0.0f,  0.0f;

    // Fixed reference: drive state to origin.
    Eigen::Matrix<Scalar_t, num_states, len_horizon> x_ref =
        Eigen::Matrix<Scalar_t, num_states, len_horizon>::Zero();

    solver_.set_x0(x0);
    solver_.set_x_ref(x_ref);
    solver_.reset_duals();

    std::memset(exit_, 0, sizeof(exit_));
  }

  void solve_impl()
  {
    solver_.solve();
  }

  EntoBench::ResultSig result_signature_impl() const
  {
    Eigen::Matrix<Scalar_t, num_inputs, 1> u0 = solver_.get_u0();
    std::memcpy(const_cast<uint32_t*>(exit_), u0.data(), sizeof(exit_));
    const uint8_t* p = reinterpret_cast<const uint8_t*>(exit_);
    constexpr size_t n = sizeof(exit_);
    return EntoBench::ResultSig{
      .bytes = std::span<const uint8_t>{p, n},
    };
  }

private:
  Solver& solver_;
  alignas(8) mutable uint32_t exit_[num_inputs]{};
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
  enable_instruction_cache();
  enable_instruction_cache_prefetch();
  icache_enable();
  ENTO_BENCH_SETUP();
#endif
  ENTO_BENCH_PRINT_CONFIG();

  // Matrix literals lifted from external/ento-bench/benchmark/control/bench_tinympc.cc:61-93
  Eigen::Matrix<Scalar_t, num_states, num_states> Adyn = (Eigen::Matrix<Scalar_t, num_states, num_states>() <<
      1.0000000, 0.0000000, 0.0000000,  0.0000000, 0.0245250, 0.0000000, 0.0500000, 0.0000000, 0.0000000,  0.0000000, 0.0002044, 0.0000000,
      0.0000000, 1.0000000, 0.0000000, -0.0245250, 0.0000000, 0.0000000, 0.0000000, 0.0500000, 0.0000000, -0.0002044, 0.0000000, 0.0000000,
      0.0000000, 0.0000000, 1.0000000,  0.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0500000,  0.0000000, 0.0000000, 0.0000000,
      0.0000000, 0.0000000, 0.0000000,  1.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000,  0.0250000, 0.0000000, 0.0000000,
      0.0000000, 0.0000000, 0.0000000,  0.0000000, 1.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000,  0.0000000, 0.0250000, 0.0000000,
      0.0000000, 0.0000000, 0.0000000,  0.0000000, 0.0000000, 1.0000000, 0.0000000, 0.0000000, 0.0000000,  0.0000000, 0.0000000, 0.0250000,
      0.0000000, 0.0000000, 0.0000000,  0.0000000, 0.9810000, 0.0000000, 1.0000000, 0.0000000, 0.0000000,  0.0000000, 0.0122625, 0.0000000,
      0.0000000, 0.0000000, 0.0000000, -0.9810000, 0.0000000, 0.0000000, 0.0000000, 1.0000000, 0.0000000, -0.0122625, 0.0000000, 0.0000000,
      0.0000000, 0.0000000, 0.0000000,  0.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000, 1.0000000,  0.0000000, 0.0000000, 0.0000000,
      0.0000000, 0.0000000, 0.0000000,  0.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000,  1.0000000, 0.0000000, 0.0000000,
      0.0000000, 0.0000000, 0.0000000,  0.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000,  0.0000000, 1.0000000, 0.0000000,
      0.0000000, 0.0000000, 0.0000000,  0.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000, 0.0000000,  0.0000000, 0.0000000, 1.0000000).finished();

  Eigen::Matrix<Scalar_t, num_states, num_inputs> Bdyn = (Eigen::Matrix<Scalar_t, num_states, num_inputs>() <<
       -0.0007069,   0.0007773,  0.0007091,  -0.0007795,
        0.0007034,   0.0007747, -0.0007042,  -0.0007739,
        0.0052554,   0.0052554,  0.0052554,   0.0052554,
       -0.1720966,  -0.1895213,  0.1722891,   0.1893288,
       -0.1729419,   0.1901740,  0.1734809,  -0.1907131,
        0.0123423,  -0.0045148, -0.0174024,   0.0095748,
       -0.0565520,   0.0621869,  0.0567283,  -0.0623632,
        0.0562756,   0.0619735, -0.0563386,  -0.0619105,
        0.2102143,   0.2102143,  0.2102143,   0.2102143,
      -13.7677303, -15.1617018, 13.7831318,  15.1463003,
      -13.8353509,  15.2139209, 13.8784751, -15.2570451,
        0.9873856,  -0.3611820, -1.3921880,   0.7659845).finished();

  Eigen::Matrix<Scalar_t, num_states, 1> Q{ 100.0000000, 100.0000000, 100.0000000, 4.0000000, 4.0000000, 400.0000000, 4.0000000, 4.0000000, 4.0000000, 2.0408163, 2.0408163, 4.0000000 };
  Eigen::Matrix<Scalar_t, num_inputs, 1> R{ 4.0, 4.0, 4.0, 4.0 };

  Eigen::Matrix<Scalar_t, num_states, len_horizon>     x_min = Eigen::Matrix<Scalar_t, num_states, len_horizon>::Constant(-5);
  Eigen::Matrix<Scalar_t, num_states, len_horizon>     x_max = Eigen::Matrix<Scalar_t, num_states, len_horizon>::Constant( 5);
  Eigen::Matrix<Scalar_t, num_inputs, len_horizon - 1> u_min = Eigen::Matrix<Scalar_t, num_inputs, len_horizon - 1>::Constant(-0.5);
  Eigen::Matrix<Scalar_t, num_inputs, len_horizon - 1> u_max = Eigen::Matrix<Scalar_t, num_inputs, len_horizon - 1>::Constant( 0.5);

  float rho_value = 5.0f;

  static Solver solver(Adyn, Bdyn, Q, R, rho_value, x_min, x_max, u_min, u_max, false);

  // max_iter parameterized via TINYMPC_MAX_ITER define (default 100) for bisection.
  auto tiny_settings = solver.get_settings();
  solver.update_settings(tiny_settings.abs_pri_tol,
                         tiny_settings.abs_dua_tol,
                         TINYMPC_MAX_ITER,
                         tiny_settings.check_termination,
                         tiny_settings.en_state_bound,
                         tiny_settings.en_input_bound);

  BenchTinyMPCDiff problem(solver);
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, STR(BENCH_NAME));
  harness.run();

  exit(0);
  return 0;
}

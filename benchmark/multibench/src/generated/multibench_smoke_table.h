// Auto-generated smoke-bench table (subset of all kernels).
#ifndef MULTIBENCH_SMOKE_TABLE_H
#define MULTIBENCH_SMOKE_TABLE_H

#include <array>
#include <ento-bench/multi_harness.h>

extern "C" {
  void kernel_nop_8k(void);
  void kernel_alu_indep_const_8k(void);
  void kernel_mul_const_8k(void);
  void kernel_vmul_const_8k(void);
  void kernel_load_hot_8k(void);
}

inline constexpr std::array<EntoBench::BenchEntry, 5> BENCHES_SMOKE = {{
    { "nop_8k", kernel_nop_8k, false, false },
    { "alu_indep_const_8k", kernel_alu_indep_const_8k, false, false },
    { "mul_const_8k", kernel_mul_const_8k, false, false },
    { "vmul_const_8k", kernel_vmul_const_8k, false, false },
    { "load_hot_8k", kernel_load_hot_8k, false, false },
}};

#endif  // MULTIBENCH_SMOKE_TABLE_H

#!/usr/bin/env python3
"""Generate single-instruction FPU capture tests for differential testing.

Emits one .cc file per instruction into benchmark/microbench/generated/.
Each test: loads known entry state, runs one FPU instruction, captures exit state + FPSCR.

Usage:
    python3 verification/gen/fpu_single.py
    # Then reconfigure cmake and build:
    #   cmake --preset stm32-g474re -S benchmark
    #   cmake --build build-entobench --target bench-fpu-vmul-f32
"""

import os
import struct
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
OUT_DIR = REPO_ROOT / "benchmark" / "microbench" / "generated"


def uint_from_float(f):
    """Float to uint32 integer (IEEE 754 bit pattern)."""
    return struct.unpack('<I', struct.pack('<f', f))[0]


def float_hex(f):
    """Float to uint32 hex literal — the IEEE 754 bit pattern as a C uint32 literal."""
    return f"0x{uint_from_float(f):08x}u"


# Instruction specs: (name, asm_line, entry_regs, entry_vals, exit_reg_count, clobber_list)
# entry_vals are floats; they get converted to uint32 hex for the entry buffer.
# clobber_list: all FP regs touched by the instruction + r0 for FPSCR readback.

INSTRUCTIONS = [
    # --- 2-operand arithmetic: Sd = Sn op Sm ---
    {
        "name": "vadd_f32",
        "asm": "vadd.f32 s0, s0, s1",
        "entry": [1.0, 2.0],
        "clobbers": '"s0", "s1"',
    },
    {
        "name": "vsub_f32",
        "asm": "vsub.f32 s0, s0, s1",
        "entry": [1.0, 2.0],
        "clobbers": '"s0", "s1"',
    },
    {
        "name": "vmul_f32",
        "asm": "vmul.f32 s0, s0, s1",
        "entry": [1.0, 2.0],
        "clobbers": '"s0", "s1"',
    },
    {
        "name": "vdiv_f32",
        "asm": "vdiv.f32 s0, s0, s1",
        "entry": [1.0, 2.0],
        "clobbers": '"s0", "s1"',
    },
    {
        "name": "vnmul_f32",
        "asm": "vnmul.f32 s0, s0, s1",
        "entry": [1.0, 2.0],
        "clobbers": '"s0", "s1"',
    },

    # --- Fused multiply-accumulate: Sd ±= Sn * Sm (3-source) ---
    # s0 = accumulator, s1/s2 = operands
    {
        "name": "vfma_f32",
        "asm": "vfma.f32 s0, s1, s2",
        "entry": [0.5, 1.0, 2.0],
        "clobbers": '"s0", "s1", "s2"',
    },
    {
        "name": "vfms_f32",
        "asm": "vfms.f32 s0, s1, s2",
        "entry": [0.5, 1.0, 2.0],
        "clobbers": '"s0", "s1", "s2"',
    },
    {
        "name": "vfnma_f32",
        "asm": "vfnma.f32 s0, s1, s2",
        "entry": [0.5, 1.0, 2.0],
        "clobbers": '"s0", "s1", "s2"',
    },
    {
        "name": "vfnms_f32",
        "asm": "vfnms.f32 s0, s1, s2",
        "entry": [0.5, 1.0, 2.0],
        "clobbers": '"s0", "s1", "s2"',
    },

    # --- Unfused multiply-accumulate ---
    {
        "name": "vmla_f32",
        "asm": "vmla.f32 s0, s1, s2",
        "entry": [0.5, 1.0, 2.0],
        "clobbers": '"s0", "s1", "s2"',
    },
    {
        "name": "vmls_f32",
        "asm": "vmls.f32 s0, s1, s2",
        "entry": [0.5, 1.0, 2.0],
        "clobbers": '"s0", "s1", "s2"',
    },

    # --- Unary ---
    {
        "name": "vsqrt_f32",
        "asm": "vsqrt.f32 s0, s1",
        "entry": [0.0, 4.0],  # s0=don't care, s1=4.0 -> sqrt=2.0
        "clobbers": '"s0", "s1"',
    },
    {
        "name": "vabs_f32",
        "asm": "vabs.f32 s0, s1",
        "entry": [0.0, -3.0],
        "clobbers": '"s0", "s1"',
    },
    {
        "name": "vneg_f32",
        "asm": "vneg.f32 s0, s1",
        "entry": [0.0, 5.0],
        "clobbers": '"s0", "s1"',
    },

    # --- Conversion ---
    {
        "name": "vcvt_f32_s32",
        "asm": "vcvt.f32.s32 s0, s0",
        "entry_raw": [42],  # raw int32 bit pattern in s0
        "clobbers": '"s0"',
    },
    {
        "name": "vcvt_s32_f32",
        "asm": "vcvt.s32.f32 s0, s0",
        "entry": [3.75],
        "clobbers": '"s0"',
    },
    {
        "name": "vcvt_f32_u32",
        "asm": "vcvt.f32.u32 s0, s0",
        "entry_raw": [42],
        "clobbers": '"s0"',
    },
    {
        "name": "vcvt_u32_f32",
        "asm": "vcvt.u32.f32 s0, s0",
        "entry": [3.75],
        "clobbers": '"s0"',
    },
]


def gen_entry_init(spec):
    """Generate entry buffer initialization lines."""
    lines = []
    if "entry_raw" in spec:
        for i, val in enumerate(spec["entry_raw"]):
            lines.append(f"    entry_[{i}] = {val}u;")
    else:
        for i, val in enumerate(spec["entry"]):
            lines.append(f"    entry_[{i}] = {float_hex(val)};  // {val}f")
    return "\n".join(lines)


def gen_entry_load_asm(n_entry):
    """Generate vldr instructions to load entry regs from buffer."""
    lines = []
    for i in range(n_entry):
        lines.append(f'      "vldr.32 s{i}, [%0, #{i*4}]\\n\\t"')
    return "\n".join(lines)


def gen_test_file(spec):
    n_entry = len(spec.get("entry", spec.get("entry_raw")))
    name = spec["name"]
    asm_line = spec["asm"]
    clobbers = spec["clobbers"]
    entry_init = gen_entry_init(spec)
    entry_load = gen_entry_load_asm(n_entry)

    return f'''// Auto-generated by verification/gen/fpu_single.py — do not edit.
// Tests: {asm_line}

#include <cstdint>
#include <span>

#include <ento-bench/bench_config.h>
#include <ento-bench/harness.h>
#include <ento-bench/problem.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>

extern "C" void initialise_monitor_handles(void);

namespace {{

class BenchFpu_{name} : public EntoBench::EntoProblem<BenchFpu_{name}>
{{
public:
  static constexpr bool RequiresDataset_  = false;
  static constexpr bool SaveResults_      = false;
  static constexpr bool RequiresPrepare_  = true;

  bool deserialize_impl(const char*) {{ return true; }}
  static constexpr const char* header_impl() {{ return ""; }}
  bool validate_impl() const {{ return true; }}
  void clear_impl() {{}}

  void prepare_impl()
  {{
{entry_init}
    exit_[0] = 0;
    exit_[1] = 0;
    uint32_t fpscr_init = 0u;
    __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr_init));
  }}

  void solve_impl()
  {{
    __asm__ volatile(
{entry_load}
      "{asm_line}\\n\\t"
      "vstr.32 s0, [%1, #0]\\n\\t"
      "vmrs r0, fpscr\\n\\t"
      "str  r0, [%1, #4]\\n\\t"
      :
      : "r"(entry_), "r"(exit_)
      : {clobbers}, "r0", "memory"
    );
  }}

  EntoBench::ResultSig result_signature_impl() const
  {{
    const uint8_t* p = reinterpret_cast<const uint8_t*>(exit_);
    constexpr size_t n = sizeof(exit_);
    return EntoBench::ResultSig{{ .bytes = std::span<const uint8_t>{{p, n}} }};
  }}

private:
  alignas(8) uint32_t entry_[{n_entry}]{{}};
  alignas(8) uint32_t exit_[2]{{}};
}};

}}  // namespace

int main()
{{
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

  BenchFpu_{name} problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_fpu_{name}");
  harness.run();

  exit(0);
  return 0;
}}
'''


def gen_cmake_snippet(specs):
    """Generate CMake list for inclusion."""
    names = [f"bench-fpu-{s['name'].replace('_', '-')}" for s in specs]
    lines = ["set(FPU_CAPTURE_BENCHMARKS"]
    for n in names:
        lines.append(f"    {n}")
    lines.append(")")
    return "\n".join(lines)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for spec in INSTRUCTIONS:
        name = spec["name"]
        target_name = f"bench_fpu_{name}"
        filepath = OUT_DIR / f"{target_name}.cc"
        filepath.write_text(gen_test_file(spec))
        print(f"  wrote {filepath.relative_to(REPO_ROOT)}")

    # Print CMake snippet for copy-paste
    print()
    print("CMake target list (add to benchmark/microbench/CMakeLists.txt):")
    print(gen_cmake_snippet(INSTRUCTIONS))
    print()
    print(f"Generated {len(INSTRUCTIONS)} tests in {OUT_DIR.relative_to(REPO_ROOT)}/")


if __name__ == "__main__":
    main()

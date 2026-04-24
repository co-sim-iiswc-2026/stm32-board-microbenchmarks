# Differential Testing Framework

Infrastructure for catching FPU / instruction-decoder bugs by running the same
Thumb-2 binary on three targets (board, gem5, optionally FVP) and diffing
their captured output state.

## Why this exists

Zhantong's gem5 Cortex-M fork is suspected of mis-implementing one or more
VFPv4 instructions. TinyMPC converges on the real STM32G474 board but
diverges to NaN in gem5. This framework reproduces the bug in small,
bit-exact test binaries and narrows down which instruction(s) are broken.

**Status (2026-04-24):** root cause found — multi-d-register `vldmia`/`vstmia`
(e.g. `vldmia rN, {d0-d3}`) produces scrambled register↔memory mappings on
gem5. Single-d-reg and single-s-reg forms work. Zhantong has a minimal
reproducer (`bench-vldmia-d-range-capture` + `bench-vstmia-d-range-capture`)
and is fixing the decoder. See "Current findings" below.

## How it works

1. Each capture test is an STM32G474 binary that:
   - Runs a small kernel with known inputs in a controlled environment
     (FPSCR reset, bounds-checked entry state)
   - Captures a fixed-size byte snapshot of post-kernel state (register
     values, memory region, whatever the test cares about)
   - Emits one structured output line via semihosting printf:
     ```
     ENTO_RESULT name=<kernel_name> bytes=<hex_dump>
     ```
2. The **board** is the trusted reference — the same binary runs on real
   silicon and produces canonical output bytes.
3. The **gem5** binary runs the same ELF through the simulator and produces
   its own output.
4. `diff` between the two `ento_results.txt` files tells us which tests
   diverge → which instruction(s) are broken in gem5.

## Harness foundation

Uses the EntoBench harness (`external/ento-bench/src/ento-bench/`):
- `Harness<Problem>` calls `problem.prepare()` before each Reps iteration
  (outside ROI), then times `solve()` inside ROI, then calls
  `problem.result_signature()` and emits the `ENTO_RESULT` line.
- `CaptureProblem<Derived, ResultBytes>` base class (`capture_problem.h`) 
  provides boilerplate — just override `prepare_impl()` and `solve_impl()`,
  and fill `exit_[]`.
- Detection idiom via C++20 `requires` means the harness silently ignores
  the new hooks on legacy Problem classes (TinyMPC, EKF, etc.) that don't
  opt in — zero impact on existing benchmarks.

## Layout

```
verification/
├── README.md              # this file
├── gen/
│   ├── fpu_single.py      # generator: emits one .cc per FPU instruction
│   └── templates/         # (unused — generator uses f-strings directly)
├── logs/                  # sweep outputs (gitignored)
│   ├── board/             # board ento_results.txt + per-test .log files
│   └── gem5/              # gem5 m5out_<bench>/ + per-test logs
├── sweep_fpu_board.sh     # flash + log all capture/FPU tests on board
└── sweep_fpu_gem5.sh      # run all capture/FPU tests in gem5
                           #   default: FPU-only; --mpc to include TinyMPC
```

Hand-written capture tests live in `benchmark/microbench/bench_*_capture.cc`
(each is ~50-100 lines using `CaptureProblem`). Generated ones go in
`benchmark/microbench/generated/bench_fpu_*.cc` (regenerate via
`python3 verification/gen/fpu_single.py`).

## Running

### Board sweep (from your Mac with board attached)
```bash
./verification/sweep_fpu_board.sh
# produces verification/logs/board/ento_results.txt
```

### gem5 sweep (on BRG RHEL8 server)
```bash
./verification/sweep_fpu_gem5.sh           # FPU + capture tests only
./verification/sweep_fpu_gem5.sh --mpc     # also run TinyMPC variants
# produces verification/logs/gem5/ento_results.txt
```

### Diffing
Once you have both files:
```bash
diff verification/logs/board/ento_results.txt verification/logs/gem5/ento_results.txt
```
A clean diff means all tested instructions match between board and gem5.
Any delta is a gem5 bug candidate.

## Adding a new capture test

Minimal example — test a hypothetical instruction `vfoo`:

```cpp
// benchmark/microbench/bench_vfoo_capture.cc
#include <ento-bench/bench_config.h>
#include <ento-bench/capture_problem.h>
#include <ento-bench/harness.h>
#include <ento-mcu/clk_util.h>
#include <ento-mcu/systick_config.h>
#include <cstring>

extern "C" void initialise_monitor_handles(void);

class BenchVfoo : public EntoBench::CaptureProblem<BenchVfoo, 8>
{
public:
  void prepare_impl() {
    entry_[0] = 0x3f800000u;  // known input
    std::memset(exit_, 0, sizeof(exit_));
  }
  void solve_impl() {
    __asm__ volatile(
      "vldr.32 s0, [%0, #0]\n\t"
      "vfoo.f32 s0, s0\n\t"         // the instruction under test
      "vstr.32 s0, [%1, #0]\n\t"
      "vmrs r0, fpscr\n\t"
      "str r0, [%1, #4]\n\t"
      :
      : "r"(entry_), "r"(exit_)
      : "s0", "r0", "memory"
    );
  }
private:
  alignas(8) uint32_t entry_[1]{};
};

int main() {
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
  BenchVfoo problem;
  ENTO_BENCH_HARNESS_TYPE(decltype(problem));
  BenchHarness harness(problem, "bench_vfoo_capture");
  harness.run();
  exit(0);
  return 0;
}
```

Then:
1. Add `bench-vfoo-capture` to `CAPTURE_BENCHMARKS` in `benchmark/microbench/CMakeLists.txt`
2. Add `bench-vfoo-capture` to the `BENCHES` arrays in both sweep scripts
3. Rebuild, sweep, diff

For parameterized FPU instructions fitting the standard shape (single-op FPU
with 1-3 source regs → 1 dest reg), add a spec entry to `verification/gen/fpu_single.py`
and re-run it — generator emits the .cc automatically.

## Current findings (2026-04-24)

All 21 single-instruction FPU tests with clean inputs match bit-exactly
between board and gem5 (vadd, vsub, vmul, vdiv, vnmul, vfma, vfms, vfnma,
vfnms, vmla, vmls, vsqrt, vabs, vneg, vcvt.f32.s32, vcvt.s32.f32,
vcvt.f32.u32, vcvt.u32.f32, single-d-reg vldmia/vstmia with and without
writeback, vmov, vpush/vpop on single registers).

TinyMPC (`bench-tinympc-capture`) produces all-NaN u[0] on gem5 while the
board converges to (0.128, 0.115, 0.141, 0.149). `bench-matvec-12x12-capture`
causes gem5 itself to segfault in its instruction decoder.

The smoking gun: `bench-vldmia-d-range-capture` and
`bench-vstmia-d-range-capture` — `vldmia/vstmia rN, {d0-d3}` — produce
scrambled bytes on gem5 (wrong register↔memory mappings + 1 garbage slot)
where the board produces correct round-trip. Pattern is identical between
load and store → bug is in shared multi-d-reg register-list decode path.

These tests are the minimal reproducer for Zhantong.

## Design notes

See the project memory (`~/.claude/projects/.../memory/`) for the full design
history: why `prepare_impl` lives outside ROI, why we use memory-backed
capture instead of trying to pin register state across C function boundaries,
why we chose FNV-1a and then dropped it, etc. The short version: the harness
reads Problem state post-solve via `result_signature_impl`, which returns a
`std::span<const uint8_t>` into Problem-owned storage. Everything is
bit-deterministic and diff-friendly.

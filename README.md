# stm32-board-microbenchmarks

Microbenchmark and differential-testing infrastructure for the STM32G474RE
(Cortex-M4 + VFPv4-SP) board and Zhantong's gem5 cortex-m fork. Built on top
of the `ento-bench` harness (submodule at `external/ento-bench`).

## Repo layout

| Path | What's in it |
|---|---|
| `src/*.S` | Assembly-only microbenchmarks (NOP, ALU, FPU, branch, cache, etc.) — original cycle-measurement suite. Built via root `CMakeLists.txt`. |
| `benchmark/` | C++ benchmark suite using the EntoBench harness. Entry point: `benchmark/CMakeLists.txt` + `benchmark/CMakePresets.json`. Contains `microbench/`, `configs/`, `scripts/`. |
| `benchmark/microbench/` | Microbenchmark targets. Two categories: **cycle benchmarks** (`bench-<name>` via `microbench_main.cc`, JSON-configured via `configs/microbench.json`), and **capture benchmarks** (`bench-*-capture`, hand-written or generated, used for differential testing). |
| `verification/` | Differential-testing framework: capture test generator, board/gem5 sweep scripts, logs. See [`verification/README.md`](verification/README.md) for details. |
| `external/ento-bench/` | EntoBench submodule — provides the Harness, Problem base classes, ROI macros, and the `CaptureProblem<Derived, N>` primitive used by capture tests. |

## Build

**Board (STM32G474RE):**
```bash
cmake --preset stm32-g474re -S benchmark
cmake --build build-entobench -j
```

**gem5 (ARM Cortex-M simulation):**
```bash
cmake -B build-gem5 -S benchmark \
  -DCMAKE_TOOLCHAIN_FILE=external/ento-bench/stm32-cmake/stm32-g474re.cmake \
  -DGEM5_SEMIHOSTING=ON -DSTM32_BUILD=ON -DCMAKE_BUILD_TYPE=Release \
  -DMICROBENCH_CONFIG_FILE="configs/microbench_gem5.json"
cmake --build build-gem5 -j
```

On the BRG RHEL8 server, source `setup-brg.sh` first to load the ARM toolchain
module, then `cd benchmark` and use the `--preset stm32-g474re` form (paths
differ slightly — the preset's relative-path resolution requires running from
inside `benchmark/`).

## Flashing and running on the board

Per-benchmark flash-and-log targets are generated when OpenOCD is available:
```bash
make -C build-entobench stm32-flash-bench-nop-semihosted         # single bench
./verification/sweep_fpu_board.sh                                # all capture tests
```

Gem5 workflow is documented in [`verification/README.md`](verification/README.md).

## Testing changes

The `CaptureProblem`-based tests under `benchmark/microbench/bench_*_capture.cc`
each produce one `ENTO_RESULT name=<name> bytes=<hex>` line of semihosting
output. Board sweep captures these into `verification/logs/board/ento_results.txt`
as the trusted reference. The gem5 sweep produces the same format; `diff`
the two files to find divergences.

See [`verification/README.md`](verification/README.md) for the differential-testing
workflow and the ongoing gem5 FPU bug hunt context.

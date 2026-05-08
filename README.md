# stm32-board-microbenchmarks

Microbenchmark and differential-testing infrastructure for the STM32G474RE
(Cortex-M4 + VFPv4-SP) board and Zhantong's gem5 cortex-m fork. Built on top
of the `ento-bench` harness (submodule at `external/ento-bench`).

## Repo layout

| Path | What's in it |
|---|---|
| `src/*.S` | Assembly-only microbenchmarks (NOP, ALU, FPU, branch, cache, etc.) — original cycle-measurement suite. Built via root `CMakeLists.txt`. |
| `benchmark/` | C++ benchmark suite using the EntoBench harness. Entry point: `benchmark/CMakeLists.txt` + `benchmark/CMakePresets.json`. Contains `microbench/`, `configs/`, `scripts/`. |
| `benchmark/microbench/` | Microbenchmark targets. Two categories: **cycle benchmarks** (`bench-<name>` via `microbench_main.cc`, JSON-configured via `configs/microbench.json`), and **diff benchmarks** (`bench-<name>` for hand-written, `bench-fpu-<...>` for generated; both built on `CaptureProblem`, used for board↔gem5 differential testing). |
| `verification/` | Differential-testing framework: diff-test generators, board/gem5 sweep scripts, logs. See [`verification/README.md`](verification/README.md) for details. |
| `external/ento-bench/` | EntoBench submodule — provides the Harness, Problem base classes, ROI macros, and the `CaptureProblem<Derived, N>` primitive used by diff tests. |

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

**QEMU (qemu-system-arm, for trace-level ground truth without the board):**
```bash
cmake -B build-qemu -S benchmark \
  -DCMAKE_TOOLCHAIN_FILE=external/ento-bench/stm32-cmake/stm32-g474re.cmake \
  -DQEMU_SIM=ON -DSTM32_BUILD=ON -DCMAKE_BUILD_TYPE=Release -DFETCH_ST_SOURCES=ON \
  -DMICROBENCH_CONFIG_FILE="configs/microbench_gem5.json"
cmake --build build-qemu -j --target microbench-all
```

QEMU mode (`-DQEMU_SIM=ON`) builds the same firmware but with a few
small ifdef gates so the binary runs cleanly under
`qemu-system-arm -M olimex-stm32-h405`:

* `sys_clk_cfg()` / cache-enable / `ENTO_BENCH_SETUP()` are skipped —
  QEMU's Cortex-M4 model doesn't implement the STM32 RCC / FLASH
  accelerator peripherals, so the board's clock-init code would hang.
* `start_roi()` / `end_roi()` use `printf("[ROI BEGIN]\n")` /
  `printf("[ROI END]\n")` instead of gem5's m5op semihosting bkpts
  (which QEMU rejects with "Unsupported SemiHosting SWI 0x100").
* DWT cycle counters are not touched (also unsupported on the QEMU
  machine).

`ENTO_RESULT` still reaches stdout via standard ARM semihosting
(`SYS_WRITE`), which QEMU handles natively. To run a built ELF:

```bash
qemu-system-arm -M olimex-stm32-h405 \
    -kernel build-qemu/bin/bench-tinympc-diff-iter1.elf \
    -nographic -semihosting-config enable=on,target=native \
    -monitor none -serial null
```

The full QEMU-as-reference / per-instruction trace-diff workflow for
hunting gem5 bugs lives in [`verification/README.md`](verification/README.md).

On the BRG RHEL8 server, source `setup-brg.sh` first to load the ARM toolchain
module, then `cd benchmark` and use the `--preset stm32-g474re` form (paths
differ slightly — the preset's relative-path resolution requires running from
inside `benchmark/`).

## Flashing and running on the board

Per-benchmark flash-and-log targets are generated when OpenOCD is available:
```bash
make -C build-entobench stm32-flash-bench-nop-semihosted         # single bench
./verification/sweep_fpu_board.sh                                # all diff tests
```

Gem5 workflow is documented in [`verification/README.md`](verification/README.md).

## Testing changes

The `CaptureProblem`-based tests under `benchmark/microbench/bench_*.cc`
(plus `generated/bench_fpu_*.cc`) each produce one `ENTO_RESULT name=<name> bytes=<hex>`
line of semihosting output. Board sweep captures these into
`verification/logs/board/ento_results.txt`
as the trusted reference. The gem5 sweep produces the same format; `diff`
the two files to find divergences.

See [`verification/README.md`](verification/README.md) for the differential-testing
workflow and the ongoing gem5 FPU bug hunt context.

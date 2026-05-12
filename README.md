# stm32-board-microbenchmarks

Microbenchmark and differential-testing infrastructure for the
STM32G474RE (Cortex-M4 + VFPv4-SP) board and Zhantong's gem5 cortex-m
fork. Two independent subprojects, plus diff-testing glue.

## Repo layout

| Path | What's in it |
|---|---|
| [`microbenchmark/`](microbenchmark/) | **Low-overhead Cortex-M4 cycle harness.** Standalone CMake project — one cold warmup + `INNER_REPS` measured calls bracketed by DWT_CYCCNT snaps (hardware) or `m5_work_begin`/`m5_work_end` pairs (gem5). Same kernel source builds for both targets via a `PLATFORM={gem5,hardware}` + `BOARD={stm32g474re,...}` switch. Per-board resources (linker script, openocd target cfg, I/D-cache sizes, board headers) live in [`microbenchmark/board/<board>/`](microbenchmark/board/); a post-link guard fails the build when a kernel exceeds the target's I-cache or D-cache. See [`microbenchmark/README.md`](microbenchmark/README.md). |
| [`benchmark/`](benchmark/) | **C++ benchmark suite using the EntoBench harness.** Entry point: [`benchmark/CMakeLists.txt`](benchmark/CMakeLists.txt) + [`benchmark/CMakePresets.json`](benchmark/CMakePresets.json). Contains `microbench/`, `multibench/`, `configs/`, `scripts/`. Two categories of targets: **cycle benchmarks** (`bench-<name>` via `microbench_main.cc`, JSON-configured via `configs/microbench*.json`), and **diff benchmarks** (`bench-<name>` for hand-written, `bench-fpu-<...>` for generated; both built on `CaptureProblem`, used for board↔gem5 differential testing). |
| [`verification/`](verification/) | **Differential-testing framework** — diff-test generators, board/gem5 sweep scripts, logs. See [`verification/README.md`](verification/README.md). |
| [`external/ento-bench/`](external/ento-bench/) | **EntoBench submodule** — provides the Harness, Problem base classes, ROI macros, and the `CaptureProblem<Derived, N>` primitive used by diff tests. |

## microbenchmark/ — quick start

The smaller, newer subproject. Pure cycle measurement for one kernel
at a time, with cross-build byte-identity invariants so gem5↔hardware
comparisons are well-defined.

```bash
cd microbenchmark
cmake --preset hw-stm32g474re && cmake --build build/hw-stm32g474re -j4
python3 ./test/test_board_run.py
```

Presets follow the `<platform>[-<variant>]-<board>` convention:

| Preset | Platform | Board | Flash accelerators |
|---|---|---|---|
| `gem5-stm32g474re`           | gem5     | stm32g474re | n/a (configured in gem5 invocation) |
| `hw-stm32g474re`             | hardware | stm32g474re | I-cache + D-cache + prefetch all on |
| `hw-nocache-stm32g474re`     | hardware | stm32g474re | caches off, prefetch on |
| `hw-noprefetch-stm32g474re`  | hardware | stm32g474re | caches on, prefetch off |
| `hw-none-stm32g474re`        | hardware | stm32g474re | all off |

Full docs (memory layout, ROI design, byte-identity invariants,
I/D-cache size guards, adding a new kernel or board):
[`microbenchmark/README.md`](microbenchmark/README.md).

## benchmark/ — quick start

The original EntoBench-based suite (C++, `CaptureProblem`-driven,
shared with the differential-testing workflow).

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

**QEMU (qemu-system-arm, for trace-level ground truth without the
board):**
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

On the BRG RHEL8 server, source `setup-brg.sh` first to load the ARM
toolchain module, then `cd benchmark` and use the `--preset
stm32-g474re` form (paths differ slightly — the preset's relative-path
resolution requires running from inside `benchmark/`).

### Flashing and running on the board

Per-benchmark flash-and-log targets are generated when OpenOCD is
available:
```bash
make -C build-entobench stm32-flash-bench-nop-semihosted   # single bench
./verification/sweep_fpu_board.sh                          # all diff tests
```

Gem5 workflow is documented in
[`verification/README.md`](verification/README.md).

### Differential testing

The `CaptureProblem`-based tests under `benchmark/microbench/bench_*.cc`
(plus `generated/bench_fpu_*.cc`) each produce one
`ENTO_RESULT name=<name> bytes=<hex>` line of semihosting output. The
board sweep captures these into
`verification/logs/board/ento_results.txt` as the trusted reference.
The gem5 sweep produces the same format; `diff` the two files to find
divergences.

See [`verification/README.md`](verification/README.md) for the
differential-testing workflow and the ongoing gem5 FPU bug-hunt
context.

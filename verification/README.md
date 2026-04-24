# verification/

Run the same Thumb-2 binary on the STM32G474 board and Zhantong's gem5
Cortex-M fork, diff output, catch gem5 bugs.

## Current state (2026-04-24)

Multi-d-register `vldmia`/`vstmia` (e.g. `{d0-d3}`) scrambles
register↔memory mappings on gem5. Single-d-reg and single-s-reg forms are
fine. Minimal repros: `bench-vldmia-d-range-capture` + `bench-vstmia-d-range-capture`
(both have correct board baselines and scrambled gem5 output). Downstream:
`bench-matvec-12x12-capture` segfaults gem5's decoder, `bench-tinympc-capture`
produces all-NaN u[0]. Bug report sent to Zhantong; waiting on fix.

All 21 other single-instruction FPU tests match board and gem5 bit-exactly
with clean inputs.

## Running

```bash
# Mac with board attached
./verification/sweep_fpu_board.sh

# BRG server (source setup-brg.sh first)
./verification/sweep_fpu_gem5.sh          # FPU only (default)
./verification/sweep_fpu_gem5.sh --mpc    # include TinyMPC variants
```

Outputs: `verification/logs/{board,gem5}/ento_results.txt`. Diff them.
Each line is `ENTO_RESULT name=<bench> bytes=<hex>`.

## Layout

```
gen/fpu_single.py       generator for single-op FPU tests (spec list → .cc)
sweep_fpu_board.sh      flash each capture test, scrape ENTO_RESULT line
sweep_fpu_gem5.sh       same against gem5 via run_m5op_bench.py
logs/                   sweep outputs (gitignored)
```

Capture test binaries themselves live under `benchmark/microbench/`:
- `bench_*_capture.cc` — hand-written tests for one-off shapes (vldm/vstm
  variants, vpush/vpop, TinyMPC, matvec, etc.)
- `generated/bench_fpu_*.cc` — generator output, one per VFP instruction

## Adding a test

Copy `benchmark/microbench/bench_vmul_capture.cc` as a template. Your class
inherits from `EntoBench::CaptureProblem<Derived, N>` (in
`external/ento-bench/src/ento-bench/capture_problem.h`) — implement
`prepare_impl()` and `solve_impl()`, fill the inherited `exit_[]` byte
buffer, done.

Then register the new target:
1. Add to `CAPTURE_BENCHMARKS` in `benchmark/microbench/CMakeLists.txt`
2. Add to `BENCHES` in both sweep scripts

For parametric single-op FPU tests (one instruction, 1–3 source regs, 1
destination), add a spec to `verification/gen/fpu_single.py` and re-run
the script — the `.cc` is emitted automatically.

## Output format

One line per test:
```
ENTO_RESULT name=<bench_name> bytes=<hex>
```
Bytes are the post-kernel snapshot the test captures (registers, memory,
whatever is relevant). Format choice: 58-char line for our typical 8-byte
payload, short enough for semihosting throughput, easy to `diff`.

Emitted by `Harness::print_ento_result()` after `problem.result_signature()`
returns a `std::span<const uint8_t>` over Problem-owned storage. Board is
the reference — no Python oracle, no IEEE-754 simulator. If you need a new
fact about what's "correct," run on board first.

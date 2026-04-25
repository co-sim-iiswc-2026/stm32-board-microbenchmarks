# verification/

Run the same Thumb-2 binary on the STM32G474 board and Zhantong's gem5
Cortex-M fork, diff output, catch gem5 bugs.

## Current state (2026-04-25)

Diff suite is fully green against Zhantong's gem5 fork. Latest sweep
(`sweep_fpu_gem5.sh --mpc` + `diff_gem5_vs_board.sh`):

```
Summary: 72 tests total | 71 match | 0 diverge | 0 board-only | 1 gem5-only
```

The lone gem5-only test is `bench_matvec_12x12` (excluded from
`board_reference.txt` by historical scope); it's bit-exact against
QEMU as a sanity check.

Coverage:

- **Single-op FPU tests** — one VFP instruction per test
  (vadd/vsub/vmul/vdiv/vfma/vfms/vfnma/vfnms/vmla/vmls/vsqrt/vabs/
  vneg/vcvt/vcmp). Catches per-encoding decoder bugs.
- **Hand-written diff benches** — vldm/vstm variants (single-d, d-pair,
  d-range, vldmia-d7wb writeback), vmov, vpush/vpop, vcmpe-vmovcond,
  matvec-12x12, preamble-zeroing variants. Cover load/store-multiple,
  conditional predicated moves, and end-to-end MPC.
- **Level A — repeated single instruction** (20 tests, `gen/fpu_repeat.py`):
  same VFP op run N× in one asm block, threaded output→input.
- **Level B — random VFP sequences** (16 tests, 8 seeds × {n10, n20},
  `gen/fpu_seq.py`): random instructions over s0..s15 with seeded
  operands. Manifest at `gen/fpu_seq_manifest.txt`.
- **TinyMPC iteration variants** (`bench-tinympc-diff` + iter{0,1,5,20,
  50}): bisect ADMM convergence. iter1/5 show real ADMM progression;
  iter20+ converge to `5211033e16c1eb3d5cd30f3e935e183e`. Every variant
  bit-matches the board.

ART-on vs ART-off produces identical signatures (timing-only).

## Running

Build just the microbench targets (avoids pulling in unrelated
currently-broken ento-bench tests):

```bash
# Mac (board build)
cmake --build build-entobench --target microbench-all -j

# BRG server (gem5 build, see top-level README for configure step)
cmake --build ../build-gem5 --target microbench-all -j
```

Then sweep:

```bash
# Mac with board attached
./verification/sweep_fpu_board.sh

# BRG server
./verification/sweep_fpu_gem5.sh          # FPU only (default)
./verification/sweep_fpu_gem5.sh --mpc    # include TinyMPC variants
```

Outputs: `verification/logs/{board,gem5}/ento_results.txt`. Diff them.
Each line is `ENTO_RESULT name=<bench> bytes=<hex>`.

For a structured diff (handles FLASH_FAILED / GEM5_FAILED statuses, name
normalization, clear per-test divergence output):

```bash
# No-arg: diffs verification/logs/gem5/ento_results.txt (latest sweep)
# against the committed board baseline at verification/board_reference.txt.
# Works on any host with the repo checked out — no scp required.
./verification/diff_gem5_vs_board.sh

# Explicit paths, useful for diffing two fresh sweeps on one host:
./verification/diff_gem5_vs_board.sh <board_log> <gem5_log>
```

`verification/board_reference.txt` is the committed board baseline, scoped
to FPU tests only (tinympc + matvec are excluded — they depend on the known
multi-d-reg vldmia bug). Refresh deliberately after a board sweep you've
verified:
```bash
grep -vE '(tinympc|matvec)' verification/logs/board/ento_results.txt \
  > verification/board_reference.txt.new
# then prepend the header comment, replace the old file, and commit
```

Each sweep also preserves history under
`verification/logs/{board,gem5}/runs/<git-sha>-<utc-timestamp>/`
(per-run summary + per-test logs). The top-level `ento_results.txt` is a
symlink to the latest run, as is `latest/`. One-line provenance per run is
appended to `runs.log` in the same directory.

## For gem5 model developers (no board needed)

If you're iterating on Zhantong's cortex-m gem5 fork and want to check a
change against real silicon, you don't need a board — the committed
`verification/board_reference.txt` is the oracle.

```bash
git pull                                        # get latest reference
cmake --build <your-gem5-build> --target microbench-all -j

# GEM5_BIN and GEM5_SCRIPT default to /work/global/ddo26/gem5/... —
# override to point at your own build + run script.
GEM5_BIN=/path/to/your/gem5.opt \
GEM5_SCRIPT=/path/to/gem5/run_m5op_bench.py \
  ./verification/sweep_fpu_gem5.sh

./verification/diff_gem5_vs_board.sh            # structured diff
```

Exit code = count of divergent+missing tests (capped at 255), so you can
wire this into a pre-merge check. Scope is FPU only; TinyMPC and matvec
are excluded from the reference (they depend on the known multi-d-reg
vldmia bug). Opt-in to TinyMPC locally with `sweep_fpu_gem5.sh --mpc`
if you want to compare those too.

## Validating gem5 against QEMU (no board needed)

`qemu-system-arm`'s Cortex-M4 model uses Berkeley-derived softfloat
configured for IEEE-754 binary32, and on every FPU test in this
suite it produces **bit-exact** output to the real STM32G474 FPU (we
verified 24/24 random `bench_fpu_mixed_*` sequences and the full
single-op set match the Python reference, which the board also
matches). That makes QEMU a portable oracle when:

* you want to iterate on gem5 without flashing the board, **and**
* the benchmark is computational (CPU-side FP/integer; QEMU does
  not model timing or STM32 peripherals beyond what
  `-M olimex-stm32-h405` exposes).

Build the QEMU firmware once (see top-level [`README.md`](../README.md)):
```bash
cmake -B build-qemu -S benchmark \
  -DCMAKE_TOOLCHAIN_FILE=external/ento-bench/stm32-cmake/stm32-g474re.cmake \
  -DQEMU_SIM=ON -DSTM32_BUILD=ON -DCMAKE_BUILD_TYPE=Release -DFETCH_ST_SOURCES=ON \
  -DMICROBENCH_CONFIG_FILE="configs/microbench_gem5.json"
cmake --build build-qemu -j --target microbench-all
```

Then capture a per-test signature and diff against the gem5 sweep:

```bash
# 1) QEMU reference for one test
qemu-system-arm -M olimex-stm32-h405 \
    -kernel build-qemu/bin/bench-tinympc-diff-iter1.elf \
    -nographic -semihosting-config enable=on,target=native \
    -monitor none -serial null \
  | grep '^ENTO_RESULT'
# → ENTO_RESULT name=bench_tinympc_diff_iter1 bytes=c5a5d33d36cdbf3df4b4e63da669f33d

# 2) Same test under gem5 (use the m5op-instrumented build-gem5 ELF)
<gem5.opt> -re --outdir=m5out_iter1 <run_m5op_bench.py> \
    --firmware build-gem5/bin/bench-tinympc-diff-iter1.elf \
    --no-art --run-to-exit
grep '^ENTO_RESULT' m5out_iter1/simout.txt
```

Bit-identical `bytes=` fields → gem5 is correct on that test. A
mismatch is a gem5 bug.

### Bisecting a gem5 mismatch with a per-instruction trace

When the `ENTO_RESULT` bytes differ between gem5 and QEMU, the
fastest way to find the bug is to compare the two simulators
instruction-by-instruction inside the kernel and locate the first
divergent register write.

The general flow:

1. **Pick a function to trace.** Start at the kernel boundary (e.g.
   the function called from inside the ROI) so the trace is bounded.
   Find its symbol and address with `objdump` or `nm`:
   ```bash
   arm-none-eabi-nm build-qemu/bin/<bench>.elf  | grep <function>
   arm-none-eabi-nm build-gem5/bin/<bench>.elf  | grep <function>
   ```
   Note both addresses — they will differ slightly (the two builds
   have different `main()` setup code, so all symbols are shifted by
   a constant offset). Align comparisons by *symbol-relative offset*,
   not absolute PC.

2. **Capture gem5's instruction trace.** Run the gem5-mode ELF with
   the `Exec` debug flag enabled inside the ROI. The standard runner
   does this when m5_work_begin/end fire; the simout will contain
   per-instruction lines of the form:
   ```
   <tick>: system.cpu: T0 : 0x<pc> @<symbol>+<offset> : <instr> : <type> :  D=0x<dest> [A=0x<addr>]
   ```
   `D=` is the destination register's new value (or, for
   flag-setting / store ops, gem5's internal effect — see caveats
   below).

3. **Capture QEMU's instruction trace via the gdb stub.** Launch
   QEMU halted, drive single-stepping from gdb:
   ```bash
   # terminal A — QEMU halted with gdb stub on :1234
   qemu-system-arm -M olimex-stm32-h405 \
       -kernel build-qemu/bin/<bench>.elf \
       -nographic -semihosting-config enable=on,target=native \
       -monitor none -serial null \
       -gdb tcp::1234 -S

   # terminal B — gdb (note: armv7e-m for Cortex-M4)
   gdb-multiarch -batch \
       -ex "set pagination off" -ex "set confirm off" \
       -ex "set architecture armv7e-m" \
       -ex "file build-qemu/bin/<bench>.elf" \
       -ex "target remote :1234" \
       -ex "break <function>" \
       -ex "continue" \
       -ex "source trace_helper.py" \
       -ex "trace_steps <N> qemu_trace.log"
   ```
   `trace_helper.py` is a few-line gdb-Python module that single-
   steps N times and writes one line per step (PC, R0–R15, S0–S31,
   FPSCR). Sketch:
   ```python
   import gdb, struct
   def u32(name):
       v = gdb.parse_and_eval("$" + name)
       if str(v.type) == "float":
           return struct.unpack("<I", struct.pack("<f", float(v)))[0]
       return int(v) & 0xFFFFFFFF
   class TraceSteps(gdb.Command):
       def __init__(self): super().__init__("trace_steps", gdb.COMMAND_USER)
       def invoke(self, arg, _):
           parts = arg.split()
           n, path = int(parts[0]), (parts[1] if len(parts) > 1 else "qemu_trace.log")
           with open(path, "w") as out:
               for _ in range(n + 1):
                   row = [f"PC={u32('pc'):08x}"]
                   row += [f"R{i:02d}={u32(f'r{i}'):08x}" for i in range(13)]
                   row += [f"SP={u32('sp'):08x}", f"LR={u32('lr'):08x}"]
                   row += [f"S{i:02d}={u32(f's{i}'):08x}" for i in range(32)]
                   row += [f"FPSCR={u32('fpscr'):08x}"]
                   out.write(" ".join(row) + "\n")
                   gdb.execute("stepi", to_string=True)
   TraceSteps()
   ```

4. **Walk both traces in lockstep, aligning by symbol+offset.**
   Subtract `gem5_symbol_addr - qemu_symbol_addr` to get a constant
   delta; the same instruction lives at `gem5_pc` in one trace and
   `gem5_pc - delta` in the other. For each gem5 line, find the
   QEMU step whose PC matches (post-delta), then compare:
   * the destination register named in the gem5 instruction text vs.
     QEMU's after-state for that register, and
   * for FP ops, gem5's `D=0x<bits>` against QEMU's `S<n>` after the
     instruction.
   First instruction where they diverge is your gem5 bug.

#### Gotchas

* **Skip Cortex-M handler frames in the QEMU trace.** Under
  `-singlestep`, QEMU may fire the SysTick interrupt and execute the
  handler in the middle of your kernel; gem5 typically does not.
  Detect handler-mode steps by the `XPSR=...` line ending in
  `T handler` (vs. `T priv-thread`) and skip those rows when
  diffing. Alternatively, gate `__enable_irq()` in the bench's
  `main()` behind `#if !defined(QEMU_SIM)` so the timer never fires.

* **Stack-pointer offset.** The two builds may set up slightly
  different stack frames before reaching the kernel (e.g. the QEMU
  build's `main()` has a few less instructions of init). Comparing
  `SP` directly will look like a constant ~8-byte mismatch; ignore
  it. Computed values that flow through the FPU are unaffected.

* **gem5 `D=` field is an artifact for flag-setting integer ops.**
  For `movs`/`adds`/`cmps`/etc. the `D=` value reflects gem5's
  internal flag encoding, not the destination register's new value.
  Cross-check via the *next* non-flag-setting instruction that
  consumes the same register, or just trust the integer side once
  the FP side has a clean alignment.

* **gdb single-step is slow.** Each `stepi` is a round-trip to the
  QEMU stub; a 30 K-instruction trace takes a couple of minutes.
  Bound the trace with a small `N` first to validate the pipeline,
  then crank up.

## Layout

```
gen/fpu_single.py       single-op FPU test generator (spec list → .cc)
gen/fpu_repeat.py       Level A: repeated-instruction test generator
gen/fpu_seq.py          Level B: random-sequence test generator
gen/fpu_seq_manifest.txt    Level B seed → entry values → instruction sequence
gen/check.sh            sanity-check: generators reproduce committed output
sweep_fpu_board.sh      flash each diff test, scrape ENTO_RESULT line
sweep_fpu_gem5.sh       same against gem5 via run_m5op_bench.py
logs/                   sweep outputs (gitignored)
```

Diff-test binaries live under `benchmark/microbench/`:
- `bench_*.cc` — hand-written tests for one-off shapes (vldm/vstm
  variants, vpush/vpop, TinyMPC, matvec, preamble-zeroing variants)
- `generated/bench_fpu_*.cc` — generator output (single-op, repeat, and
  random-sequence categories; one file per test)

## Adding a test

Copy `benchmark/microbench/bench_vmul.cc` as a template. Your class
inherits from `EntoBench::CaptureProblem<Derived, N>` (in
`external/ento-bench/src/ento-bench/capture_problem.h`) — implement
`prepare_impl()` and `solve_impl()`, fill the inherited `exit_[]` byte
buffer, done.

Then register the new target:
1. Add to `HANDWRITTEN_BENCHMARKS` in `benchmark/microbench/CMakeLists.txt`
2. Add to `BENCHES` in both sweep scripts

For parametric tests, extend the appropriate generator and re-run it —
the `.cc` files are emitted automatically and picked up by CMake's
`file(GLOB)`:
- `gen/fpu_single.py` — single VFP op, 1–3 source regs, 1 destination
- `gen/fpu_repeat.py` — one VFP op repeated N× (add ops / N values)
- `gen/fpu_seq.py` — random VFP sequence (add seeds / lengths / catalog ops)

After regenerating, run `gen/check.sh` to confirm output is still
byte-deterministic (useful before committing generator changes).

## Output format

One line per test:
```
ENTO_RESULT name=<bench_name> bytes=<hex>
```
Bytes are the post-kernel snapshot the test captures (registers, memory,
whatever is relevant). Payload sizes vary by test shape: 8 B for
single-op FPU tests (s0 + FPSCR), 132 B for Level A/B and preamble tests
(s0..s31 + FPSCR), and a few tens of bytes for the hand-written
vldm/vstm/matvec variants.

Emitted by `Harness::print_ento_result()` after `problem.result_signature()`
returns a `std::span<const uint8_t>` over Problem-owned storage. Board is
the reference — no Python oracle, no IEEE-754 simulator. If you need a new
fact about what's "correct," run on board first.

# microbenchmark/test

Python smoke tests for the harness. Five scripts, each runnable on its own:

| Script                       | What it checks                                  | Board required? |
|------------------------------|-------------------------------------------------|-----------------|
| `test_build_all.py`          | All 4 hardware presets + gem5 configure & build, `_bench_body_start = 0x08000480` everywhere | no |
| `test_layout_identical.py`   | Kernel body bytes (`0x08000480 .. _bench_body_end`) hash to the same SHA-256 across all 4 hardware variants, and `kernel_body` matches across all 5 builds | no |
| `test_disassembly.py`        | Dumps full / `.bench_kernel` / `.text` disassembly + `nm` symbols per preset to `test/disasm/<preset>/`, plus cross-build diffs to `test/disasm/diff_*.txt` for visual inspection | no |
| `test_board_run.py`          | Flash one preset's ELF to the STM32G474RE via OpenOCD, capture semihosting output, parse every `MICROBENCH name=<bench> rep=<i> inner=N` line, write the **average** inner cycles to `test/logs/<preset>/<bench>.cycles.txt` | **yes** |
| `test_board_run_all.py`      | Wrapper that runs `test_board_run.py` for each of `hw-stm32g474re`, `hw-nocache-stm32g474re`, `hw-noprefetch-stm32g474re`, `hw-none-stm32g474re` and writes `test/logs/<bench>.summary.txt` with one row per variant (avg) | **yes** |

Wrapper `run_all_tests.py` runs all of them in order; the board stage auto-skips if no ST-Link is visible to `lsusb`, or with `--no-board`.

Shared helpers live in [`_common.py`](_common.py) (paths, toolchain
resolution, build / ELF / hash helpers, `lsusb` check).

## Usage

From the `microbenchmark/` directory (or anywhere — the scripts resolve their own paths):

```bash
python3 ./test/run_all_tests.py                          # all stages
python3 ./test/run_all_tests.py --no-board               # skip stage 4 explicitly
python3 ./test/test_build_all.py                         # builds only
python3 ./test/test_layout_identical.py                  # layout invariant (needs builds first)
python3 ./test/test_disassembly.py                       # dump test/disasm/<preset>/*.dis artifacts
python3 ./test/test_board_run.py                                          # flash + run, preset=hw-stm32g474re bench=bench_nop16_100
python3 ./test/test_board_run.py hw-nocache-stm32g474re                   # different variant
python3 ./test/test_board_run.py hw-stm32g474re bench_<your>              # different kernel
python3 ./test/test_board_run.py --timeout-s 30 hw-stm32g474re            # longer OpenOCD timeout
python3 ./test/test_board_run_all.py                     # sweep all 4 hw variants, write summary
python3 ./test/test_board_run_all.py bench_<your>        # same sweep, different kernel
```

Board-run artifacts (per kernel name, per variant):

```
test/logs/<variant>/<bench>.log         # full OpenOCD output
test/logs/<variant>/<bench>.cycles.txt  # single integer: average inner cycles
test/logs/<bench>.summary.txt           # variant × avg table
```

After `test_disassembly.py`, useful files to read:

```
test/disasm/<preset>/bench_nop16_100.full.dis              # whole ELF
test/disasm/<preset>/bench_nop16_100.bench_kernel.dis      # just the pinned kernel section
test/disasm/<preset>/bench_nop16_100.text.dis              # harness + main + startup
test/disasm/<preset>/bench_nop16_100.symbols.txt           # `nm -n` listing
test/disasm/diff_bench_kernel.txt                            # pairwise diffs of .bench_kernel
test/disasm/diff_apply_flash_acr.txt                         # apply_flash_acr() per hw variant
```

## Board run prerequisites

The ST-Link on the Nucleo board must be visible inside WSL:

```bash
lsusb | grep -i ST-LINK
# Bus 002 Device 003: ID 0483:374b STMicroelectronics ST-LINK/V2.1
```

If empty, re-attach from a Windows admin PowerShell:

```powershell
usbipd list                            # find the ST-Link bus-id
usbipd attach --wsl --busid <id>
```

(One-time bind setup is documented in [../README.md](../README.md#one-time-wsl-setup).)

## How `test_board_run.py` terminates

OpenOCD is launched with a hard `--timeout-s` (default 15 s) and stays
attached as long as it takes. Semihosting output is streamed to the
log file as the target produces it. When the timeout fires, OpenOCD
is killed; the script then parses the log for every `MICROBENCH
name=<bench> rep=<i> inner=N` line. Exit codes 124 (timeout) and 143
(SIGTERM) are treated as expected termination.

The script answers "did the harness execute end-to-end?", not "is the
cycle count the right number?". For tight cycle-budget assertions,
write a per-kernel check that reads `test/logs/<preset>/<bench>.cycles.txt`.

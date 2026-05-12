#!/usr/bin/env python3
"""
test_board_run.py — flash <bench>.elf for a single preset to the
STM32G474RE board via OpenOCD, capture semihosting output, parse the
per-rep cycle counts, average them, and persist the full OpenOCD log
under test/logs/<preset>/.

Requires:
  - usbipd-attached ST-Link inside WSL (see README "One-time WSL setup")
  - openocd in PATH
  - <bench>.elf built for the given preset (auto-built if missing)

The harness runs one cold warmup call followed by INNER_REPS measured
calls; each measured call emits its own line:

    MICROBENCH name=<bench> rep=<i> inner=<N>

The headline number is the **average** inner cycles across all reps.

Artifacts:
  test/logs/<preset>/<bench>.log         — full OpenOCD output
  test/logs/<preset>/<bench>.cycles.txt  — single integer: average inner cycles

Usage:
  python3 ./test/test_board_run.py
  python3 ./test/test_board_run.py hw-nocache-stm32g474re
  python3 ./test/test_board_run.py hw-stm32g474re bench_<other>
  python3 ./test/test_board_run.py --timeout-s 30 hw-stm32g474re bench_<other>
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

from _common import (
    DEFAULT_BENCH, LOGS, ROOT, ensure_build, fail, stlink_visible,
)


# Per-rep line: MICROBENCH name=<bench> rep=<i> inner=<N>
REP_RE = re.compile(
    r"MICROBENCH\s+name=(\S+)\s+rep=(\d+)\s+inner=(\d+)"
)


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="Flash + run one preset on the STM32G474RE board.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("preset", nargs="?", default="hw-stm32g474re",
                    help="CMake preset to flash (default: %(default)s)")
    ap.add_argument("bench", nargs="?", default=DEFAULT_BENCH,
                    help="Benchmark ELF name without .elf (default: %(default)s)")
    ap.add_argument("--timeout-s", type=int, default=15,
                    help="OpenOCD attach timeout in seconds (default: %(default)s)")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    preset = args.preset
    bench  = args.bench
    timeout_s = args.timeout_s

    elf = ensure_build(preset, bench)

    if not stlink_visible():
        sys.stderr.write(
            "  FAIL: No ST-Link visible to lsusb. From PowerShell on the Windows host:\n"
            "        usbipd list                          # find ST-Link bus-id\n"
            "        usbipd attach --wsl --busid <id>     # re-attach to WSL\n"
            "        Then re-run this test.\n"
        )
        return 1

    log_dir = LOGS / preset
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"{bench}.log"
    cyc_file = log_dir / f"{bench}.cycles.txt"

    print(f"==> Flashing {elf} and capturing semihosting output "
          f"(timeout {timeout_s}s) ...")
    print("    (target halts on completion; OpenOCD prints semihosting "
          "output as the kernel runs)")

    # The probe config (stlink.cfg) is at the project root because the
    # ST-Link probe is not board-specific; the target config (openocd.cfg)
    # lives under board/<board>/. Derive <board> from the preset name —
    # preset convention: `gem5-<board>` or `hw[-<variant>]-<board>`.
    if preset.startswith("gem5-"):
        board_name = preset[len("gem5-"):]
    else:
        # hw-<board> or hw-<variant>-<board>; assume the last "-" splits
        # variant from board. With a single board today the simpler
        # heuristic is also fine: strip the leading "hw-" and treat the
        # rest as either "<variant>-<board>" or just "<board>".
        rest = preset[len("hw-"):] if preset.startswith("hw-") else preset
        # If there's a dash, the trailing component is the board; otherwise
        # the entire rest is the board name.
        if "-" in rest:
            # Find the longest suffix that exists as a board/ directory.
            # In practice today there's only stm32g474re, so this is just
            # "everything after the last hyphen". Future boards may need a
            # smarter heuristic (e.g. read BOARD from the CMake cache).
            board_name = rest.rsplit("-", 1)[-1]
            # Special-case: rsplit of "noprefetch-stm32g474re" gives
            # "stm32g474re" already, which is right. But if a board name
            # contains a hyphen we'd need to look it up properly.
        else:
            board_name = rest

    openocd_cmd = [
        "openocd",
        "-f", str(ROOT / "openocd" / "stlink.cfg"),
        "-f", str(ROOT / "board" / board_name / "openocd.cfg"),
        "-c", "init",
        "-c", "reset",
        "-c", "halt",
        "-c", "arm semihosting enable",
        "-c", f"program {elf} verify",
        "-c", "reset run",
    ]

    try:
        with log_file.open("w") as f:
            proc = subprocess.run(
                openocd_cmd, cwd=ROOT, timeout=timeout_s,
                stdout=f, stderr=subprocess.STDOUT, check=False,
            )
        rc = proc.returncode
    except subprocess.TimeoutExpired:
        # OpenOCD doesn't auto-exit after `reset run` — the timeout is
        # the normal termination path. Semihosting output has been
        # written to the log as the target produced it.
        rc = 124

    if rc not in (0, 124, 143):
        sys.stderr.write("--- openocd output ---\n")
        sys.stderr.write(log_file.read_text())
        sys.stderr.write("--- end ---\n")
        fail(f"openocd exited with status {rc}")

    log_text = log_file.read_text()
    reps: list[tuple[int, int, str]] = []   # (rep_idx, inner_cyc, raw_line)
    for raw in log_text.splitlines():
        m = REP_RE.search(raw)
        if m and m.group(1) == bench:
            reps.append((int(m.group(2)), int(m.group(3)), raw.strip()))

    if not reps:
        sys.stderr.write("--- openocd output ---\n")
        sys.stderr.write(log_text)
        sys.stderr.write("--- end ---\n")
        fail(f"no 'MICROBENCH name={bench} rep=... inner=...' line in OpenOCD log")
        return 1  # unreachable

    # Preserve rep order (the kernel emits rep 0..N-1 sequentially) and
    # compute the average as the headline metric.
    reps.sort(key=lambda r: r[0])
    inners = [c for _, c, _ in reps]
    avg = round(sum(inners) / len(inners))

    # cycles.txt holds the single headline number — the average.
    cyc_file.write_text(f"{avg}\n")

    print(f"  observed: {len(reps)} rep(s)")
    for idx, cyc, raw in reps:
        print(f"    rep={idx:>2}  inner={cyc}   ({raw})")
    print(f"  log:      {log_file}")
    print(f"  cycles:   {cyc_file}  (avg={avg})")

    print()
    print(f"Board run OK ({preset} / {bench}): {len(reps)} reps, "
          f"avg={avg} (min={min(inners)} max={max(inners)}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())

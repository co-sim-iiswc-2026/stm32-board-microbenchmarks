#!/usr/bin/env python3
"""
test_board_run_all.py — sweep through all hardware variants on the
board for a given kernel, persist each run's full OpenOCD log, and emit
a summary table.

Each variant produces one MICROBENCH line per inner rep; the summary
shows the per-variant **average** inner cycles (headline metric). The
full per-rep log lives in test/logs/<variant>/<bench>.log; the average
is in test/logs/<variant>/<bench>.cycles.txt.

Artifacts:
  test/logs/<variant>/<bench>.log         — full OpenOCD output per run
  test/logs/<variant>/<bench>.cycles.txt  — single integer: average inner
  test/logs/<bench>.summary.txt           — variant × avg table

Usage:
  python3 ./test/test_board_run_all.py
  python3 ./test/test_board_run_all.py bench_<other>
  python3 ./test/test_board_run_all.py --timeout-s 30 bench_<other>

Behaviour on failure:
  Each variant is attempted independently. A failure on one variant
  does NOT abort the others; the summary records "FAIL" for that row.
  Exit code: 0 if all passed, 1 if any failed.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from _common import DEFAULT_BENCH, HW_PRESETS, LOGS, ROOT, stlink_visible


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="Sweep all hardware variants for a given kernel.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("bench", nargs="?", default=DEFAULT_BENCH,
                    help="Benchmark ELF name without .elf (default: %(default)s)")
    ap.add_argument("--timeout-s", type=int, default=15,
                    help="OpenOCD attach timeout in seconds (default: %(default)s)")
    return ap.parse_args()


def _read_avg(cyc_file: Path) -> str:
    """cycles.txt holds the average as a single integer."""
    return cyc_file.read_text().strip()


def main() -> int:
    args = parse_args()
    bench = args.bench
    timeout_s = args.timeout_s

    if not stlink_visible():
        sys.stderr.write(
            "FAIL: No ST-Link visible to lsusb. From PowerShell on the Windows host:\n"
            "      usbipd list                          # find ST-Link bus-id\n"
            "      usbipd attach --wsl --busid <id>     # re-attach to WSL\n"
            "      Then re-run.\n"
        )
        return 1

    LOGS.mkdir(parents=True, exist_ok=True)
    summary_file = LOGS / f"{bench}.summary.txt"

    # Columns: variant | avg | log
    summary_rows: list[tuple[str, str, str]] = []
    summary_rows.append(("variant", "avg", "log"))
    summary_rows.append(("-------", "---", "---"))

    test_run = Path(__file__).parent / "test_board_run.py"

    overall_rc = 0
    for v in HW_PRESETS:
        print(f"\n=== {v} ===")
        res = subprocess.run(
            ["python3", str(test_run),
             "--timeout-s", str(timeout_s),
             v, bench],
            cwd=ROOT, check=False,
        )
        cyc_file = LOGS / v / f"{bench}.cycles.txt"
        log_file = LOGS / v / f"{bench}.log"

        if res.returncode == 0 and cyc_file.exists():
            avg = _read_avg(cyc_file)
        else:
            overall_rc = 1
            avg = "FAIL"
        summary_rows.append((v, avg, str(log_file)))

    # Write summary file. Column width sized for the longest expected
    # preset name (e.g. "hw-noprefetch-stm32g474re" = 25 chars).
    lines = [
        f"{v:<26}  {avg:>6}  {log}"
        for v, avg, log in summary_rows
    ]
    summary_file.write_text("\n".join(lines) + "\n")

    print(f"\n========== summary ({bench}) ==========")
    print("\n".join(lines))
    print(f"\nPer-variant average:  test/logs/<variant>/{bench}.cycles.txt")
    print(f"Full logs:            test/logs/<variant>/{bench}.log")
    print(f"Summary:              test/logs/{bench}.summary.txt")

    return overall_rc


if __name__ == "__main__":
    sys.exit(main())

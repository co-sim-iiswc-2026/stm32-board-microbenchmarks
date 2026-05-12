#!/usr/bin/env python3
"""
run_all_tests.py — run the test suite in order.

Stages:
  1. test_build_all          — configure & build all hardware presets (no board)
  2. test_layout_identical   — body bytes byte-identical across builds (no board)
  3. test_disassembly        — dump disasm artifacts (no board)
  4. test_board_run_all      — flash + run on STM32G474RE (REQUIRES board)

Stage 4 is skipped automatically if no ST-Link is visible to lsusb, or
explicitly via --no-board.

Usage:
  python3 ./test/run_all_tests.py
  python3 ./test/run_all_tests.py --no-board
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from _common import stlink_visible


HERE = Path(__file__).resolve().parent


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description="Run the microbenchmark test suite in order.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--no-board", action="store_true",
                    help="Skip stage 4 (board flash+run) even if an ST-Link is visible.")
    return ap.parse_args()


def run_stage(label: str, script_name: str, args: list[str] | None = None) -> int:
    print()
    print("=" * 57)
    print(f"   {label}")
    print("=" * 57)
    res = subprocess.run(
        ["python3", str(HERE / script_name), *(args or [])],
        check=False,
    )
    if res.returncode != 0:
        print(f"\n>>> {label} FAILED (exit {res.returncode})", file=sys.stderr)
    return res.returncode


def main() -> int:
    args = parse_args()

    if rc := run_stage("[1/4] Build all presets", "test_build_all.py"):
        return rc
    if rc := run_stage("[2/4] Layout-identical check", "test_layout_identical.py"):
        return rc
    if rc := run_stage("[3/4] Disassembly artifact dump", "test_disassembly.py"):
        return rc

    if args.no_board:
        print("\n[4/4] Board run skipped (--no-board).")
        return 0

    if not stlink_visible():
        print("\n[4/4] Board run skipped (no ST-Link visible — usbipd not attached?).")
        return 0

    if rc := run_stage("[4/4] Board run — sweep all hw variants",
                       "test_board_run_all.py"):
        return rc

    print("\nAll tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

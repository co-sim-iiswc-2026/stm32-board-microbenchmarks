#!/usr/bin/env python3
"""
scaling_nop16_sweep.py — flash bench_nop16_{8,16,24,…,80} on all 4
hardware variants, capture average DWT `inner` cycles per (kernel ×
variant), tabulate, and linear-fit each variant's points to extract:

  slope     = cycles per nop.n  (effective CPI for instruction-fetch
              behaviour under that cache/prefetch policy)
  intercept = harness measurement framing  (bl + bx + ldr-distance
              when warm-cache; plus uncached-fetch tail when ART off)

argparse only — no env vars.  Requires an ST-Link visible to lsusb.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

NOP_COUNTS = [8, 16, 24, 32, 40, 48, 56, 64, 72, 80]
DEFAULT_VARIANTS = [
    "hw-stm32g474re",
    "hw-nocache-stm32g474re",
    "hw-noprefetch-stm32g474re",
    "hw-none-stm32g474re",
]


def run_one(variant: str, n_nops: int, timeout_s: int) -> int | None:
    """Flash bench_nop16_<n_nops> on <variant>, return avg cycles or None."""
    bench = f"bench_nop16_{n_nops}"
    res = subprocess.run(
        ["python3", str(ROOT / "test" / "test_board_run.py"),
         "--timeout-s", str(timeout_s),
         variant, bench],
        cwd=ROOT, capture_output=True, text=True, check=False,
    )
    cyc_file = ROOT / "test" / "logs" / variant / f"{bench}.cycles.txt"
    if res.returncode != 0 or not cyc_file.exists():
        sys.stderr.write(f"  [{variant}/{bench}] FAIL (rc={res.returncode})\n")
        if res.stderr:
            sys.stderr.write(res.stderr[-400:])
        return None
    return int(cyc_file.read_text().strip())


def fit_line(xs: list[float], ys: list[float]) -> tuple[float, float]:
    """Least-squares linear fit y = m*x + b. Returns (m, b)."""
    n = len(xs)
    sx, sy = sum(xs), sum(ys)
    sxy = sum(x * y for x, y in zip(xs, ys))
    sxx = sum(x * x for x in xs)
    m = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    b = (sy - m * sx) / n
    return m, b


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Sweep bench_nop16_{10..100} × 4 hw variants on the board.")
    ap.add_argument("--timeout-s", type=int, default=15,
                    help="Per-run OpenOCD timeout (default %(default)s)")
    args = ap.parse_args()

    variants = DEFAULT_VARIANTS

    # results[variant][n] = avg cycles
    results: dict[str, dict[int, int | None]] = {v: {} for v in variants}

    for v in variants:
        print(f"\n=== {v} ===")
        for n in NOP_COUNTS:
            cyc = run_one(v, n, args.timeout_s)
            results[v][n] = cyc
            print(f"  bench_nop16_{n:>3}: inner = {cyc}")

    # Table.
    print()
    print("=" * 96)
    print(f"{'NOPs':>5}   " + "   ".join(f"{v:<24}" for v in variants))
    print("-" * 96)
    for n in NOP_COUNTS:
        cells = [
            f"{results[v][n]:>24}" if results[v][n] is not None
            else f"{'FAIL':>24}"
            for v in variants
        ]
        print(f"{n:>5}   " + "   ".join(cells))
    print("=" * 96)

    # Linear fit per variant.
    print()
    print("Linear fit  inner = slope · N + intercept")
    print("-" * 64)
    for v in variants:
        xs = [n for n in NOP_COUNTS if results[v][n] is not None]
        ys = [float(results[v][n]) for n in xs]
        if len(xs) < 2:
            print(f"  {v:<28} insufficient data")
            continue
        m, b = fit_line([float(x) for x in xs], ys)
        # Residuals to gauge linearity.
        max_resid = max(abs(y - (m * x + b)) for x, y in zip(xs, ys))
        print(f"  {v:<28} slope = {m:6.3f} c/NOP   "
              f"intercept = {b:7.2f} c   max|resid| = {max_resid:.2f}")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())

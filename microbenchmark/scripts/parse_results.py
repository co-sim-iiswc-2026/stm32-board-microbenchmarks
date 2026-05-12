#!/usr/bin/env python3
"""
parse_results.py — pull the kernel's cycle count out of a run artifact.

Two modes, auto-detected from the file content:

  Hardware (OpenOCD log capturing semihosting)
      Reads every  MICROBENCH name=<bench> rep=<i> inner=<N>  line and
      emits the average inner cycles as the headline:
          <bench>\\t<avg>
      With --per-rep, emits one row per rep instead:
          <bench>\\t<rep>\\t<inner>

  gem5 (m5out/stats.txt)
      Reads every stats window (one per rep, carved out by an
      m5_work_begin / m5_work_end pair around the measured call) and
      emits the average of the named stat (default
      system.cpu.numCycles):
          <stat>\\t<avg>
      With --per-rep, emits one row per window:
          <stat>\\t<rep>\\t<value>
      With --window all, dumps the full text of every window.

Usage:
  python3 ./scripts/parse_results.py path/to/openocd.log
  python3 ./scripts/parse_results.py path/to/m5out/stats.txt
  python3 ./scripts/parse_results.py m5out/stats.txt --stat system.cpu.numCycles
  python3 ./scripts/parse_results.py m5out/stats.txt --window all
  python3 ./scripts/parse_results.py openocd.log --per-rep
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


HARDWARE_RE = re.compile(
    r"MICROBENCH\s+name=(\S+)\s+rep=(\d+)\s+inner=(\d+)"
)


def detect(text: str) -> str:
    if "Begin Simulation Statistics" in text:
        return "gem5"
    if HARDWARE_RE.search(text):
        return "hardware"
    return "unknown"


def extract_all_stats_windows(text: str) -> list[str]:
    """Return each '----- Begin ... End -----' block's body as a string.

    The harness emits one window per measured rep; gem5 concatenates
    them into stats.txt back-to-back, so we return them in rep order.
    """
    out: list[str] = []
    cur: list[str] = []
    inside = False
    for line in text.splitlines(keepends=True):
        if "Begin Simulation Statistics" in line:
            inside = True
            cur = []
            continue
        if "End Simulation Statistics" in line:
            if inside:
                out.append("".join(cur))
                inside = False
            continue
        if inside:
            cur.append(line)
    # Tolerate a file ending mid-window: include the partial.
    if inside and cur:
        out.append("".join(cur))
    return out


def parse_hardware(text: str, per_rep: bool) -> int:
    """Emit average inner cycles (default) or one row per rep (--per-rep)."""
    rows = HARDWARE_RE.findall(text)
    if not rows:
        sys.exit("no 'MICROBENCH name=... rep=... inner=...' line found")
    if per_rep:
        for name, rep, inner in rows:
            print(f"{name}\t{rep}\t{inner}")
        return 0
    # Average is the headline metric. All rows share the same bench
    # name (one ELF flashed per run); use the first.
    name = rows[0][0]
    inners = [int(i) for _, _, i in rows]
    avg = round(sum(inners) / len(inners))
    print(f"{name}\t{avg}")
    return 0


def parse_gem5(text: str, stat_name: str, per_rep: bool, dump_window: bool) -> int:
    windows = extract_all_stats_windows(text)
    if not windows:
        sys.exit("no stats window found — were m5_work_begin/end pairs reached?")
    if dump_window:
        for i, w in enumerate(windows):
            print(f"----- rep {i} -----")
            sys.stdout.write(w)
        return 0
    # gem5 stats lines look like:  system.cpu.numCycles  123456   # comment
    pat = re.compile(rf"^{re.escape(stat_name)}\s+(\S+)", re.MULTILINE)
    values: list[float] = []
    missing = 0
    for i, w in enumerate(windows):
        m = pat.search(w)
        if not m:
            print(f"{stat_name}\t{i}\t<missing>", file=sys.stderr)
            missing += 1
            continue
        if per_rep:
            print(f"{stat_name}\t{i}\t{m.group(1)}")
        else:
            try:
                values.append(float(m.group(1)))
            except ValueError:
                # Non-numeric stat — fall back to per-rep dump for transparency.
                print(f"{stat_name}\t{i}\t{m.group(1)}")
                missing += 1
    if not per_rep and values:
        avg = round(sum(values) / len(values))
        print(f"{stat_name}\t{avg}")
    return 1 if missing else 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("path", type=Path, help="OpenOCD log or m5out/stats.txt")
    ap.add_argument("--stat", default="system.cpu.numCycles",
                    help="gem5: which stat to extract per rep (default: %(default)s)")
    ap.add_argument("--per-rep", action="store_true",
                    help="Print one row per rep instead of the headline average.")
    ap.add_argument("--window", choices=("stat", "all"), default="stat",
                    help="gem5: 'all' to dump every rep's full window (default: stat)")
    args = ap.parse_args()

    text = args.path.read_text()
    kind = detect(text)
    if kind == "hardware":
        return parse_hardware(text, args.per_rep)
    if kind == "gem5":
        return parse_gem5(text, args.stat, args.per_rep, args.window == "all")
    sys.exit(f"could not detect file type of {args.path} (neither OpenOCD log nor gem5 stats.txt)")


if __name__ == "__main__":
    sys.exit(main())

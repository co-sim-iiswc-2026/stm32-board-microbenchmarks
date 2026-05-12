#!/usr/bin/env python3
"""
test_build_all.py — configure & build every preset (gem5 + the 4
hardware variants), assert each produces bench_nop16_100.elf with the
pinned symbols at the expected addresses (bench_entry=0x08000400,
_bench_body_start=0x08000480).

Cheap to run; no board required.
"""

from __future__ import annotations

import sys

from _common import (
    ALL_PRESETS, DEFAULT_BENCH, EXPECTED_BENCH_BODY_START_ADDR,
    EXPECTED_BENCH_ENTRY_ADDR, cmake_build, cmake_configure,
    elf_path, fail, nm_symbols, ok,
)


def main() -> int:
    print(f"==> Configuring + building all {len(ALL_PRESETS)} presets ...")
    for p in ALL_PRESETS:
        print(f"    [{p}]")
        cmake_configure(p)
        cmake_build(p, jobs=4)

    print()
    print("==> Checking pinned symbols (bench_entry @ 0x08000400, "
          "_bench_body_start @ 0x08000480) ...")
    for p in ALL_PRESETS:
        elf = elf_path(p, DEFAULT_BENCH)
        if not elf.exists():
            fail(f"[{p}] missing {elf}")

        syms = nm_symbols(elf)
        body_addr  = syms.get("_bench_body_start")
        entry_addr = syms.get("bench_entry")

        if body_addr != EXPECTED_BENCH_BODY_START_ADDR:
            fail(f"[{p}] _bench_body_start = {body_addr} (want {EXPECTED_BENCH_BODY_START_ADDR})")
        if entry_addr != EXPECTED_BENCH_ENTRY_ADDR:
            fail(f"[{p}] bench_entry       = {entry_addr} (want {EXPECTED_BENCH_ENTRY_ADDR})")
        ok(f"[{p}] bench_entry={entry_addr} _bench_body_start={body_addr}")

    print()
    print("All builds OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
test_layout_identical.py — verifies the byte-identical and
address-identical invariants the harness depends on:

  1. `kernel_body` (the user's workload) hashes to the same value
     across ALL build targets: gem5 + every hardware cache variant.
     This is what makes cross-target cycle-count comparisons valid.

  2. `kernel_body` lives at the SAME flash address across all builds —
     pinned at 0x08001000 by the board's linker script. Same with
     `__kernel_data_start` (pinned at 0x08001400). Stable addresses
     keep I/D-cache set indices identical between gem5 and hardware.

  3. The bench_entry wrapper bytes (`_bench_body_start` to
     `_bench_body_end`, inside .bench_kernel) hash to the same value
     across the 4 hardware cache variants. Wrapper bytes differ
     between hardware and gem5 by design — different measurement
     instrumentation — so gem5 is excluded from this check.
"""

from __future__ import annotations

import sys

from _common import (
    ALL_PRESETS, DEFAULT_BENCH, HW_PRESETS, elf_path, fail,
    hash_body_region, hash_kernel_body, nm_symbols,
)


# Pinned addresses the board's linker script guarantees.
EXPECTED_KERNEL_BODY_ADDR = "08001000"
EXPECTED_KERNEL_DATA_ADDR = "08001400"


def check_hash_invariant(name: str, presets: list[str], hasher) -> None:
    print(f"==> {name}")
    ref: str | None = None
    for p in presets:
        elf = elf_path(p, DEFAULT_BENCH)
        if not elf.exists():
            fail(f"[{p}] no {elf} — run test_build_all.py first "
                 f"(or `cmake --preset {p} && cmake --build build/{p}`)")
        h = hasher(elf)
        print(f"    {p:<26} {h}")
        if ref is None:
            ref = h
        elif h != ref:
            fail(f"[{p}] hash differs from first preset — invariant broken")


def check_address_invariant(name: str, symbol: str, expected: str) -> None:
    print(f"==> {name}")
    for p in ALL_PRESETS:
        elf = elf_path(p, DEFAULT_BENCH)
        syms = nm_symbols(elf)
        addr = syms.get(symbol)
        if addr is None:
            fail(f"[{p}] symbol '{symbol}' not found in {elf}")
        print(f"    {p:<26} {symbol} = 0x{addr}")
        if addr != expected:
            fail(f"[{p}] {symbol} = 0x{addr}, expected 0x{expected} "
                 f"(linker pin in board/<board>/<board>.ld broken?)")


def main() -> int:
    check_hash_invariant(
        "kernel_body bytes byte-identical across all targets (gem5 + 4 hardware)",
        ALL_PRESETS,
        hash_kernel_body,
    )

    print()
    check_address_invariant(
        f"kernel_body pinned at 0x{EXPECTED_KERNEL_BODY_ADDR} on every build",
        "kernel_body",
        EXPECTED_KERNEL_BODY_ADDR,
    )

    print()
    check_address_invariant(
        f"__kernel_data_start pinned at 0x{EXPECTED_KERNEL_DATA_ADDR} on every build",
        "__kernel_data_start",
        EXPECTED_KERNEL_DATA_ADDR,
    )

    print()
    check_hash_invariant(
        "bench_entry wrapper bytes byte-identical across the 4 hardware cache variants",
        HW_PRESETS,
        hash_body_region,
    )

    print()
    print("All layout invariants hold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

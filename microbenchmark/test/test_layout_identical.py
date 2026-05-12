#!/usr/bin/env python3
"""
test_layout_identical.py — verifies two byte-identical invariants the
harness depends on:

  1. `kernel_body` (the user's workload) hashes to the same value
     across ALL build targets: gem5 + every hardware cache variant.
     This is what makes cross-target cycle-count comparisons valid.

  2. The bench_entry wrapper bytes (`_bench_body_start` to
     `_bench_body_end`, inside .bench_kernel) hash to the same value
     across the 4 hardware cache variants. Wrapper bytes differ
     between hardware and gem5 by design — different measurement
     instrumentation — so gem5 is excluded from this check.
"""

from __future__ import annotations

import sys

from _common import (
    ALL_PRESETS, DEFAULT_BENCH, HW_PRESETS, elf_path, fail,
    hash_body_region, hash_kernel_body,
)


def check_invariant(name: str, presets: list[str], hasher) -> None:
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


def main() -> int:
    check_invariant(
        "kernel_body bytes byte-identical across all targets (gem5 + 4 hardware)",
        ALL_PRESETS,
        hash_kernel_body,
    )

    print()
    check_invariant(
        "bench_entry wrapper bytes byte-identical across the 4 hardware cache variants",
        HW_PRESETS,
        hash_body_region,
    )

    print()
    print("All layout invariants hold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

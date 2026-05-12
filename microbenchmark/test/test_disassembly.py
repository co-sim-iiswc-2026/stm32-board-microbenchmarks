#!/usr/bin/env python3
"""
test_disassembly.py — dump per-preset disassembly artifacts to
test/disasm/<preset>/ and produce cross-build diff reports.

Outputs (per preset):
  <preset>/<bench>.full.dis          — full ELF disassembly
  <preset>/<bench>.bench_kernel.dis  — just the .bench_kernel section
  <preset>/<bench>.text.dis          — just the .text section
  <preset>/<bench>.symbols.txt       — `nm -n` listing

Cross-build summaries:
  diff_bench_kernel.txt   — pairwise diffs of .bench_kernel across builds
  diff_apply_flash_acr.txt — apply_flash_acr() per variant
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

from _common import (
    ARM_NM, ARM_OBJDUMP, DEFAULT_BENCH, HW_PRESETS, ROOT,
    cmake_build, cmake_configure, elf_path, fail, hash_body_region, ok, run,
)

OUT = ROOT / "test" / "disasm"


def objdump(*args: str) -> str:
    """Run arm-none-eabi-objdump and return stdout."""
    return run([ARM_OBJDUMP, *args], capture=True).stdout


def write_objdump(args: list[str], path: Path) -> None:
    path.write_text(objdump(*args))


def main() -> int:
    bench = DEFAULT_BENCH

    # Build any missing presets (cheap if already built).
    for p in HW_PRESETS:
        if not elf_path(p, bench).exists():
            print(f"==> Building missing preset: {p}")
            cmake_configure(p)
            cmake_build(p, target=f"{bench}.elf")

    # Fresh output dir.
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    print(f"==> Dumping per-preset disassembly to test/disasm/<preset>/")
    for p in HW_PRESETS:
        elf = elf_path(p, bench)
        dst = OUT / p
        dst.mkdir()

        write_objdump(["-d", "-S",                       str(elf)], dst / f"{bench}.full.dis")
        write_objdump(["-d", "-j", ".bench_kernel",      str(elf)], dst / f"{bench}.bench_kernel.dis")
        write_objdump(["-d", "-j", ".text",              str(elf)], dst / f"{bench}.text.dis")

        nm = run([ARM_NM, "-n", str(elf)], capture=True).stdout
        (dst / f"{bench}.symbols.txt").write_text(nm)

        body_addr = None
        for line in nm.splitlines():
            parts = line.split()
            if len(parts) == 3 and parts[2] == "_bench_body_start":
                body_addr = parts[0]
                break
        if body_addr != "08000480":
            fail(f"[{p}] _bench_body_start={body_addr} (want 08000480)")

        size_bytes = elf.stat().st_size
        ok(f"{p:<26} _bench_body_start={body_addr}  size={size_bytes} bytes")

    # Cross-build diff: .bench_kernel.dis pairwise vs the default hardware preset.
    print()
    print("==> Cross-build .bench_kernel diffs (test/disasm/diff_bench_kernel.txt)")
    base_preset = HW_PRESETS[0]   # the all-on default (HW_VARIANT=full)
    base = OUT / base_preset / f"{bench}.bench_kernel.dis"
    diff_lines: list[str] = [
        "# Pairwise diffs of .bench_kernel disassembly.",
        "# Body bytes (0x08000480..) must match; only prologue/epilogue may differ.",
        "",
    ]
    for p in HW_PRESETS:
        if p == base_preset:
            continue
        other = OUT / p / f"{bench}.bench_kernel.dis"
        diff_lines += [
            "=" * 64,
            f"# diff {base_preset} vs {p}",
            "=" * 64,
        ]
        res = run(["diff", "-u", str(base), str(other)], capture=True, check=False)
        diff_lines.append(res.stdout)
        diff_lines.append("")
    (OUT / "diff_bench_kernel.txt").write_text("\n".join(diff_lines))

    # apply_flash_acr() per variant.
    print("==> Per-hw-variant apply_flash_acr disasm (test/disasm/diff_apply_flash_acr.txt)")
    acr_lines: list[str] = [
        "# apply_flash_acr() disassembly per hw variant.",
        "# Differences here = different FLASH->ACR immediate (cache/prefetch bits).",
        "",
    ]
    for p in HW_PRESETS:
        full = (OUT / p / f"{bench}.full.dis").read_text().splitlines()
        capture_block: list[str] = []
        capturing = False
        for line in full:
            if "<apply_flash_acr>:" in line:
                capturing = True
            if capturing:
                capture_block.append(line)
                if line.strip() == "" and len(capture_block) > 1:
                    break
        acr_lines += [
            "=" * 64,
            f"# {p}",
            "=" * 64,
            *capture_block,
            "",
        ]
    (OUT / "diff_apply_flash_acr.txt").write_text("\n".join(acr_lines))

    # Re-verify body-byte invariant.
    print()
    print("==> Body-byte invariant (re-check):")
    ref: str | None = None
    for p in HW_PRESETS:
        h = hash_body_region(elf_path(p, bench))
        print(f"  {p:<26} {h}")
        if ref is None:
            ref = h
        elif h != ref:
            fail(f"[{p}] body hash diverges from {HW_PRESETS[0]} — invariant broken")

    print()
    print("Artifacts written to test/disasm/")
    print(f"  - per preset: <preset>/{bench}.{{full,bench_kernel,text}}.dis + symbols.txt")
    print("  - cross:      diff_bench_kernel.txt  diff_apply_flash_acr.txt")
    return 0


if __name__ == "__main__":
    sys.exit(main())

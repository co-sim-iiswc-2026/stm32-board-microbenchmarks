#!/usr/bin/env python3
"""
check_kernel_size.py — post-link guards against oversized kernels.

The harness depends on the warmup call fully priming the target's
caches so every subsequent measured rep hits warm caches. If the
kernel's footprint exceeds those caches, the warmup can't possibly
cover everything and the measurement loses its "warm cache" meaning.

Two checks, one per cache:

  I-cache check
    Compares the `.size`-tagged byte length of `kernel_body` (the
    user's instruction sequence emitted by the BENCH / END_BENCH
    macros) against the board's ICACHE_SIZE_BYTES.

  D-cache check
    Compares the flash-resident data footprint the kernel opts into
    against the board's DCACHE_SIZE_BYTES. A kernel declares its
    data by placing read-only data in a `.rodata.kernel_data` (or
    `.rodata.kernel_data.*`) input section; the linker brackets that
    region with `__kernel_data_start` / `__kernel_data_end` symbols
    that this script reads. Kernels that don't declare such a
    section have a zero-byte data footprint and always pass.

Per-cache override flags (--allow-exceed-icache, --allow-exceed-dcache)
turn the corresponding failure into a warning. argparse only — no
env-var inputs.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


ARM_NM = shutil.which("arm-none-eabi-nm") or "arm-none-eabi-nm"


def _nm_table(elf: Path) -> list[list[str]]:
    """Return `nm -S` output as a list of token rows."""
    out = subprocess.check_output(
        [ARM_NM, "-S", str(elf)], text=True)
    return [line.split() for line in out.splitlines() if line.strip()]


def symbol_size_bytes(elf: Path, symbol: str) -> int | None:
    """Return the byte size of `symbol` (from its `.size` directive),
    or None if the symbol has no size."""
    for parts in _nm_table(elf):
        if len(parts) == 4 and parts[3] == symbol:
            return int(parts[1], 16)
    return None


def symbol_address(elf: Path, symbol: str) -> int | None:
    """Return the linked address of `symbol`, or None if absent."""
    for parts in _nm_table(elf):
        # Sized rows have 4 cols; unsized 3.
        if parts[-1] == symbol:
            return int(parts[0], 16)
    return None


def kernel_data_size_bytes(elf: Path) -> int | None:
    """Return `__kernel_data_end - __kernel_data_start`, or None if
    those linker sentinels are missing (linker script too old).

    Both symbols always exist for a current linker script — even when
    the kernel doesn't declare any .rodata.kernel_data input, they
    collapse to the same address (size = 0).
    """
    start = symbol_address(elf, "__kernel_data_start")
    end   = symbol_address(elf, "__kernel_data_end")
    if start is None or end is None:
        return None
    return end - start


def emit_failure(kernel_name: str, cache_kind: str, size: int,
                 cache_size: int, override_flag: str) -> None:
    """Print a uniform error message for either cache."""
    sys.stderr.write(
        "\n"
        f"  ERROR: kernel '{kernel_name}' has a {cache_kind} footprint of "
        f"{size} bytes, which exceeds the board's {cache_kind} size "
        f"({cache_size} bytes).\n"
        "\n"
        "  The harness assumes the warmup call fully primes the target's "
        f"{cache_kind} so every subsequent measured rep hits a warm cache.\n"
        "  An oversized kernel breaks that assumption — some lines will "
        "always be cold, and the reported `inner` cycles no longer reflect\n"
        "  a warm-cache measurement.\n"
        "\n"
        "  Options:\n"
        f"    1. Shrink the kernel's {cache_kind} footprint below "
        f"{cache_size} bytes.\n"
        "    2. If you intentionally want to measure a partially-cold-cache "
        f"kernel, re-configure with {override_flag}=ON.\n"
        "\n"
    )


def check_icache(elf: Path, kernel_name: str, icache: int,
                 allow_exceed: bool) -> bool:
    """Run the I-cache check. Returns True iff the build should fail."""
    size = symbol_size_bytes(elf, "kernel_body")
    if size is None:
        sys.exit(
            f"check_kernel_size: kernel_body (with .size) not found in "
            f"{elf} — was the kernel built with the BENCH / END_BENCH "
            "macros?"
        )

    if size > icache:
        status = "OVERSIZE (allowed)" if allow_exceed else "OVERSIZE"
    else:
        status = "ok"
    print(
        f"[{kernel_name}] I-cache: kernel_body = {size} bytes / "
        f"I-cache = {icache} bytes — {status}"
    )

    if size > icache and not allow_exceed:
        emit_failure(kernel_name, "I-cache", size, icache,
                     "-DALLOW_KERNEL_EXCEED_ICACHE")
        return True
    return False


def check_dcache(elf: Path, kernel_name: str, dcache: int,
                 allow_exceed: bool) -> bool:
    """Run the D-cache check. Returns True iff the build should fail."""
    size = kernel_data_size_bytes(elf)
    if size is None:
        sys.exit(
            f"check_kernel_size: __kernel_data_start/__kernel_data_end "
            f"sentinels not found in {elf} — linker script needs the "
            ".rodata kernel-data brackets."
        )

    if size > dcache:
        status = "OVERSIZE (allowed)" if allow_exceed else "OVERSIZE"
    else:
        status = "ok"
    print(
        f"[{kernel_name}] D-cache: kernel_data = {size} bytes / "
        f"D-cache = {dcache} bytes — {status}"
    )

    if size > dcache and not allow_exceed:
        emit_failure(kernel_name, "D-cache", size, dcache,
                     "-DALLOW_KERNEL_EXCEED_DCACHE")
        return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Fail the build if a kernel exceeds the board's I-cache or D-cache.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--elf", required=True, type=Path,
                    help="Path to the linked .elf file.")
    ap.add_argument("--kernel-name", required=True,
                    help="Benchmark name, used in the error message.")
    ap.add_argument("--icache-size-bytes", required=True, type=int,
                    help="Target board's I-cache size in bytes.")
    ap.add_argument("--dcache-size-bytes", required=True, type=int,
                    help="Target board's D-cache size in bytes.")
    ap.add_argument("--allow-exceed-icache", action="store_true",
                    help="Don't fail when the kernel exceeds I-cache.")
    ap.add_argument("--allow-exceed-dcache", action="store_true",
                    help="Don't fail when the kernel exceeds D-cache.")
    args = ap.parse_args()

    if not args.elf.exists():
        sys.exit(f"check_kernel_size: ELF not found: {args.elf}")

    failed = False
    failed |= check_icache(args.elf, args.kernel_name,
                           args.icache_size_bytes, args.allow_exceed_icache)
    failed |= check_dcache(args.elf, args.kernel_name,
                           args.dcache_size_bytes, args.allow_exceed_dcache)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

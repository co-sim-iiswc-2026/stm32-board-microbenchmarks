"""
Shared helpers for the microbenchmark test scripts.

Convention:
- ROOT is the microbenchmark/ directory.
- HW_PRESETS are the 4 hardware cache/prefetch variants. They share
  the same source so cross-build comparisons (layout invariant,
  board-run sweep) only need to iterate over these.
"""

from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

# microbenchmark/ — where CMakeLists.txt lives.
ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
LOGS  = ROOT / "test" / "logs"

# Hardware presets (drive the board). Share source so the bench_entry
# wrapper bytes within .bench_kernel are byte-identical across these.
# Names follow the <platform>[-<variant>]-<board> convention.
HW_PRESETS = [
    "hw-stm32g474re",
    "hw-nocache-stm32g474re",
    "hw-noprefetch-stm32g474re",
    "hw-none-stm32g474re",
]

# All presets including gem5. Used to verify kernel_body (the
# actual workload) is byte-identical across every target — that's the
# invariant that makes gem5-vs-hardware cycle comparisons meaningful.
ALL_PRESETS = ["gem5-stm32g474re", *HW_PRESETS]

# Default kernel everyone tests against.
DEFAULT_BENCH = "bench_nop16_100"

# Pinned addresses the harness guarantees (see board/<board>/<board>.ld + .bench_kernel).
EXPECTED_BENCH_ENTRY_ADDR     = "08000400"
EXPECTED_BENCH_BODY_START_ADDR = "08000480"

# Toolchain — resolved once at import.
ARM_NM      = shutil.which("arm-none-eabi-nm")      or "arm-none-eabi-nm"
ARM_OBJDUMP = shutil.which("arm-none-eabi-objdump") or "arm-none-eabi-objdump"
ARM_SIZE    = shutil.which("arm-none-eabi-size")    or "arm-none-eabi-size"


def fail(msg: str) -> "None":  # noqa: D401
    """Print FAIL: <msg> to stderr and exit 1."""
    print(f"  FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def ok(msg: str) -> None:
    """Print an OK status line."""
    print(f"  ok:   {msg}")


def run(cmd: list[str], *, cwd: Path | None = None, check: bool = True,
        capture: bool = False, env: dict | None = None,
        timeout: float | None = None) -> subprocess.CompletedProcess:
    """Thin wrapper around subprocess.run with sensible defaults."""
    return subprocess.run(
        cmd,
        cwd=cwd or ROOT,
        check=check,
        capture_output=capture,
        text=True,
        env=env,
        timeout=timeout,
    )


def cmake_configure(preset: str) -> None:
    """`cmake --preset <preset>`, quiet on success."""
    res = run(["cmake", "--preset", preset], capture=True, check=False)
    if res.returncode != 0:
        sys.stderr.write(res.stdout)
        sys.stderr.write(res.stderr)
        fail(f"cmake --preset {preset} failed")


def cmake_build(preset: str, *, target: str | None = None, jobs: int = 4) -> None:
    """`cmake --build build/<preset> -j<jobs> [--target <target>]`."""
    cmd = ["cmake", "--build", str(BUILD / preset), "-j", str(jobs)]
    if target:
        cmd += ["--target", target]
    res = run(cmd, capture=True, check=False)
    if res.returncode != 0:
        sys.stderr.write(res.stdout)
        sys.stderr.write(res.stderr)
        fail(f"cmake --build {preset} failed")


def elf_path(preset: str, bench: str) -> Path:
    return BUILD / preset / "bin" / f"{bench}.elf"


def nm_symbols(elf: Path) -> dict[str, str]:
    """Return {symbol_name: 8-digit-hex-address} for all symbols in elf."""
    res = run([ARM_NM, str(elf)], capture=True)
    syms: dict[str, str] = {}
    for line in res.stdout.splitlines():
        parts = line.split()
        if len(parts) == 3:
            addr, _kind, name = parts
            syms[name] = addr
    return syms


def _objdump_bytes_only(elf: Path, section: str, start_addr: int,
                        end_addr: int) -> str:
    """Run `objdump -s` on [start_addr, end_addr) in `section` and return
    only the hex byte payload — no address column, no ASCII column.

    objdump -s output looks like:
        Contents of section .text:
         80004f0 bf00bf00 bf00bf00 bf00bf00 bf00bf00  ................
         8000500 bf00bf00 bf00bf00 bf00bf00 bf00bf00  ................

    We drop the first 4 header lines, then for each remaining data line
    strip the leading offset (col 0) and the trailing ASCII column (last
    field), keeping only the hex byte groups in between. This makes the
    hash address-independent — what we're checking is the BYTES, not
    where they happen to live in flash.
    """
    res = run([
        ARM_OBJDUMP, "-s", "-j", section,
        f"--start-address=0x{start_addr:x}",
        f"--stop-address=0x{end_addr:x}",
        str(elf),
    ], capture=True)

    h = hashlib.sha256()
    for line in res.stdout.splitlines()[4:]:
        # Split off offset (first token); the ASCII column is whatever
        # comes after the last 2-or-more-space gap. Easiest: keep only
        # tokens that are pure hex digits.
        tokens = line.split()
        if not tokens:
            continue
        # The first token is the offset (in hex, no spaces) — drop it.
        # The remaining hex groups are the byte data; non-hex tokens
        # (the ASCII column) we filter out.
        hex_only = [t for t in tokens[1:]
                    if all(c in "0123456789abcdefABCDEF" for c in t)]
        h.update(" ".join(hex_only).encode())
    return h.hexdigest()


def hash_body_region(elf: Path) -> str:
    """SHA-256 of the bench_entry wrapper bytes from _bench_body_start..._bench_body_end.

    These bytes contain the harness's measurement instrumentation
    (snap ldrs on hardware, m5_work_begin/end bkpts on gem5). They are
    byte-identical across the 4 hardware cache variants but DIFFER
    between gem5 and hardware (different markers).
    """
    syms = nm_symbols(elf)
    start = int(syms["_bench_body_start"], 16)
    end   = int(syms["_bench_body_end"],   16)
    return _objdump_bytes_only(elf, ".bench_kernel", start, end)


def hash_kernel_body(elf: Path, length: int = 256) -> str:
    """SHA-256 of `length` bytes starting at the `kernel_body` symbol.

    This is the user's actual kernel workload. It MUST be byte-identical
    across every build target (gem5 + all hardware cache variants),
    because that's what makes cross-target cycle-count comparisons
    meaningful.
    """
    syms = nm_symbols(elf)
    start = int(syms["kernel_body"], 16)
    return _objdump_bytes_only(elf, ".text", start, start + length)


def ensure_build(preset: str, bench: str = DEFAULT_BENCH) -> Path:
    """Configure + build the given preset/bench if its ELF doesn't exist yet."""
    elf = elf_path(preset, bench)
    if not elf.exists():
        cmake_configure(preset)
        cmake_build(preset, target=f"{bench}.elf")
    if not elf.exists():
        fail(f"build failed — no {elf}")
    return elf


STLINK_RE = re.compile(r"ST-?LINK", re.IGNORECASE)


def stlink_visible() -> bool:
    """Return True iff `lsusb` shows an ST-Link device."""
    res = run(["lsusb"], capture=True, check=False)
    if res.returncode != 0:
        return False
    return bool(STLINK_RE.search(res.stdout))

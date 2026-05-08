#!/bin/bash
# Sanity-check the generators on two axes:
#
#   1. Reproducibility — re-running each generator must produce the
#      currently-committed generated/*.cc and fpu_seq_manifest.txt
#      byte-for-byte. Catches accidental drift from generator edits.
#
#   2. Build-mode coverage — every generated bench_*.cc must guard
#      its STM32-peripheral init (sys_clk_cfg, ENTO_BENCH_SETUP,
#      cache enable) so that BOTH the gem5 build (-DGEM5_SIM=1) and
#      the QEMU build (-DQEMU_SIM=1) skip it. A bench that only
#      checks `#ifndef GEM5_SIM` will hang under qemu-system-arm on
#      the unimplemented STM32 RCC peripheral, so we forbid the
#      bare-GEM5_SIM guard outright.
#
# Exit 0 if everything matches. Non-zero with a diff / explanation if
# anything drifted or the QEMU guard is missing.
#
# Usage:
#   ./verification/gen/check.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# ---------------------------------------------------------------------------
# (1) Reproducibility
# ---------------------------------------------------------------------------

# Snapshot what's currently on disk (i.e. committed state, assuming clean
# tree).
cp -r benchmark/microbench/generated "$TMPDIR/before"
cp verification/gen/fpu_seq_manifest.txt "$TMPDIR/before_manifest.txt"

# Regenerate from all three generator scripts. fpu_single.py emits the
# single-instruction tests; fpu_repeat.py emits the Level A repeated-
# instruction tests; fpu_seq.py emits the Level B random-sequence tests
# (and the manifest).
python3 verification/gen/fpu_single.py > /dev/null
python3 verification/gen/fpu_repeat.py > /dev/null
python3 verification/gen/fpu_seq.py    > /dev/null

# Diff. `diff -r` exits non-zero on any mismatch.
if ! diff -r "$TMPDIR/before" benchmark/microbench/generated > "$TMPDIR/gen.diff"; then
  echo "FAIL: regenerated .cc files differ from committed state:" >&2
  cat "$TMPDIR/gen.diff" >&2
  exit 1
fi

if ! diff "$TMPDIR/before_manifest.txt" verification/gen/fpu_seq_manifest.txt > "$TMPDIR/manifest.diff"; then
  echo "FAIL: regenerated manifest differs from committed state:" >&2
  cat "$TMPDIR/manifest.diff" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# (2) Build-mode coverage — every generated file must skip STM32 init
#     under both GEM5_SIM and QEMU_SIM.
# ---------------------------------------------------------------------------

bare_gem5=$(grep -l '^#ifndef GEM5_SIM$' benchmark/microbench/generated/*.cc 2>/dev/null || true)
if [[ -n "$bare_gem5" ]]; then
  echo "FAIL: generated files still use the bare GEM5_SIM-only guard;" >&2
  echo "      these would hang under qemu-system-arm on sys_clk_cfg / RCC:" >&2
  echo "$bare_gem5" | sed 's/^/  /' >&2
  echo "      Update the generator(s) to emit:" >&2
  echo "        #if !defined(GEM5_SIM) && !defined(QEMU_SIM)" >&2
  exit 1
fi

# Every generated bench_*.cc that touches STM32 peripherals (i.e. has a
# main() with sys_clk_cfg) must contain the compound guard.
missing=()
for f in benchmark/microbench/generated/bench_*.cc; do
  if grep -q 'sys_clk_cfg' "$f" \
     && ! grep -q '!defined(GEM5_SIM) && !defined(QEMU_SIM)' "$f"; then
    missing+=("$f")
  fi
done
if (( ${#missing[@]} > 0 )); then
  echo "FAIL: generated files call sys_clk_cfg() without the QEMU_SIM gate:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

echo "OK: generators reproduce committed output byte-for-byte"
echo "    and emit the QEMU_SIM-aware build-mode guard."

#!/bin/bash
# Run all generated FPU capture benchmarks in gem5 (Zhantong's cortex-m fork)
# and extract their ENTO_RESULT lines. Mirror of sweep_fpu_board.sh for
# differential testing.
#
# Assumes (override via env vars if needed):
#   GEM5_BIN     — path to gem5.opt built for ARM
#   GEM5_SCRIPT  — path to run_m5op_bench.py (at the root of Zhantong's gem5 repo)
#
# Usage:
#   ./verification/sweep_fpu_gem5.sh

set -euo pipefail
cd "$(dirname "$0")/.."

GEM5_BIN="${GEM5_BIN:-/work/global/ddo26/gem5/build/ARM/gem5.opt}"
GEM5_SCRIPT="${GEM5_SCRIPT:-/work/global/ddo26/gem5/run_m5op_bench.py}"
FW_DIR="build-gem5/bin"
OUT_BASE="verification/logs/gem5"
SUMMARY="$OUT_BASE/ento_results.txt"

# Single-instruction FPU tests — the default sweep.
FPU_BENCHES=(
    bench-fpu-vadd-f32
    bench-fpu-vsub-f32
    bench-fpu-vmul-f32
    bench-fpu-vdiv-f32
    bench-fpu-vnmul-f32
    bench-fpu-vfma-f32
    bench-fpu-vfms-f32
    bench-fpu-vfnma-f32
    bench-fpu-vfnms-f32
    bench-fpu-vmla-f32
    bench-fpu-vmls-f32
    bench-fpu-vsqrt-f32
    bench-fpu-vabs-f32
    bench-fpu-vneg-f32
    bench-fpu-vcvt-f32-s32
    bench-fpu-vcvt-s32-f32
    bench-fpu-vcvt-f32-u32
    bench-fpu-vcvt-u32-f32
    bench-vldm-vstm-capture
    bench-vmov-capture
    bench-vpush-vpop-capture
    bench-matvec-12x12-capture
    bench-vldmia-d1-capture
    bench-vldmia-d7wb-capture
    bench-vldmia-d-range-capture
    bench-vstmia-d-range-capture
)

# TinyMPC variants — opt-in via INCLUDE_MPC=1 (slower, already known to NaN in gem5).
MPC_BENCHES=(
    bench-tinympc-capture
    bench-tinympc-capture-iter0
    bench-tinympc-capture-iter1
    bench-tinympc-capture-iter5
    bench-tinympc-capture-iter20
    bench-tinympc-capture-iter50
)

INCLUDE_MPC=0
for arg in "$@"; do
    case "$arg" in
        --mpc) INCLUDE_MPC=1 ;;
        -h|--help)
            echo "Usage: $0 [--mpc]"
            echo "  --mpc   also run TinyMPC capture variants (default: FPU only)"
            exit 0
            ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

if [[ "$INCLUDE_MPC" == "1" ]]; then
    BENCHES=("${MPC_BENCHES[@]}" "${FPU_BENCHES[@]}")
else
    BENCHES=("${FPU_BENCHES[@]}")
fi

mkdir -p "$OUT_BASE"
: > "$SUMMARY"

if [[ ! -x "$GEM5_BIN" ]]; then
    echo "gem5 binary not found or not executable: $GEM5_BIN"
    echo "Set GEM5_BIN env var to override."
    exit 1
fi
if [[ ! -f "$GEM5_SCRIPT" ]]; then
    echo "run_m5op_bench.py not found: $GEM5_SCRIPT"
    echo "Set GEM5_SCRIPT env var to override."
    exit 1
fi

echo "Sweeping ${#BENCHES[@]} FPU tests in gem5..."
echo "  gem5:   $GEM5_BIN"
echo "  script: $GEM5_SCRIPT"
echo

for bench in "${BENCHES[@]}"; do
    firmware="$FW_DIR/${bench}.elf"
    outdir="$OUT_BASE/m5out_${bench}"
    printf "  %-32s " "$bench"

    if [[ ! -f "$firmware" ]]; then
        echo "MISSING_ELF ($firmware)"
        echo "$bench: MISSING_ELF" >> "$SUMMARY"
        continue
    fi

    # -re redirects simulated stdout/stderr into simout.txt/simerr.txt in outdir.
    # --no-art disables the STM32 ART accelerator (not supported by Zhantong's fork).
    if "$GEM5_BIN" -re --outdir="$outdir" "$GEM5_SCRIPT" \
            --firmware "$firmware" --no-art --run-to-exit > /dev/null 2>&1; then
        result=$(grep "^ENTO_RESULT" "$outdir/simout.txt" 2>/dev/null | head -1 || true)
        if [[ -n "$result" ]]; then
            echo "$result" >> "$SUMMARY"
            echo "$result" | sed -E 's/.*bytes=([0-9a-f]+).*/bytes=\1/'
        else
            echo "NO_ENTO_RESULT_LINE (see $outdir/simout.txt)"
            echo "$bench: NO_ENTO_RESULT_LINE" >> "$SUMMARY"
        fi
    else
        echo "GEM5_FAILED (see $outdir/)"
        echo "$bench: GEM5_FAILED" >> "$SUMMARY"
    fi
done

echo
echo "Per-test outdirs:  $OUT_BASE/m5out_*"
echo "Summary:           $SUMMARY"
echo
echo "=== All ENTO_RESULT lines ==="
cat "$SUMMARY"

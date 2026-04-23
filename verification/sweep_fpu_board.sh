#!/bin/bash
# Flash all generated FPU capture benchmarks to the STM32G474 board and
# extract their ENTO_RESULT lines. Produces the board-side baseline for
# differential testing against gem5/FVP.
#
# Usage:
#   ./verification/sweep_fpu_board.sh

set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build-entobench"
LOG_DIR="verification/logs/board"
SUMMARY_FILE="$LOG_DIR/ento_results.txt"

BENCHES=(
    bench-tinympc-capture
    bench-tinympc-capture-iter0
    bench-tinympc-capture-iter1
    bench-tinympc-capture-iter5
    bench-tinympc-capture-iter20
    bench-tinympc-capture-iter50
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
)

mkdir -p "$LOG_DIR"
: > "$SUMMARY_FILE"

echo "Sweeping ${#BENCHES[@]} FPU capture tests on board..."
echo

for bench in "${BENCHES[@]}"; do
    log="$LOG_DIR/${bench}.log"
    printf "  %-32s " "$bench"
    if make -C "$BUILD_DIR" "stm32-flash-${bench}-semihosted" > "$log" 2>&1; then
        result=$(grep "^ENTO_RESULT" "$log" | head -1 || true)
        if [[ -n "$result" ]]; then
            echo "$result" >> "$SUMMARY_FILE"
            # Print sig_hash + sig_hex for quick eyeball
            echo "$result" | sed -E 's/.*sig_hash=([0-9a-f]+).*sig_hex=([0-9a-f]+).*/hash=\1 hex=\2/'
        else
            echo "NO_ENTO_RESULT_LINE"
            echo "$bench: NO_ENTO_RESULT_LINE" >> "$SUMMARY_FILE"
        fi
    else
        echo "FLASH_FAILED (see $log)"
        echo "$bench: FLASH_FAILED" >> "$SUMMARY_FILE"
    fi
done

echo
echo "Full logs:  $LOG_DIR/"
echo "Summary:    $SUMMARY_FILE"
echo
echo "=== All ENTO_RESULT lines ==="
cat "$SUMMARY_FILE"

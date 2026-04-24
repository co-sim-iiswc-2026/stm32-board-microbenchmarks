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
LOGS_ROOT="verification/logs/board"
HEAD_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
RUN_TAG="${HEAD_SHA}-$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$LOGS_ROOT/runs/$RUN_TAG"
LOG_DIR="$RUN_DIR"
SUMMARY_FILE="$RUN_DIR/ento_results.txt"
RUNS_LOG="$LOGS_ROOT/runs.log"

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
    bench-vstmia-d-range-capture
    # Preamble-zeroing unit tests (isolate the s0..s31 zeroing path)
    bench-preamble-zero-vmov-dpair-capture
    bench-preamble-zero-vmov-ssingle-capture
    bench-preamble-zero-vldr-capture
    # Level A — single FPU instruction repeated N times (fpu_repeat.py)
    bench-fpu-repeat-vadd-f32-n2
    bench-fpu-repeat-vadd-f32-n8
    bench-fpu-repeat-vadd-f32-n64
    bench-fpu-repeat-vadd-f32-n256
    bench-fpu-repeat-vsub-f32-n2
    bench-fpu-repeat-vsub-f32-n8
    bench-fpu-repeat-vsub-f32-n64
    bench-fpu-repeat-vsub-f32-n256
    bench-fpu-repeat-vmul-f32-n2
    bench-fpu-repeat-vmul-f32-n8
    bench-fpu-repeat-vmul-f32-n64
    bench-fpu-repeat-vmul-f32-n256
    bench-fpu-repeat-vfma-f32-n2
    bench-fpu-repeat-vfma-f32-n8
    bench-fpu-repeat-vfma-f32-n64
    bench-fpu-repeat-vfma-f32-n256
    bench-fpu-repeat-vmla-f32-n2
    bench-fpu-repeat-vmla-f32-n8
    bench-fpu-repeat-vmla-f32-n64
    bench-fpu-repeat-vmla-f32-n256
    # Level B — random VFP sequences (fpu_seq.py)
    bench-fpu-seq-s00000001-n10
    bench-fpu-seq-s00000001-n20
    bench-fpu-seq-sdeadbeef-n10
    bench-fpu-seq-sdeadbeef-n20
    bench-fpu-seq-scafef00d-n10
    bench-fpu-seq-scafef00d-n20
    bench-fpu-seq-sbeefdead-n10
    bench-fpu-seq-sbeefdead-n20
    bench-fpu-seq-s12345678-n10
    bench-fpu-seq-s12345678-n20
    bench-fpu-seq-sabcdef01-n10
    bench-fpu-seq-sabcdef01-n20
    bench-fpu-seq-s5a5a5a5a-n10
    bench-fpu-seq-s5a5a5a5a-n20
    bench-fpu-seq-sa5a5a5a5-n10
    bench-fpu-seq-sa5a5a5a5-n20
)

mkdir -p "$RUN_DIR"
: > "$SUMMARY_FILE"

echo "Sweeping ${#BENCHES[@]} FPU capture tests on board..."
echo "  run dir: $RUN_DIR"
echo

for bench in "${BENCHES[@]}"; do
    log="$LOG_DIR/${bench}.log"
    printf "  %-32s " "$bench"
    if make -C "$BUILD_DIR" "stm32-flash-${bench}-semihosted" > "$log" 2>&1; then
        result=$(grep "^ENTO_RESULT" "$log" | head -1 || true)
        if [[ -n "$result" ]]; then
            echo "$result" >> "$SUMMARY_FILE"
            echo "$result" | sed -E 's/.*bytes=([0-9a-f]+).*/bytes=\1/'
        else
            echo "NO_ENTO_RESULT_LINE"
            echo "$bench: NO_ENTO_RESULT_LINE" >> "$SUMMARY_FILE"
        fi
    else
        echo "FLASH_FAILED (see $log)"
        echo "$bench: FLASH_FAILED" >> "$SUMMARY_FILE"
    fi
done

OK_COUNT=$(grep -c "^ENTO_RESULT" "$SUMMARY_FILE" || true)
TOTAL=${#BENCHES[@]}

# Point `latest` and the compat `ento_results.txt` at this run.
ln -sfn "runs/$RUN_TAG" "$LOGS_ROOT/latest"
ln -sfn "runs/$RUN_TAG/ento_results.txt" "$LOGS_ROOT/ento_results.txt"

# Append one-line run summary to runs.log.
printf '%s | HEAD=%s | %d/%d OK | dir=runs/%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HEAD_SHA" "$OK_COUNT" "$TOTAL" "$RUN_TAG" \
  >> "$RUNS_LOG"

echo
echo "Full logs:  $RUN_DIR/"
echo "Summary:    $SUMMARY_FILE"
echo "Latest:     $LOGS_ROOT/latest -> runs/$RUN_TAG"
echo "Runs log:   $RUNS_LOG  ($OK_COUNT/$TOTAL OK this run)"
echo
echo "=== All ENTO_RESULT lines ==="
cat "$SUMMARY_FILE"

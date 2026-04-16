#!/bin/bash
# Run only the new art_cap variants (32-bit, mixed, ratio) and save logs
# to existing benchmark_logs directories so parse_logs.py picks them up.
#
# Usage:
#   ./benchmark/scripts/run_new_art_variants.sh

set -euo pipefail
cd "$(dirname "$0")/../.."

BUILD_DIR="build-entobench"
LOG_DIR="benchmark_logs"
PRESET="stm32-g474re"

NEW_BENCHMARKS=(
    bench-art_cap32_64
    bench-art_cap32_128
    bench-art_cap32_256
    bench-art_capmix_32
    bench-art_capmix_64
    bench-art_capmix_128
    bench-art_capmix_256
    bench-art_mix3x1_64
    bench-art_mix3x1_128
    bench-art_mix1x3_64
    bench-art_mix1x3_128
)

config_json_for() {
    case "$1" in
        cache_pf)      echo "configs/microbench.json" ;;
        cache_nopf)    echo "configs/microbench_noprefetch.json" ;;
        nocache_pf)    echo "configs/microbench_nocache.json" ;;
        nocache_nopf)  echo "configs/microbench_none.json" ;;
        *) echo ""; return 1 ;;
    esac
}

flash_and_log() {
    local target="$1"
    local log="$2"
    echo "  Flashing: $target"
    make -C "$BUILD_DIR" "stm32-flash-${target}-semihosted" 2>&1 | tee "$log" | grep -E "Average cycles:" | head -1
}

run_config() {
    local json="$1"
    local cfg_name="$2"
    local log_subdir="$LOG_DIR/$cfg_name"
    mkdir -p "$log_subdir"

    echo ""
    echo "=== $cfg_name ==="
    cmake --preset "$PRESET" -S benchmark -DMICROBENCH_CONFIG_FILE="$json" 2>&1 | tail -1
    for bench in "${NEW_BENCHMARKS[@]}"; do
        cmake --build "$BUILD_DIR" --target "$bench" 2>&1 | tail -1
    done
    for bench in "${NEW_BENCHMARKS[@]}"; do
        flash_and_log "$bench" "$log_subdir/${bench}.log"
    done
}

# Dual bank — all 4 configs
echo "=== Setting dual bank ==="
make -C "$BUILD_DIR" stm32-flash-bank-dual 2>&1 | grep "flash mode" || true
sleep 2

for cfg in cache_pf cache_nopf nocache_pf nocache_nopf; do
    run_config "$(config_json_for $cfg)" "$cfg"
done

# Single bank — all 4 configs
echo ""
echo "=== Switching to single bank ==="
make -C "$BUILD_DIR" stm32-flash-bank-single 2>&1 | grep "flash mode"
sleep 2

for cfg in cache_pf cache_nopf nocache_pf nocache_nopf; do
    run_config "$(config_json_for $cfg)" "${cfg}_singlebank"
done

# Restore dual bank
echo ""
echo "=== Restoring dual bank ==="
make -C "$BUILD_DIR" stm32-flash-bank-dual 2>&1 | grep "flash mode"

echo ""
echo "Done. Re-parse:"
echo "  python3 benchmark/scripts/parse_logs.py benchmark_logs/ -o benchmark_logs/results.csv"
echo "  python3 benchmark/scripts/generate_art_tables.py benchmark_logs/results.csv"

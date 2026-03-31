#!/bin/bash
# Run fetch characterization benchmarks across cache/prefetch/bank configs.
#
# Usage:
#   ./benchmark/scripts/run_fetch_char.sh                    # all 4 configs, dual bank
#   ./benchmark/scripts/run_fetch_char.sh --config cache_pf  # single config
#   ./benchmark/scripts/run_fetch_char.sh --bank both        # dual + single bank (8 configs)
#   ./benchmark/scripts/run_fetch_char.sh --bank single      # single bank only
#   ./benchmark/scripts/run_fetch_char.sh --skip-build

set -euo pipefail
cd "$(dirname "$0")/../.."

SKIP_BUILD=0
RUN_CONFIGS=()
BANK_MODE="dual"  # dual, single, or both

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)   SKIP_BUILD=1 ;;
        --config)       RUN_CONFIGS+=("$2"); shift ;;
        --bank)         BANK_MODE="$2"; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
    shift
done

if [[ ${#RUN_CONFIGS[@]} -eq 0 ]]; then
    RUN_CONFIGS=(cache_pf cache_nopf nocache_pf nocache_nopf)
fi

BUILD_DIR="build-entobench"
LOG_DIR="benchmark_logs"
PRESET="stm32-g474re"

config_json_for() {
    case "$1" in
        cache_pf)      echo "configs/microbench.json" ;;
        cache_nopf)    echo "configs/microbench_noprefetch.json" ;;
        nocache_pf)    echo "configs/microbench_nocache.json" ;;
        nocache_nopf)  echo "configs/microbench_none.json" ;;
        *) echo ""; return 1 ;;
    esac
}

# Short kernels — use standard inner_reps (5000)
SHORT_BENCHMARKS=(
    bench-fetch_nop16_8
    bench-fetch_nop16_16
    bench-fetch_nop16_32
    bench-fetch_nop16_64
    bench-fetch_nop16_128
    bench-fetch_nop16_256
    bench-fetch_nop32_8
    bench-fetch_nop32_16
    bench-fetch_nop32_32
    bench-fetch_nop32_64
    bench-fetch_nop32_128
    bench-fetch_ws_validate
    bench-br_back_0
    bench-br_back_1
    bench-br_back_2
    bench-br_back_4
    bench-br_back_8
    bench-br_back_16
    bench-br_back_32
    bench-br_back_64
    bench-br_fwd_0
    bench-br_fwd_2
    bench-br_fwd_4
    bench-br_fwd_8
    bench-br_fwd_16
    bench-br_fwd_32
    bench-br_nottaken
    bench-fetch_seq_4
    bench-fetch_seq_8
    bench-fetch_seq_16
    bench-fetch_seq_32
    bench-fetch_interleave_mul
    bench-fetch_interleave_div
    bench-art_cap_32
    bench-art_cap_64
    bench-art_cap_128
    bench-art_cap_256
)

# Long kernels — need lower inner_reps
LONG_BENCHMARKS=(
    bench-art_cap_512
    bench-art_cap_1024
)

# V2 variants
V2_BENCHMARKS=(
    bench-alu_v2
    bench-alu16_v2
    bench-pushpop_v2
    bench-mixed_width_v2
    bench-bp_forward_v2
    bench-bp_nested_v2
)

set_bank_mode() {
    local mode="$1"
    echo ""
    echo "============================================"
    echo "  Setting flash bank mode: $mode"
    echo "============================================"
    if [[ "$mode" == "single" ]]; then
        make -C "$BUILD_DIR" stm32-flash-bank-single 2>&1 | grep -E "flash mode|written|load"
    elif [[ "$mode" == "dual" ]]; then
        make -C "$BUILD_DIR" stm32-flash-bank-dual 2>&1 | grep -E "flash mode|written|load"
    fi
    # Give the chip a moment after reset
    sleep 2
    # Verify
    echo "  Verifying..."
    make -C "$BUILD_DIR" stm32-flash-bank-read 2>&1 | grep "flash mode"
}

flash_and_log() {
    local target="$1"
    local log="$2"
    echo "  Flashing: $target"
    make -C "$BUILD_DIR" "stm32-flash-${target}-semihosted" 2>&1 | tee "$log" | grep -E "Average cycles:" | head -1
}

run_all_configs_for_bank() {
    local bank="$1"
    local bank_suffix="$2"  # "_dual" or "_single"

    for cfg in "${RUN_CONFIGS[@]}"; do
        json=$(config_json_for "$cfg")
        if [[ -z "$json" ]]; then
            echo "Unknown config: $cfg"
            exit 1
        fi

        local log_subdir="$LOG_DIR/${cfg}${bank_suffix}"
        mkdir -p "$log_subdir"

        # Standard reps for short benchmarks
        echo ""
        echo "=== ${cfg}${bank_suffix}: short benchmarks (inner_reps=5000) ==="
        if [[ $SKIP_BUILD -eq 0 ]]; then
            cmake --preset "$PRESET" -S benchmark \
                -DMICROBENCH_CONFIG_FILE="$json" 2>&1 | tail -1
            for bench in "${SHORT_BENCHMARKS[@]}" "${V2_BENCHMARKS[@]}"; do
                cmake --build "$BUILD_DIR" --target "$bench" 2>&1 | tail -1
            done
        fi
        for bench in "${SHORT_BENCHMARKS[@]}" "${V2_BENCHMARKS[@]}"; do
            flash_and_log "$bench" "$log_subdir/${bench}.log"
        done

        # Low reps for long benchmarks
        echo ""
        echo "=== ${cfg}${bank_suffix}: long benchmarks (inner_reps=100) ==="
        local lowreps_json="configs/_tmp_${cfg}_lowreps.json"
        python3 -c "
import json
with open('benchmark/$json') as f: d = json.load(f)
d['microbench']['inner_reps'] = 100
with open('benchmark/$lowreps_json', 'w') as f: json.dump(d, f, indent=4)
"
        if [[ $SKIP_BUILD -eq 0 ]]; then
            cmake --preset "$PRESET" -S benchmark \
                -DMICROBENCH_CONFIG_FILE="$lowreps_json" 2>&1 | tail -1
            for bench in "${LONG_BENCHMARKS[@]}"; do
                cmake --build "$BUILD_DIR" --target "$bench" 2>&1 | tail -1
            done
        fi
        for bench in "${LONG_BENCHMARKS[@]}"; do
            flash_and_log "$bench" "$log_subdir/${bench}.log"
        done

        rm -f "benchmark/$lowreps_json"
    done
}

# =============================================================================
# Main
# =============================================================================
mkdir -p "$LOG_DIR"

case "$BANK_MODE" in
    dual)
        set_bank_mode dual
        run_all_configs_for_bank dual ""
        ;;
    single)
        set_bank_mode single
        run_all_configs_for_bank single "_singlebank"
        # Restore dual bank when done
        set_bank_mode dual
        ;;
    both)
        set_bank_mode dual
        run_all_configs_for_bank dual ""

        set_bank_mode single
        run_all_configs_for_bank single "_singlebank"

        # Restore dual bank when done
        set_bank_mode dual
        ;;
    *)
        echo "Unknown bank mode: $BANK_MODE (use dual, single, or both)"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "  Fetch characterization complete."
echo "  Bank mode: $BANK_MODE"
echo "  Configs:   ${RUN_CONFIGS[*]}"
echo "  Logs:      $LOG_DIR/<config>/*.log"
echo "=========================================="
echo ""
echo "Parse results:"
echo "  python3 benchmark/scripts/parse_logs.py $LOG_DIR -o $LOG_DIR/results.csv"
echo "  python3 benchmark/scripts/analyze_fetch_char.py $LOG_DIR/results.csv"

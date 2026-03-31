#!/bin/bash
# Run fetch characterization benchmarks across all 4 cache/prefetch configs.
#
# Usage:
#   ./benchmark/scripts/run_fetch_char.sh
#   ./benchmark/scripts/run_fetch_char.sh --config cache_pf
#   ./benchmark/scripts/run_fetch_char.sh --skip-build

set -euo pipefail
cd "$(dirname "$0")/../.."

SKIP_BUILD=0
RUN_CONFIGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)   SKIP_BUILD=1 ;;
        --config)       RUN_CONFIGS+=("$2"); shift ;;
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

# Also run v2 variants
V2_BENCHMARKS=(
    bench-alu_v2
    bench-alu16_v2
    bench-pushpop_v2
    bench-mixed_width_v2
    bench-bp_forward_v2
    bench-bp_nested_v2
)

flash_and_log() {
    local target="$1"
    local log="$2"
    echo "  Flashing: $target"
    make -C "$BUILD_DIR" "stm32-flash-${target}-semihosted" 2>&1 | tee "$log" | grep -E "Average cycles:" | head -1
}

run_config() {
    local config_json="$1"
    local config_name="$2"
    local inner_reps_label="$3"
    local log_subdir="$LOG_DIR/$config_name"
    mkdir -p "$log_subdir"

    echo ""
    echo "############################################"
    echo "  Config: $config_name ($inner_reps_label)"
    echo "############################################"

    if [[ $SKIP_BUILD -eq 0 ]]; then
        local json_file="$config_json"
        # For long benchmarks, use low-reps version
        if [[ "$inner_reps_label" == "lowreps" ]]; then
            # Temporarily create a low-reps version of this config
            local base_json="$config_json"
            json_file="configs/_tmp_lowreps.json"
            python3 -c "
import json
with open('benchmark/$base_json') as f: d = json.load(f)
d['microbench']['inner_reps'] = 100
with open('benchmark/$json_file', 'w') as f: json.dump(d, f, indent=4)
"
        fi

        cmake --preset "$PRESET" -S benchmark \
            -DMICROBENCH_CONFIG_FILE="$json_file" 2>&1 | tail -1

        shift 3
        local benchmarks=("$@")
        for bench in "${benchmarks[@]}"; do
            cmake --build "$BUILD_DIR" --target "$bench" 2>&1 | tail -1
        done
    fi
}

run_and_flash() {
    local config_json="$1"
    local config_name="$2"
    local log_subdir="$LOG_DIR/$config_name"
    mkdir -p "$log_subdir"

    # Standard reps for short benchmarks
    echo ""
    echo "=== $config_name: short benchmarks (inner_reps=5000) ==="
    if [[ $SKIP_BUILD -eq 0 ]]; then
        cmake --preset "$PRESET" -S benchmark \
            -DMICROBENCH_CONFIG_FILE="$config_json" 2>&1 | tail -1
        for bench in "${SHORT_BENCHMARKS[@]}" "${V2_BENCHMARKS[@]}"; do
            cmake --build "$BUILD_DIR" --target "$bench" 2>&1 | tail -1
        done
    fi
    for bench in "${SHORT_BENCHMARKS[@]}" "${V2_BENCHMARKS[@]}"; do
        flash_and_log "$bench" "$log_subdir/${bench}.log"
    done

    # Low reps for long benchmarks
    echo ""
    echo "=== $config_name: long benchmarks (inner_reps=100) ==="
    local lowreps_json="configs/_tmp_${config_name}_lowreps.json"
    python3 -c "
import json
with open('benchmark/$config_json') as f: d = json.load(f)
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

    # Clean up temp json
    rm -f "benchmark/$lowreps_json"
}

mkdir -p "$LOG_DIR"

for cfg in "${RUN_CONFIGS[@]}"; do
    json=$(config_json_for "$cfg")
    if [[ -z "$json" ]]; then
        echo "Unknown config: $cfg"
        exit 1
    fi
    run_and_flash "$json" "$cfg"
done

echo ""
echo "=========================================="
echo "  Fetch characterization complete."
echo "  Configs: ${RUN_CONFIGS[*]}"
echo "  Logs:    $LOG_DIR/<config>/*.log"
echo "=========================================="
echo ""
echo "Parse results:"
echo "  python3 benchmark/scripts/parse_logs.py $LOG_DIR -o $LOG_DIR/results.csv"
echo "  python3 benchmark/scripts/logs_to_latex.py $LOG_DIR/results.csv"

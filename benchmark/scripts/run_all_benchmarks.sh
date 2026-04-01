#!/bin/bash
# Run all microbenchmarks on STM32G474RE.
#
# Usage:
#   ./benchmark/scripts/run_all_benchmarks.sh                      # all 4 configs, dual bank, inline
#   ./benchmark/scripts/run_all_benchmarks.sh --skip-build         # flash only
#   ./benchmark/scripts/run_all_benchmarks.sh --config cache_pf    # single config
#   ./benchmark/scripts/run_all_benchmarks.sh --bank both          # dual + single bank
#   ./benchmark/scripts/run_all_benchmarks.sh --policy noinline    # noinline kernel policy
#   ./benchmark/scripts/run_all_benchmarks.sh --policy both        # run inline then noinline
#
# Configurations (compile-time, cache/prefetch):
#   cache_pf     - cache ON,  prefetch ON
#   cache_nopf   - cache ON,  prefetch OFF
#   nocache_pf   - cache OFF, prefetch ON
#   nocache_nopf - cache OFF, prefetch OFF
#
# Bank modes (hardware, set via OpenOCD option bytes):
#   dual   - 64-bit fetch (default)
#   single - 128-bit fetch
#   both   - run dual then single
#
# Inline policies (compile-time):
#   inline   - kernel inlined into harness loop (default)
#   noinline - kernel in separate noinline function
#   both     - run inline then noinline
#
# Output: benchmark_logs/<config>[_singlebank][_noinline]/<name>.log

set -euo pipefail
cd "$(dirname "$0")/../.."

SKIP_BUILD=0
RUN_CONFIGS=()
BANK_MODE="dual"
POLICY_MODE="inline"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)   SKIP_BUILD=1 ;;
        --config)       RUN_CONFIGS+=("$2"); shift ;;
        --bank)         BANK_MODE="$2"; shift ;;
        --policy)       POLICY_MODE="$2"; shift ;;
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

# Create a temp JSON with overrides applied
make_json_override() {
    local base_json="$1"
    local out_json="$2"
    shift 2
    # Remaining args are key=value pairs
    local overrides="$*"
    python3 -c "
import json, sys
with open('benchmark/$base_json') as f: d = json.load(f)
for pair in '$overrides'.split():
    k, v = pair.split('=')
    try: v = int(v)
    except: pass
    d['microbench'][k] = v
with open('benchmark/$out_json', 'w') as f: json.dump(d, f, indent=4)
"
}

BENCHMARKS=(
    # Compute
    bench-nop
    bench-alu
    bench-alu16
    bench-mul
    bench-div
    bench-div_short
    bench-pushpop
    bench-fpu
    bench-dmb
    bench-mixed_width
    # Memory
    bench-load
    bench-load_dep
    bench-store
    bench-store_burst
    bench-ldr_literal
    bench-ccm_sram
    bench-scs_read
    bench-scs_store
    # Cache/Prefetch
    bench-art_prefetch
    bench-icache_miss
    # Branch
    bench-branch
    bench-bp_tight
    bench-bp_long_body
    bench-bp_forward
    bench-bp_alternating
    bench-bp_nested
    bench-bp_align
    # V2 variants
    bench-alu_v2
    bench-alu16_v2
    bench-pushpop_v2
    bench-mixed_width_v2
    bench-bp_forward_v2
    bench-bp_nested_v2
    # Fetch characterization
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
    bench-art_cap_512
)

# Long kernels — need lower inner_reps to avoid multi-minute runs
LONG_BENCHMARKS=(
    bench-art_cap_1024
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
    sleep 2
    echo "  Verifying..."
    make -C "$BUILD_DIR" stm32-flash-bank-read 2>&1 | grep "flash mode"
}

flash_and_log() {
    local target="$1"
    local log="$2"
    local label="$3"
    echo "  Flashing: $label"
    make -C "$BUILD_DIR" "stm32-flash-${target}-semihosted" 2>&1 | tee "$log" | grep -E "Average cycles:" | head -1
}

record_sizes() {
    local label="$1"
    echo "=== $label ===" >> "$LOG_DIR/flash_sizes.txt"
    for bench in "${BENCHMARKS[@]}"; do
        local elf="$BUILD_DIR/bin/${bench}.elf"
        if [[ -f "$elf" ]]; then
            printf "%-30s " "$bench" >> "$LOG_DIR/flash_sizes.txt"
            arm-none-eabi-size "$elf" | tail -1 >> "$LOG_DIR/flash_sizes.txt"
        fi
    done
    echo "" >> "$LOG_DIR/flash_sizes.txt"
}

run_config() {
    local config_json="$1"
    local config_name="$2"
    local log_subdir="$LOG_DIR/$config_name"
    mkdir -p "$log_subdir"

    echo ""
    echo "############################################"
    echo "  Configuration: $config_name"
    echo "  Config file:   $config_json"
    echo "############################################"

    # Standard benchmarks
    if [[ $SKIP_BUILD -eq 0 ]]; then
        echo "[build] Configuring with $config_json"
        cmake --preset "$PRESET" -S benchmark \
            -DMICROBENCH_CONFIG_FILE="$config_json" 2>&1 | tail -1

        echo "[build] Building all benchmarks"
        for bench in "${BENCHMARKS[@]}" "${LONG_BENCHMARKS[@]}"; do
            cmake --build "$BUILD_DIR" --target "$bench" 2>&1 | tail -1
        done
    fi

    record_sizes "$config_name"

    for bench in "${BENCHMARKS[@]}"; do
        flash_and_log "$bench" "$log_subdir/${bench}.log" "$bench ($config_name)"
    done

    # Long benchmarks with reduced inner_reps
    if [[ ${#LONG_BENCHMARKS[@]} -gt 0 ]]; then
        local lowreps_json="configs/_tmp_lowreps.json"
        make_json_override "$config_json" "$lowreps_json" "inner_reps=100"
        if [[ $SKIP_BUILD -eq 0 ]]; then
            cmake --preset "$PRESET" -S benchmark \
                -DMICROBENCH_CONFIG_FILE="$lowreps_json" 2>&1 | tail -1
            for bench in "${LONG_BENCHMARKS[@]}"; do
                cmake --build "$BUILD_DIR" --target "$bench" 2>&1 | tail -1
            done
        fi
        for bench in "${LONG_BENCHMARKS[@]}"; do
            flash_and_log "$bench" "$log_subdir/${bench}.log" "$bench ($config_name, lowreps)"
        done
        rm -f "benchmark/$lowreps_json"
    fi
}

run_all_configs_for_bank_and_policy() {
    local bank_suffix="$1"    # "" or "_singlebank"
    local policy_suffix="$2"  # "" or "_noinline"
    local policy_val="$3"     # 0 or 1

    for cfg in "${RUN_CONFIGS[@]}"; do
        local base_json
        base_json=$(config_json_for "$cfg")
        if [[ -z "$base_json" ]]; then
            echo "Unknown config: $cfg"
            exit 1
        fi

        local config_name="${cfg}${bank_suffix}${policy_suffix}"

        if [[ "$policy_val" -eq 0 ]]; then
            run_config "$base_json" "$config_name"
        else
            local tmp_json="configs/_tmp_${cfg}_policy${policy_val}.json"
            make_json_override "$base_json" "$tmp_json" "inline_policy=$policy_val"
            run_config "$tmp_json" "$config_name"
            rm -f "benchmark/$tmp_json"
        fi
    done
}

run_for_bank() {
    local bank_suffix="$1"

    case "$POLICY_MODE" in
        inline)
            run_all_configs_for_bank_and_policy "$bank_suffix" "" 0
            ;;
        noinline)
            run_all_configs_for_bank_and_policy "$bank_suffix" "_noinline" 1
            ;;
        both)
            run_all_configs_for_bank_and_policy "$bank_suffix" "" 0
            run_all_configs_for_bank_and_policy "$bank_suffix" "_noinline" 1
            ;;
        *)
            echo "Unknown policy: $POLICY_MODE (use inline, noinline, or both)"
            exit 1
            ;;
    esac
}

# =============================================================================
# Main
# =============================================================================
mkdir -p "$LOG_DIR"
> "$LOG_DIR/flash_sizes.txt"

case "$BANK_MODE" in
    dual)
        set_bank_mode dual
        run_for_bank ""
        ;;
    single)
        set_bank_mode single
        run_for_bank "_singlebank"
        set_bank_mode dual
        ;;
    both)
        set_bank_mode dual
        run_for_bank ""
        set_bank_mode single
        run_for_bank "_singlebank"
        set_bank_mode dual
        ;;
    *)
        echo "Unknown bank mode: $BANK_MODE (use dual, single, or both)"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "  All benchmarks complete."
echo "  Bank:   $BANK_MODE"
echo "  Policy: $POLICY_MODE"
echo "  Configs: ${RUN_CONFIGS[*]}"
echo "  Logs:    $LOG_DIR/<config>/*.log"
echo "  Sizes:   $LOG_DIR/flash_sizes.txt"
echo "=========================================="
echo ""
echo "Parse results:"
echo "  python3 benchmark/scripts/parse_logs.py $LOG_DIR -o $LOG_DIR/results.csv"
echo "  python3 benchmark/scripts/logs_to_latex.py $LOG_DIR/results.csv"

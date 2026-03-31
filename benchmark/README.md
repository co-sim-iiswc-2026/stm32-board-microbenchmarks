# STM32 Cortex-M4 Microbenchmarks

Microbenchmarks for the STM32G474RE (Cortex-M4F) targeting both real hardware
and gem5 simulation. Each benchmark is a small inline-asm kernel measured via
the EntoBench harness framework.

## Prerequisites

- **Toolchain**: `arm-none-eabi-gcc` (tested with 13.2.1)
  ```
  sudo apt install gcc-arm-none-eabi
  ```
- **CMake** >= 3.21
- **EntoBench submodule** (must be initialized):
  ```
  git submodule update --init --recursive
  ```
- **OpenOCD** (optional, only needed for flashing to real hardware)

## Build Variants

There are two build variants controlled by CMake options:

| Variant | `GEM5_SIM` | `GEM5_SEMIHOSTING` | ROI Mechanism | Use Case |
|---------|------------|---------------------|---------------|----------|
| **STM32 (hardware)** | OFF | OFF | DWT cycle counters | Run on real STM32G474RE board |
| **gem5 (simulation)** | ON | ON | BKPT semihosting | Run in gem5 M-profile simulator |

When `GEM5_SIM=ON`, hardware peripheral init (RCC clock config, cache/prefetch
enable) is skipped since gem5 doesn't model these peripherals.

## Building

All commands are run from the `benchmark/` directory.

### STM32 Hardware Build

```bash
cd benchmark

# Configure (uses the stm32-g474re preset)
cmake --preset stm32-g474re -B ../build-stm32

# Build all benchmarks
cmake --build ../build-stm32 -j$(nproc)

# Or build a specific benchmark
cmake --build ../build-stm32 --target bench-nop
```

ELF binaries are placed in `../build-stm32/bin/`.

### gem5 Simulation Build

```bash
cd benchmark

# Configure with gem5 flags
cmake --preset stm32-g474re -B ../build-gem5 \
    -DGEM5_SIM=ON -DGEM5_SEMIHOSTING=ON

# Build all benchmarks
cmake --build ../build-gem5 -j$(nproc)

# Or build a specific benchmark
cmake --build ../build-gem5 --target bench-nop
```

ELF binaries are placed in `../build-gem5/bin/`.

### Build with a Different Config

The harness parameters (reps, warmup, cache/prefetch) are controlled by a JSON
config file. Available configs are in `configs/`:

| Config File | Reps | Inner Reps | Cache | Prefetch | Notes |
|---|---|---|---|---|---|
| `microbench.json` | 10 | 5000 | ON | ON | Default for hardware |
| `microbench_gem5.json` | 2 | 1 | ON | ON | Fast gem5 runs |
| `microbench_nocache.json` | 10 | 5000 | OFF | ON | I-cache disabled |
| `microbench_noprefetch.json` | 10 | 5000 | ON | OFF | ART prefetch disabled |
| `microbench_none.json` | 10 | 5000 | OFF | OFF | No cache, no prefetch |
| `microbench_lowreps.json` | 10 | 100 | ON | ON | Quick sanity check |

To use a specific config:

```bash
cmake --preset stm32-g474re -B ../build-gem5 \
    -DGEM5_SIM=ON -DGEM5_SEMIHOSTING=ON \
    -DMICROBENCH_CONFIG_FILE="configs/microbench_gem5.json"
```

## Benchmark List

### Compute
| Target | Kernel | Description |
|---|---|---|
| `bench-nop` | 100 NOPs | Pipeline throughput baseline |
| `bench-alu` | 100 ALU (32-bit) | ADD/SUB/AND/ORR throughput |
| `bench-alu16` | 100 ALU (16-bit) | 16-bit Thumb encoding throughput |
| `bench-mul` | 100 MUL.W | 32x32 multiply throughput |
| `bench-div` | 20 SDIV | Worst-case divide (0x7FFFFFFF / 1) |
| `bench-div_short` | 20 SDIV | Best-case divide (15 / 3) |
| `bench-pushpop` | PUSH/POP | Multi-register stack operations |
| `bench-fpu` | FP add/mul/div | Single-precision FP throughput |
| `bench-dmb` | DMB/DSB/ISB | Memory barrier latency |
| `bench-mixed_width` | 16+32-bit mix | Alternating instruction widths |

### Memory
| Target | Kernel | Description |
|---|---|---|
| `bench-load` | 50 LDR | Independent loads from SRAM |
| `bench-load_dep` | 50 LDR (chain) | Dependent (serialized) loads |
| `bench-store` | 50 STR | Stores to same address |
| `bench-store_burst` | 50 STR | Stores to consecutive addresses |
| `bench-ldr_literal` | 50 LDR literal | PC-relative literal pool loads |
| `bench-ccm_sram` | 50 LDR + 50 STR | CCM SRAM (0x10000000) access |
| `bench-scs_read` | 50 SCS reads | System Control Space register reads |
| `bench-scs_store` | 50 SCS writes | System Control Space register writes |

### Cache / Prefetch
| Target | Kernel | Description |
|---|---|---|
| `bench-art_prefetch` | 200 NOPs (aligned) | ART accelerator prefetch behavior |
| `bench-icache_miss` | 4x 2KB NOP sled | I-cache capacity miss |

### Branch Prediction
| Target | Kernel | Description |
|---|---|---|
| `bench-branch` | 100-iter loop | Tight backward branch |
| `bench-bp_tight` | 200-iter loop | Tight backward branch (longer) |
| `bench-bp_long_body` | 100-iter, 8 NOPs | Loop with larger body |
| `bench-bp_forward` | 100-iter, BEQ fwd | Always-taken forward branch |
| `bench-bp_alternating` | 200-iter, odd/even | Alternating taken/not-taken |
| `bench-bp_nested` | 20x10 nested | Nested loop branches |
| `bench-bp_align` | 3x100-iter | Branch target alignment effects |

### V2 Variants
Benchmarks suffixed `_v2` use register assignments matching the original
standalone `.S` kernels (independent destination registers, original encoding
choices). Only benchmarks that differ from v1 are included:
`alu_v2`, `alu16_v2`, `pushpop_v2`, `mixed_width_v2`, `bp_forward_v2`, `bp_nested_v2`.

### Fetch Characterization
Benchmarks prefixed `fetch_*`, `br_*`, and `art_cap_*` characterize the
Cortex-M4 instruction fetch pipeline and ART accelerator behavior at various
code sizes and branch distances.

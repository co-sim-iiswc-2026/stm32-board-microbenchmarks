# =============================================================================
# STM32G474RE Microbenchmarks — EntoBench Integration
# =============================================================================
include(${CMAKE_SOURCE_DIR}/entobench_helpers.cmake)

if(NOT STM32_BUILD)
  message(STATUS "Microbenchmarks require STM32_BUILD — skipping")
  return()
endif()

if(NOT DEFINED MICROBENCH_CONFIG_FILE)
  set(MICROBENCH_CONFIG_FILE "configs/microbench.json")
endif()

# gem5 semihosting ROI: uses BKPT #0xAB to call gem5 pseudo-ops
option(GEM5_SEMIHOSTING "Use gem5 semihosting for ROI markers instead of DWT counters" OFF)
# gem5 simulation mode: skips RCC/PWR/Flash/SysTick init that gem5 doesn't model
option(GEM5_SIM "Target gem5 simulation (skip hardware peripheral init)" OFF)

# GEM5_SEMIHOSTING implies GEM5_SIM
if(GEM5_SEMIHOSTING AND NOT GEM5_SIM)
  set(GEM5_SIM ON CACHE BOOL "Implied by GEM5_SEMIHOSTING" FORCE)
endif()

# Force NoInline kernel policy on every build path so the kernel body
# sits inside `call_noinline` on board and gem5 — required for byte-
# identical kernel between ROI markers (board↔gem5 cycle parity).
add_definitions(-DINLINE_POLICY=1)

if(GEM5_SIM)
  add_definitions(-DGEM5_SIM=1)
  message(STATUS "gem5 simulation mode — peripheral init skipped")
endif()
if(GEM5_SEMIHOSTING)
  add_definitions(-DGEM5_SEMIHOSTING=1)
  message(STATUS "gem5 semihosting ROI enabled — DWT counters disabled")
endif()

# Libraries needed by all microbenchmarks
set(MODULES
  bench
  ento-mcu-semihosted
  CMSIS::STM32::${STM_PRODUCT}
)

# =============================================================================
# Define all simple (non-exception) microbenchmarks
# =============================================================================
set(MICROBENCHMARKS
    # --- Compute ---
    nop
    alu
    alu16
    mul
    div
    div_short
    pushpop
    fpu
    dmb
    mixed_width
    # --- Memory ---
    load
    load_dep
    store
    store_burst
    ldr_literal
    ccm_sram
    scs_read
    scs_store
    # --- Cache/Prefetch ---
    art_prefetch
    icache_miss
    # --- Branch/Branch Prediction ---
    branch
    bp_tight
    bp_long_body
    bp_forward
    bp_alternating
    bp_nested
    bp_align
)

# V2 variants: match original src/*.S register usage (independent destinations,
# original register choices). Only benchmarks that differ from v1 are included.
set(MICROBENCHMARKS_V2
    alu_v2
    alu16_v2
    pushpop_v2
    mixed_width_v2
    bp_forward_v2
    bp_nested_v2
)

# Fetch characterization benchmarks
set(MICROBENCHMARKS_FETCH
    # Group 1: Flash fetch baseline
    fetch_nop16_8
    fetch_nop16_16
    fetch_nop16_32
    fetch_nop16_64
    fetch_nop16_128
    fetch_nop16_256
    fetch_nop32_8
    fetch_nop32_16
    fetch_nop32_32
    fetch_nop32_64
    fetch_nop32_128
    fetch_ws_validate
    # Group 2: Branch distance
    br_back_0
    br_back_1
    br_back_2
    br_back_4
    br_back_8
    br_back_16
    br_back_32
    br_back_64
    br_fwd_0
    br_fwd_2
    br_fwd_4
    br_fwd_8
    br_fwd_16
    br_fwd_32
    br_nottaken
    # Group 3: Fetch pipeline
    fetch_seq_4
    fetch_seq_8
    fetch_seq_16
    fetch_seq_32
    fetch_interleave_mul
    fetch_interleave_div
    # Group 4: ART cache capacity
    art_cap_32
    art_cap_64
    art_cap_128
    art_cap_256
    art_cap_512
    art_cap_1024
    # Group 4b: ART cache capacity — 32-bit
    art_cap32_64
    art_cap32_128
    art_cap32_256
    # Group 4c: ART cache capacity — mixed width
    art_capmix_32
    art_capmix_64
    art_capmix_128
    art_capmix_256
    # Group 4d: ART cache capacity — different mix ratios
    art_mix3x1_64
    art_mix3x1_128
    art_mix1x3_64
    art_mix1x3_128
)

# Track all targets for group operations
set(BENCH_TARGETS)

foreach(bench ${MICROBENCHMARKS})
    set(TARGET_NAME bench-${bench})

    set(EXTRA_SOURCES "")
    if(bench STREQUAL "icache_miss")
      set(EXTRA_SOURCES kernel_icache_miss.S)
    endif()

    add_benchmark(${TARGET_NAME}
      SOURCES microbench_main.cc ${EXTRA_SOURCES}
      LIBRARIES ${MODULES}
    )

    target_compile_definitions(${TARGET_NAME} PRIVATE
      KERNEL_FN=bench_${bench}_kernel
      KERNEL_NAME=bench_${bench}
    )

    target_include_directories(${TARGET_NAME} PRIVATE
      ${EIGEN_DIR}
      ${CMAKE_CURRENT_SOURCE_DIR}/include
      ${CMAKE_CURRENT_SOURCE_DIR}
    )

    list(APPEND BENCH_TARGETS ${TARGET_NAME})
endforeach()

# V2 benchmarks (match original src/*.S register usage and encodings)
foreach(bench ${MICROBENCHMARKS_V2})
    set(TARGET_NAME bench-${bench})

    add_benchmark(${TARGET_NAME}
      SOURCES microbench_main.cc
      LIBRARIES ${MODULES}
    )

    target_compile_definitions(${TARGET_NAME} PRIVATE
      KERNEL_FN=bench_${bench}_kernel
      KERNEL_NAME=bench_${bench}
    )

    target_include_directories(${TARGET_NAME} PRIVATE
      ${EIGEN_DIR}
      ${CMAKE_CURRENT_SOURCE_DIR}/include
      ${CMAKE_CURRENT_SOURCE_DIR}
    )

    list(APPEND BENCH_TARGETS ${TARGET_NAME})
endforeach()

# Fetch characterization benchmarks
foreach(bench ${MICROBENCHMARKS_FETCH})
    set(TARGET_NAME bench-${bench})

    set(EXTRA_SOURCES "")
    if(bench STREQUAL "art_cap_1024")
      set(EXTRA_SOURCES kernel_art_cap_1024.S)
    elseif(bench STREQUAL "art_mix1x3_128")
      set(EXTRA_SOURCES kernel_art_mix1x3_128.S)
    endif()

    add_benchmark(${TARGET_NAME}
      SOURCES microbench_main.cc ${EXTRA_SOURCES}
      LIBRARIES ${MODULES}
    )

    target_compile_definitions(${TARGET_NAME} PRIVATE
      KERNEL_FN=bench_${bench}_kernel
      KERNEL_NAME=bench_${bench}
    )

    target_include_directories(${TARGET_NAME} PRIVATE
      ${EIGEN_DIR}
      ${CMAKE_CURRENT_SOURCE_DIR}/include
      ${CMAKE_CURRENT_SOURCE_DIR}
    )

    list(APPEND BENCH_TARGETS ${TARGET_NAME})
endforeach()

# =============================================================================
# Inline-asm harness benchmarks (lambda inlined into harness loop)
# =============================================================================
set(INLINE_HARNESS_BENCHMARKS
    bench-nop-harness-inline
    bench-alu16-harness-inline
)

foreach(tgt ${INLINE_HARNESS_BENCHMARKS})
    string(REPLACE "-" "_" src_name ${tgt})
    add_benchmark(${tgt}
      SOURCES ${src_name}.cc
      LIBRARIES ${MODULES}
    )
    target_include_directories(${tgt} PRIVATE
      ${EIGEN_DIR}
      ${CMAKE_CURRENT_SOURCE_DIR}/include
      ${CMAKE_CURRENT_SOURCE_DIR}
    )
    list(APPEND BENCH_TARGETS ${tgt})
endforeach()

# =============================================================================
# Hand-written differential tests (board-vs-gem5 byte-exact capture)
# =============================================================================
set(HANDWRITTEN_BENCHMARKS
    bench-vmul
    bench-tinympc-diff
    bench-vldm-vstm
    bench-vmov
    bench-vpush-vpop
    bench-matvec-12x12
    bench-vldmia-d1
    bench-vldmia-d7wb
    bench-vldmia-d-range
    bench-vstmia-d-range
    bench-vcmpe-vmovcond
    # Preamble-zeroing unit tests (pin down the "zero s0..s31" path
    # used by Level A/B so any decoder bug there is caught in isolation).
    bench-preamble-zero-vmov-dpair
    bench-preamble-zero-vmov-ssingle
    bench-preamble-zero-vldr
)

foreach(tgt ${HANDWRITTEN_BENCHMARKS})
    string(REPLACE "-" "_" src_name ${tgt})
    add_benchmark(${tgt}
      SOURCES ${src_name}.cc
      LIBRARIES ${MODULES}
    )
    target_include_directories(${tgt} PRIVATE
      ${EIGEN_DIR}
      ${CMAKE_CURRENT_SOURCE_DIR}/include
      ${CMAKE_CURRENT_SOURCE_DIR}
    )
    list(APPEND BENCH_TARGETS ${tgt})
endforeach()

# TinyMPC iteration-count variants — same .cc, different TINYMPC_MAX_ITER.
# Used to bisect ADMM iteration count when hunting board↔gem5 divergence.
# iter=0 is diagnostic: validates the solver actually iterates (if u[0] at
# iter=0 equals iter=1, solver isn't doing anything).
set(TINYMPC_ITER_VARIANTS 0 1 5 20 50)
foreach(iter ${TINYMPC_ITER_VARIANTS})
    set(variant_tgt "bench-tinympc-diff-iter${iter}")
    set(variant_name "bench_tinympc_diff_iter${iter}")
    add_benchmark(${variant_tgt}
      SOURCES bench_tinympc_diff.cc
      LIBRARIES ${MODULES}
    )
    target_include_directories(${variant_tgt} PRIVATE
      ${EIGEN_DIR}
      ${CMAKE_CURRENT_SOURCE_DIR}/include
      ${CMAKE_CURRENT_SOURCE_DIR}
    )
    target_compile_definitions(${variant_tgt} PRIVATE
      TINYMPC_MAX_ITER=${iter}
      BENCH_NAME=${variant_name}
    )
    list(APPEND BENCH_TARGETS ${variant_tgt})
endforeach()

# =============================================================================
# Generated FPU capture benchmarks (verification/gen/fpu_single.py)
# =============================================================================
file(GLOB GENERATED_FPU_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/generated/bench_fpu_*.cc"
)

foreach(src ${GENERATED_FPU_SOURCES})
    get_filename_component(src_name ${src} NAME_WE)
    string(REPLACE "_" "-" tgt ${src_name})
    add_benchmark(${tgt}
      SOURCES generated/${src_name}.cc
      LIBRARIES ${MODULES}
    )
    target_include_directories(${tgt} PRIVATE
      ${EIGEN_DIR}
      ${CMAKE_CURRENT_SOURCE_DIR}/include
      ${CMAKE_CURRENT_SOURCE_DIR}
    )
    list(APPEND BENCH_TARGETS ${tgt})
endforeach()

# =============================================================================
# Inline-asm benchmarks (ROI inside function, compiler-managed layout)
# =============================================================================
add_benchmark(bench-inline
  SOURCES inline_benchmarks.cc
  LIBRARIES ${MODULES}
)
target_include_directories(bench-inline PRIVATE
  ${EIGEN_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}
)
list(APPEND BENCH_TARGETS bench-inline)

# =============================================================================
# SDIV latency calibration set (subdir)
# =============================================================================
# Adds bench-sdiv-cal-* targets and the microbench-sdiv-calibration-all group
# target.  Appends to BENCH_TARGETS so microbench-all picks them up; also
# exports SDIV_CAL_TARGETS for the cycle-bench compile-options pass below.
add_subdirectory(sdiv_calibration)

# =============================================================================
# FPU-ALU latency calibration set (subdir)
# =============================================================================
# Adds bench-fpu-cal-* targets and the microbench-fpu-calibration-all group
# target.  Appends to BENCH_TARGETS so microbench-all picks them up; also
# exports FPU_CAL_TARGETS for the cycle-bench compile-options pass below.
add_subdirectory(fpu_calibration)

# Aggregate build target: everything under microbench/, nothing else.
# Use this instead of `cmake --build` with no --target to avoid pulling in
# unrelated (and currently-broken) ento-bench test/benchmark subdirs.
add_custom_target(microbench-all DEPENDS ${BENCH_TARGETS})

# =============================================================================
# Configure benchmark group from JSON (must be after all targets are added)
# =============================================================================
add_configured_benchmark_group_with_target_configs("microbench"
  TARGETS ${BENCH_TARGETS}
  CONFIG_FILE "${CMAKE_SOURCE_DIR}/${MICROBENCH_CONFIG_FILE}"
)

# Two compile-time override sets — diff-style tests vs cycle benchmarks.
#
# Diff-style tests (HANDWRITTEN_BENCHMARKS, TinyMPC iter variants,
# generated FPU): REPS=1, INNER_REPS=1, DO_WARMUP=0.  These observe a
# single point-in-time byte snapshot; multi-rep cascades solver/asm
# state across calls and breaks per-iter gating (most visibly on
# TinyMPC, where MAX_ITER=1 silently becomes "many" because the static
# Solver retains state across the harness's 50001 calls).
#
# Cycle benchmarks (MICROBENCHMARKS, *_V2, *_FETCH, INLINE_HARNESS):
# REPS=2, INNER_REPS=1, DO_WARMUP=0.  Reps==1 hits an upstream bug in
# EntoBench's harness.h — when Reps==1 the per-rep measurement lands
# in `rep_metrics_` but `print_metrics(metrics_, …)` reads the
# never-assigned `metrics_` and emits "Cycles = 0".  Bumping to REPS=2
# routes through the working `Reps > 1` path which calls
# `print_rep_metrics(rep_metrics_, …)` per iteration.
#
# Using target_compile_options with -U/-D (applied AFTER
# target_compile_defs from the configured benchmark group) guarantees
# the override wins.

# Cycle-measurement targets — derived from the lists above.
set(CYCLE_BENCH_TARGETS)
foreach(bench ${MICROBENCHMARKS} ${MICROBENCHMARKS_V2} ${MICROBENCHMARKS_FETCH})
    list(APPEND CYCLE_BENCH_TARGETS bench-${bench})
endforeach()
list(APPEND CYCLE_BENCH_TARGETS ${INLINE_HARNESS_BENCHMARKS})
# SDIV calibration targets are also cycle-measurement (REPS=2, DO_WARMUP=0).
list(APPEND CYCLE_BENCH_TARGETS ${SDIV_CAL_TARGETS})
# FPU-ALU calibration targets are cycle-measurement too (same compile opts).
list(APPEND CYCLE_BENCH_TARGETS ${FPU_CAL_TARGETS})

# Diff-style targets — every other benchmark (excluding bench-inline,
# which has its own ROI placement and stays at JSON defaults).
set(DIFF_BENCH_TARGETS ${BENCH_TARGETS})
list(REMOVE_ITEM DIFF_BENCH_TARGETS bench-inline)
foreach(tgt ${CYCLE_BENCH_TARGETS})
    list(REMOVE_ITEM DIFF_BENCH_TARGETS ${tgt})
endforeach()

foreach(tgt ${DIFF_BENCH_TARGETS})
    target_compile_options(${tgt} PRIVATE
      -UINNER_REPS -DINNER_REPS=1
      -UREPS        -DREPS=1
      -UDO_WARMUP   -DDO_WARMUP=0
    )
endforeach()

foreach(tgt ${CYCLE_BENCH_TARGETS})
    # INNER_REPS comes from the JSON config (microbench{,_gem5}.json:
    # inner_reps).  REPS=2 is forced to dodge the upstream Reps==1
    # print bug; DO_WARMUP=0 is forced so the first ROI is the measured
    # one (run_m5op_bench.py defaults to --roi-counter 0).
    target_compile_options(${tgt} PRIVATE
      -UREPS        -DREPS=2
      -UDO_WARMUP   -DDO_WARMUP=0
    )
endforeach()

# =============================================================================
# STM32 flash/debug targets (if OpenOCD is available)
# =============================================================================
if(OPENOCD_EXECUTABLE AND OPENOCD_INTERFACE)
  add_stm32_targets("${BENCH_TARGETS}")
endif()

# =============================================================================
# Flash bank mode targets (STM32G4 category 3 devices with dual-bank flash)
# =============================================================================
if(OPENOCD_EXECUTABLE AND OPENOCD_INTERFACE AND STM32_CHIP MATCHES "STM32G4(7[34]|8[34]|91|A1)")
  # Read current DBANK setting
  add_custom_target(stm32-flash-bank-read
    COMMAND ${OPENOCD_EXECUTABLE}
      -f "${OPENOCD_INTERFACE}"
      -f "${CMAKE_SOURCE_DIR}/openocd/${OPENOCD_CFG}"
      -c "init"
      -c "reset halt"
      -c "stm32l4x option_read 0 0x20"
      -c "shutdown"
    USES_TERMINAL
    COMMENT "Reading FLASH_OPTR (DBANK is bit 22)"
  )

  # Switch to single bank (128-bit fetch, clear DBANK bit 22)
  add_custom_target(stm32-flash-bank-single
    COMMAND ${OPENOCD_EXECUTABLE}
      -f "${OPENOCD_INTERFACE}"
      -f "${CMAKE_SOURCE_DIR}/openocd/${OPENOCD_CFG}"
      -c "init"
      -c "reset halt"
      -c "stm32l4x option_write 0 0x20 0x00000000 0x00400000"
      -c "stm32l4x option_load 0"
      -c "shutdown"
    USES_TERMINAL
    COMMENT "Setting single bank mode (DBANK=0, 128-bit fetch)"
  )

  # Switch to dual bank (64-bit fetch, set DBANK bit 22)
  add_custom_target(stm32-flash-bank-dual
    COMMAND ${OPENOCD_EXECUTABLE}
      -f "${OPENOCD_INTERFACE}"
      -f "${CMAKE_SOURCE_DIR}/openocd/${OPENOCD_CFG}"
      -c "init"
      -c "reset halt"
      -c "stm32l4x option_write 0 0x20 0x00400000 0x00400000"
      -c "stm32l4x option_load 0"
      -c "shutdown"
    USES_TERMINAL
    COMMENT "Setting dual bank mode (DBANK=1, 64-bit fetch)"
  )
endif()

# =============================================================================
# Summary
# =============================================================================
list(LENGTH BENCH_TARGETS BENCH_COUNT)
message(STATUS "Configured ${BENCH_COUNT} microbenchmark targets")

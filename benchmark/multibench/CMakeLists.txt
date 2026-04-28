# =============================================================================
# Multi-bench harness — STM32G474 Cortex-M4F microbench energy measurement
# =============================================================================
#
# Builds 16 firmware binaries: {core, memory} x {cache_pf, cache_nopf,
# nocache_pf, nocache_nopf} x {board, gem5}.
#
# - Board targets: defined LATENCY_MEASUREMENT — drive trigger/latency pins
#   for STLINK-V3PWR + Saleae trace edge capture. Uses the same STM32 toolchain.
# - gem5  targets: defined ARM_GEM5 + GEM5_SEMIHOSTING — emit m5op pseudo-ops
#   via BKPT 0xAB instead of GPIO toggles.
#
# Both flavors share generated/*.S and the same multibench main; only the
# per-target compile definitions differ.
#
# IMPORTANT: per project_differential_testing_status.md, gem5 ARM ISA decoder
# has a known bug with multi-d-register vldmia/vstmia (Zhantong's decoder fix
# pending). For v1, FPU benches are board-acceptance only — gem5 stat counts
# for the FPU rows are stretch-goal until the upstream fix lands.
include(${CMAKE_SOURCE_DIR}/entobench_helpers.cmake)

if(NOT STM32_BUILD)
  message(STATUS "Multibench requires STM32_BUILD — skipping")
  return()
endif()

# -----------------------------------------------------------------------------
# Generated kernel sources
# -----------------------------------------------------------------------------
file(GLOB MULTIBENCH_GENERATED_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/generated/kernel_*.S"
)

# Sanity check — bail loudly if codegen wasn't run.
list(LENGTH MULTIBENCH_GENERATED_SOURCES MULTIBENCH_KERNEL_COUNT)
if(MULTIBENCH_KERNEL_COUNT LESS 1)
    message(FATAL_ERROR
        "No generated kernels in ${CMAKE_CURRENT_SOURCE_DIR}/src/generated/. "
        "Run: python3 ${CMAKE_CURRENT_SOURCE_DIR}/tools/gen_kernels.py")
endif()
message(STATUS "Multibench: ${MULTIBENCH_KERNEL_COUNT} generated kernel(s)")

# Libraries needed by every multibench target (same as microbench).
set(MULTIBENCH_MODULES
    bench
    ento-mcu-semihosted
    CMSIS::STM32::${STM_PRODUCT}
)

# -----------------------------------------------------------------------------
# Per-config compile definitions
# -----------------------------------------------------------------------------
# These set ENABLE_CACHES / ENABLE_PREFETCH for ENTO_BENCH_SETUP() to consume,
# matching the JSON config files that microbench/CMakeLists.txt reads. We use
# direct -D flags here (vs the JSON path) because multibench targets don't
# share the json-driven Harness machinery — we bypass it for MultiHarness.
function(_multibench_apply_config TGT CONFIG)
    if(CONFIG STREQUAL "cache_pf")
        target_compile_definitions(${TGT} PRIVATE ENABLE_CACHES=1 ENABLE_PREFETCH=1)
    elseif(CONFIG STREQUAL "cache_nopf")
        target_compile_definitions(${TGT} PRIVATE ENABLE_CACHES=1 ENABLE_PREFETCH=0)
    elseif(CONFIG STREQUAL "nocache_pf")
        target_compile_definitions(${TGT} PRIVATE ENABLE_CACHES=0 ENABLE_PREFETCH=1)
    elseif(CONFIG STREQUAL "nocache_nopf")
        target_compile_definitions(${TGT} PRIVATE ENABLE_CACHES=0 ENABLE_PREFETCH=0)
    else()
        message(FATAL_ERROR "unknown multibench config: ${CONFIG}")
    endif()
endfunction()

# -----------------------------------------------------------------------------
# Target factory
# -----------------------------------------------------------------------------
# 16 targets total: {core, memory} x {cache_pf, cache_nopf, nocache_pf,
# nocache_nopf} x {board, gem5}.
set(MULTIBENCH_PARTITIONS core memory)
set(MULTIBENCH_CONFIGS    cache_pf cache_nopf nocache_pf nocache_nopf)
set(MULTIBENCH_FLAVORS    board gem5)

set(MULTIBENCH_TARGETS)

foreach(part ${MULTIBENCH_PARTITIONS})
  foreach(cfg ${MULTIBENCH_CONFIGS})
    foreach(flavor ${MULTIBENCH_FLAVORS})
      if(flavor STREQUAL "board")
        set(TGT "multibench-${part}-${cfg}")
      else()
        set(TGT "multibench-${part}-${cfg}-gem5")
      endif()

      add_benchmark(${TGT}
        SOURCES
          multibench_${part}_main.cc
          ${MULTIBENCH_GENERATED_SOURCES}
        LIBRARIES ${MULTIBENCH_MODULES}
      )

      target_include_directories(${TGT} PRIVATE
        ${EIGEN_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        # gem5 m5op semihosting header + the gem5/asm/generic/m5ops.h tree
        # live in microbench/. Reuse rather than duplicate so any future
        # tweak (e.g. new BKPT immediate) propagates to both harnesses.
        ${CMAKE_CURRENT_SOURCE_DIR}/../microbench
        ${CMAKE_CURRENT_SOURCE_DIR}/../microbench/include
      )

      _multibench_apply_config(${TGT} ${cfg})

      if(flavor STREQUAL "board")
        # Board: keep the STM32_BUILD path active in roi.h; LATENCY_MEASUREMENT
        # turns on GPIO pin choreography. STM32_BUILD is set globally by the
        # parent benchmark/CMakeLists.txt.
        target_compile_definitions(${TGT} PRIVATE
          LATENCY_MEASUREMENT=1
        )
      else()
        # gem5 flavor: turn on the GEM5_SEMIHOSTING + ARM_GEM5 paths in roi.h
        # so start_roi/end_roi emit m5op BKPT pseudo-ops. Also flag GEM5_SIM=1
        # so the multibench main skips peripheral init that gem5 doesn't model.
        target_compile_definitions(${TGT} PRIVATE
          GEM5_SEMIHOSTING=1
          ARM_GEM5=1
          GEM5_SIM=1
        )
      endif()

      list(APPEND MULTIBENCH_TARGETS ${TGT})
    endforeach()
  endforeach()
endforeach()

# -----------------------------------------------------------------------------
# Smoke target — single 5-bench binary used to validate the harness scaffold
# end-to-end before expanding to all 16 above.
# -----------------------------------------------------------------------------
add_benchmark(multibench-smoke
  SOURCES
    multibench_smoke_main.cc
    ${MULTIBENCH_GENERATED_SOURCES}
  LIBRARIES ${MULTIBENCH_MODULES}
)
target_include_directories(multibench-smoke PRIVATE
  ${EIGEN_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/src
  ${CMAKE_CURRENT_SOURCE_DIR}/../microbench
  ${CMAKE_CURRENT_SOURCE_DIR}/../microbench/include
)
_multibench_apply_config(multibench-smoke cache_pf)
target_compile_definitions(multibench-smoke PRIVATE LATENCY_MEASUREMENT=1)
list(APPEND MULTIBENCH_TARGETS multibench-smoke)

# Aggregate target so `cmake --build . --target multibench-all` builds the
# whole set without pulling in unrelated subdirs.
add_custom_target(multibench-all DEPENDS ${MULTIBENCH_TARGETS})

# -----------------------------------------------------------------------------
# OpenOCD flash/debug targets (board flavor only — gem5 targets don't flash).
# -----------------------------------------------------------------------------
if(OPENOCD_EXECUTABLE AND OPENOCD_INTERFACE)
  set(MULTIBENCH_BOARD_TARGETS)
  foreach(part ${MULTIBENCH_PARTITIONS})
    foreach(cfg ${MULTIBENCH_CONFIGS})
      list(APPEND MULTIBENCH_BOARD_TARGETS "multibench-${part}-${cfg}")
    endforeach()
  endforeach()
  list(APPEND MULTIBENCH_BOARD_TARGETS multibench-smoke)
  add_stm32_targets("${MULTIBENCH_BOARD_TARGETS}")
endif()

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
list(LENGTH MULTIBENCH_TARGETS MULTIBENCH_TARGET_COUNT)
message(STATUS "Configured ${MULTIBENCH_TARGET_COUNT} multibench targets "
               "(16 production + 1 smoke)")

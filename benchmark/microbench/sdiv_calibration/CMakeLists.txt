# =============================================================================
# SDIV latency-calibration microbenchmarks
# =============================================================================
# Each bench is the standard microbench_main.cc compiled with a different
# KERNEL_FN pointing at one of the kernels in sdiv_calibration/kernels.h.
# See README.md for the data the set produces.
#
# Group target: microbench-sdiv-calibration-all.  Build only this set
# with `cmake --build <build-dir> --target microbench-sdiv-calibration-all`.

set(MICROBENCHMARKS_SDIV_CAL
    sdiv-cal-baseline
    sdiv-cal-max-10
    sdiv-cal-max-20
    sdiv-cal-max-40
    sdiv-cal-mid-20
    sdiv-cal-short-10
    sdiv-cal-short-20
    sdiv-cal-short-40
)

# Track the calibration-set targets for the group custom target and
# for the cycle-bench compile-options pass below.
set(SDIV_CAL_TARGETS)

foreach(bench ${MICROBENCHMARKS_SDIV_CAL})
    set(TARGET_NAME bench-${bench})

    # The kernel function symbol from kernels.h uses underscores: the
    # bench name `sdiv-cal-max-20` maps to `bench_sdiv_cal_max_20_kernel`.
    string(REPLACE "-" "_" bench_us ${bench})

    add_benchmark(${TARGET_NAME}
      SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../microbench_main.cc
      LIBRARIES ${MODULES}
    )

    target_compile_definitions(${TARGET_NAME} PRIVATE
      KERNEL_FN=bench_${bench_us}_kernel
      KERNEL_NAME=bench_${bench_us}
    )

    # microbench_main.cc lives in the parent dir and includes the new
    # `sdiv_calibration/kernels.h`.  Both the parent and this dir need
    # to be on the include path.
    target_include_directories(${TARGET_NAME} PRIVATE
      ${EIGEN_DIR}
      ${CMAKE_CURRENT_SOURCE_DIR}/..
      ${CMAKE_CURRENT_SOURCE_DIR}/../include
      ${CMAKE_CURRENT_SOURCE_DIR}
    )

    list(APPEND SDIV_CAL_TARGETS ${TARGET_NAME})
    # Also pull into the parent's BENCH_TARGETS so the flash/`microbench-all`
    # aggregate sees these.
    list(APPEND BENCH_TARGETS ${TARGET_NAME})
endforeach()

# Group target — build only the calibration set.
add_custom_target(microbench-sdiv-calibration-all DEPENDS ${SDIV_CAL_TARGETS})

# Bubble the updated BENCH_TARGETS list up to the parent CMakeLists
# (which references it from this point on).
set(BENCH_TARGETS ${BENCH_TARGETS} PARENT_SCOPE)
# Bubble SDIV_CAL_TARGETS too so the parent can apply cycle-bench
# compile options (REPS=2, DO_WARMUP=0) and STM32 flash targets to
# these.
set(SDIV_CAL_TARGETS ${SDIV_CAL_TARGETS} PARENT_SCOPE)

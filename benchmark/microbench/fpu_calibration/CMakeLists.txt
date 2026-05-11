# =============================================================================
# FPU-ALU latency-calibration microbenchmarks
# =============================================================================
# One bench per FP-ALU instruction class gem5 models in
# `gem5/src/arch/arm/m_fp_insts.hh`.  Each is compiled from the standard
# microbench_main.cc with a different KERNEL_FN pointing at one of the
# kernels in fpu_calibration/kernels.h.
#
# Scope: FP-ALU only.  Memory FPU ops (VLDR/VSTR/VLDM/VSTM/VPUSH/VPOP)
# are tracked separately.
#
# Group target: microbench-fpu-calibration-all.  Build only this set with
# `cmake --build <build-dir> --target microbench-fpu-calibration-all`.

set(MICROBENCHMARKS_FPU_CAL
    fpu-cal-baseline
    fpu-cal-vadd
    fpu-cal-vsub
    fpu-cal-vmul
    fpu-cal-vnmul
    fpu-cal-vdiv
    fpu-cal-vmla
    fpu-cal-vmls
    fpu-cal-vfma
    fpu-cal-vfms
    fpu-cal-vneg
    fpu-cal-vabs
    fpu-cal-vsqrt
    fpu-cal-vmov-imm
    fpu-cal-vmov-reg
    fpu-cal-vmov-core-to-s
    fpu-cal-vmov-s-to-core
    fpu-cal-vcmp
    fpu-cal-vcmpe
    fpu-cal-vcvt-f32-s32
    fpu-cal-vcvt-s32-f32
    fpu-cal-vmrs
    fpu-cal-vmsr
)

# Track the calibration-set targets for the group custom target and
# for the cycle-bench compile-options pass below.
set(FPU_CAL_TARGETS)

foreach(bench ${MICROBENCHMARKS_FPU_CAL})
    set(TARGET_NAME bench-${bench})

    # The kernel function symbol from kernels.h uses underscores: the
    # bench name `fpu-cal-vadd` maps to `bench_fpu_cal_vadd_kernel`.
    string(REPLACE "-" "_" bench_us ${bench})

    add_benchmark(${TARGET_NAME}
      SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../microbench_main.cc
      LIBRARIES ${MODULES}
    )

    target_compile_definitions(${TARGET_NAME} PRIVATE
      KERNEL_FN=bench_${bench_us}_kernel
      KERNEL_NAME=bench_${bench_us}
    )

    # microbench_main.cc lives in the parent dir and includes
    # `fpu_calibration/kernels.h`.  Both the parent and this dir need
    # to be on the include path.
    target_include_directories(${TARGET_NAME} PRIVATE
      ${EIGEN_DIR}
      ${CMAKE_CURRENT_SOURCE_DIR}/..
      ${CMAKE_CURRENT_SOURCE_DIR}/../include
      ${CMAKE_CURRENT_SOURCE_DIR}
    )

    list(APPEND FPU_CAL_TARGETS ${TARGET_NAME})
    # Also pull into the parent's BENCH_TARGETS so the flash/`microbench-all`
    # aggregate sees these.
    list(APPEND BENCH_TARGETS ${TARGET_NAME})
endforeach()

# Group target — build only the calibration set.
add_custom_target(microbench-fpu-calibration-all DEPENDS ${FPU_CAL_TARGETS})

# Bubble the updated BENCH_TARGETS list up to the parent CMakeLists
# (which references it from this point on).
set(BENCH_TARGETS ${BENCH_TARGETS} PARENT_SCOPE)
# Bubble FPU_CAL_TARGETS too so the parent can apply cycle-bench
# compile options (REPS=2, DO_WARMUP=0) and STM32 flash targets to
# these.
set(FPU_CAL_TARGETS ${FPU_CAL_TARGETS} PARENT_SCOPE)

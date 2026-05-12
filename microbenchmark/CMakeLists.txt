cmake_minimum_required(VERSION 3.20)
project(microbenchmark ASM C)

# ---------------------------------------------------------------------------
# Preset-driven build. Three cache vars describe the build target:
#
#   -DPLATFORM=gem5         → gem5 simulation (m5op via BKPT #0xab)
#   -DPLATFORM=hardware     → real board (DWT CYCCNT)
#     -DHW_VARIANT=full|nocache|noprefetch|none      (hardware only)
#   -DBOARD=stm32g474re     → which board: picks linker script, openocd
#                             target cfg, I-cache size, and board-specific
#                             headers (dwt.h)
#
# Per-variant cache flags live in configs/<config>.cmake; per-board
# resources live in board/<board>/. Optional safety knobs:
#
#   -DALLOW_KERNEL_EXCEED_ICACHE=ON   skip the post-link check that
#                                      otherwise fails the build when a
#                                      kernel's kernel_body exceeds the
#                                      board's I-cache size.
#   -DALLOW_KERNEL_EXCEED_DCACHE=ON   same, for the kernel's declared
#                                      flash-resident data footprint
#                                      vs the board's D-cache size.
# ---------------------------------------------------------------------------

set(PLATFORM "" CACHE STRING "Target platform: gem5 | hardware")
set_property(CACHE PLATFORM PROPERTY STRINGS gem5 hardware)

if(NOT PLATFORM STREQUAL "gem5" AND NOT PLATFORM STREQUAL "hardware")
    message(FATAL_ERROR
        "Set -DPLATFORM=gem5 or -DPLATFORM=hardware (use a preset).")
endif()

set(BOARD "" CACHE STRING "Target board (directory name under board/)")
if(NOT BOARD)
    message(FATAL_ERROR
        "Set -DBOARD=<name> matching a directory under board/ (e.g. stm32g474re).")
endif()

if(PLATFORM STREQUAL "hardware" AND NOT DEFINED HW_VARIANT)
    set(HW_VARIANT "full")
endif()

option(ALLOW_KERNEL_EXCEED_ICACHE
    "Don't fail the build when a kernel's kernel_body exceeds the board's I-cache."
    OFF)
option(ALLOW_KERNEL_EXCEED_DCACHE
    "Don't fail the build when a kernel's declared flash data exceeds the board's D-cache."
    OFF)

# ---------------------------------------------------------------------------
# Board-specific bundle (linker script, openocd target cfg, I/D-cache
# sizes, board's include dir for dwt.h etc.).
# ---------------------------------------------------------------------------
set(_board_cmake "${CMAKE_SOURCE_DIR}/board/${BOARD}/board.cmake")
if(NOT EXISTS "${_board_cmake}")
    message(FATAL_ERROR "No board config: ${_board_cmake}")
endif()
include("${_board_cmake}")

foreach(_v BOARD_LINKER_SCRIPT BOARD_OPENOCD_TARGET_CFG BOARD_INCLUDE_DIR
           ICACHE_SIZE_BYTES DCACHE_SIZE_BYTES)
    if(NOT DEFINED ${_v})
        message(FATAL_ERROR "Board config ${_board_cmake} must set(${_v} ...)")
    endif()
endforeach()

# ---------------------------------------------------------------------------
# Variant-specific bundle (cache/prefetch flags, INNER_REPS).
# ---------------------------------------------------------------------------
if(PLATFORM STREQUAL "gem5")
    set(VARIANT_CONFIG "gem5")
else()
    set(VARIANT_CONFIG "hardware-${HW_VARIANT}")
endif()

set(_cfg "${CMAKE_SOURCE_DIR}/configs/${VARIANT_CONFIG}.cmake")
if(NOT EXISTS "${_cfg}")
    message(FATAL_ERROR "No config: ${_cfg}")
endif()
include("${_cfg}")

# Every variant config must set INNER_REPS — the variant owns its rep count.
if(NOT DEFINED INNER_REPS)
    message(FATAL_ERROR "Config ${_cfg} must set(INNER_REPS ...)")
endif()
# Hardware variants additionally own their flash-accelerator settings.
if(PLATFORM STREQUAL "hardware")
    foreach(_v ENABLE_ICACHE ENABLE_DCACHE ENABLE_PREFETCH)
        if(NOT DEFINED ${_v})
            message(FATAL_ERROR "Config ${_cfg} must set(${_v} ...)")
        endif()
    endforeach()
endif()

message(STATUS "Microbenchmark build:")
message(STATUS "  PLATFORM=${PLATFORM} BOARD=${BOARD} VARIANT=${VARIANT_CONFIG}")
if(PLATFORM STREQUAL "hardware")
    message(STATUS "  ICACHE=${ENABLE_ICACHE} DCACHE=${ENABLE_DCACHE} "
                   "PREFETCH=${ENABLE_PREFETCH}")
endif()
message(STATUS "  INNER_REPS=${INNER_REPS}")
message(STATUS "  Board I-cache: ${ICACHE_SIZE_BYTES} bytes "
               "(ALLOW_KERNEL_EXCEED_ICACHE=${ALLOW_KERNEL_EXCEED_ICACHE})")
message(STATUS "  Board D-cache: ${DCACHE_SIZE_BYTES} bytes "
               "(ALLOW_KERNEL_EXCEED_DCACHE=${ALLOW_KERNEL_EXCEED_DCACHE})")

# ---------------------------------------------------------------------------
# Toolchain flags
# ---------------------------------------------------------------------------
set(MCU_FLAGS "-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16")
set(COMMON_FLAGS "${MCU_FLAGS} -Wall -Wextra -fno-builtin -fno-common")

set(CMAKE_C_FLAGS   "${COMMON_FLAGS} -std=c11 -Os ${CMAKE_C_FLAGS}")
set(CMAKE_ASM_FLAGS "${COMMON_FLAGS} ${CMAKE_ASM_FLAGS}")

# Search order: project include/, then the board's include dir for
# board-specific headers (dwt.h on stm32g474re).
include_directories(
    ${CMAKE_SOURCE_DIR}/include
    ${BOARD_INCLUDE_DIR}
)

# Per-platform define — exactly one is active.
if(PLATFORM STREQUAL "gem5")
    add_compile_definitions(PLATFORM_GEM5)
else()
    add_compile_definitions(PLATFORM_HARDWARE)
endif()

# Hardware-only knobs propagated for apply_flash_acr().
if(PLATFORM STREQUAL "hardware")
    add_compile_definitions(
        ENABLE_ICACHE=${ENABLE_ICACHE}
        ENABLE_DCACHE=${ENABLE_DCACHE}
        ENABLE_PREFETCH=${ENABLE_PREFETCH}
    )
endif()

# Per-rep measurement count — the harness loops INNER_REPS times,
# capturing each iteration's inner-ROI cycle delta into the
# _inner_delta_cyc[] array; main() prints one MICROBENCH line per rep.
add_compile_definitions(INNER_REPS=${INNER_REPS})

# ---------------------------------------------------------------------------
# Linker
# ---------------------------------------------------------------------------
set(CMAKE_EXE_LINKER_FLAGS
    "${MCU_FLAGS} -nostdlib -nostartfiles -T ${BOARD_LINKER_SCRIPT} -Wl,--no-warn-rwx-segments")

# ---------------------------------------------------------------------------
# Benchmark targets
# ---------------------------------------------------------------------------
set(HARNESS_SOURCES
    src/startup.c
    src/system_init.c
    src/flash_config.c
    src/main.c
)

# bench_nop16_100 is the canonical benchmark: BENCH harness gives
# a ~6-cycle measurement floor on hardware, and the body of 100 × nop.n
# runs at exactly 100 cycles → CPI = 1.0 for the NOPs themselves.
#
# BENCH has both hardware (DWT_CYCCNT) and gem5 (m5_work_begin /
# m5_work_end) implementations, so the same source builds for both
# platforms.
set(BENCHMARKS
    # Scaling-sweep kernels — sizes step by 8 NOPs so each datapoint
    # covers an integer number of 64-bit FLITF flash fetches (4 × nop.n
    # per fetch). Used by scripts/scaling_nop16_sweep.py to linear-fit
    # per-NOP cost and harness framing.
    bench_nop16_8
    bench_nop16_16
    bench_nop16_24
    bench_nop16_32
    bench_nop16_40
    bench_nop16_48
    bench_nop16_56
    bench_nop16_64
    bench_nop16_72
    bench_nop16_80
    # Canonical 100-NOP kernel — kept separately for default tests
    # and README examples.
    bench_nop16_100
)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

find_program(ARM_NM     arm-none-eabi-nm)
find_program(ARM_OBJCOPY arm-none-eabi-objcopy)
find_program(PYTHON3    python3 REQUIRED)

# OpenOCD for hardware flashing — uses the project's generic probe
# config (openocd/stlink.cfg) plus the board-specific target cfg
# resolved via BOARD_OPENOCD_TARGET_CFG.
if(PLATFORM STREQUAL "hardware")
    find_program(OPENOCD_EXECUTABLE openocd)
    if(NOT OPENOCD_EXECUTABLE)
        message(STATUS "openocd not found in PATH — flash-* targets will not be generated.")
    endif()
endif()

set(_size_check_script "${CMAKE_SOURCE_DIR}/scripts/check_kernel_size.py")
set(_size_check_extra "")
if(ALLOW_KERNEL_EXCEED_ICACHE)
    list(APPEND _size_check_extra "--allow-exceed-icache")
endif()
if(ALLOW_KERNEL_EXCEED_DCACHE)
    list(APPEND _size_check_extra "--allow-exceed-dcache")
endif()

foreach(bench ${BENCHMARKS})
    set(elf_target "${bench}.elf")
    add_executable(${elf_target}
        kernels/${bench}.S
        ${HARNESS_SOURCES}
    )
    target_compile_definitions(${elf_target} PRIVATE BENCH_NAME="${bench}")
    target_link_options(${elf_target} PRIVATE
        "-Wl,-Map=${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${bench}.map")
    set_property(TARGET ${elf_target} APPEND PROPERTY LINK_DEPENDS ${BOARD_LINKER_SCRIPT})

    # Post-build: print code size, pinned symbols, then run the
    # kernel-size guards against the board's I-cache and D-cache.
    # Each guard fails the build (non-zero exit) when the respective
    # footprint exceeds the board's cache and the corresponding
    # ALLOW_KERNEL_EXCEED_{I,D}CACHE option isn't set.
    add_custom_command(TARGET ${elf_target} POST_BUILD
        COMMAND ${CMAKE_SIZE} $<TARGET_FILE:${elf_target}>
        COMMAND ${CMAKE_COMMAND} -E echo "kernel-body symbols:"
        COMMAND ${CMAKE_COMMAND} -E env bash -c
                "${ARM_NM} \"$<TARGET_FILE:${elf_target}>\" | grep -E '_bench_body_(start|end)|bench_entry' || true"
        COMMAND ${PYTHON3} ${_size_check_script}
                --elf $<TARGET_FILE:${elf_target}>
                --kernel-name ${bench}
                --icache-size-bytes ${ICACHE_SIZE_BYTES}
                --dcache-size-bytes ${DCACHE_SIZE_BYTES}
                ${_size_check_extra}
        VERBATIM
    )

    if(PLATFORM STREQUAL "hardware" AND OPENOCD_EXECUTABLE)
        add_custom_target(flash-${bench}
            COMMAND ${OPENOCD_EXECUTABLE}
                -f ${CMAKE_SOURCE_DIR}/openocd/stlink.cfg
                -f ${BOARD_OPENOCD_TARGET_CFG}
                -c "init"
                -c "reset halt"
                -c "arm semihosting enable"
                -c "program $<TARGET_FILE:${elf_target}> verify"
                -c "reset run"
            DEPENDS ${elf_target}
            USES_TERMINAL
            COMMENT "Flashing ${elf_target} via OpenOCD"
        )
    endif()
endforeach()

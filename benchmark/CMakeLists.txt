cmake_minimum_required(VERSION 3.16)
project(stm32-microbench CXX C ASM)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ELFs go in bin/ — required by EntoBench flash targets (program bin/<name>.elf)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# =============================================================================
# Paths
# =============================================================================
set(ENTOBENCH_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../external/ento-bench)
set(ENTOBENCH_SRC ${ENTOBENCH_DIR}/src)

# Copy and include EntoBench helpers (defines add_benchmark, add_stm32_target, etc.)
configure_file(${ENTOBENCH_DIR}/entobench_helpers.cmake
               ${CMAKE_SOURCE_DIR}/entobench_helpers.cmake COPYONLY)
include(${CMAKE_SOURCE_DIR}/entobench_helpers.cmake)

# Eigen (referenced by some ento-bench headers; we don't use it directly)
set(EIGEN_DIR ${ENTOBENCH_DIR}/external/eigen CACHE PATH "Path to Eigen")

# Suppress warnings from third-party code
add_compile_options(-w)

# =============================================================================
# STM32 Build Configuration
# =============================================================================
# The toolchain file (stm32-g474re.cmake) sets:
#   STM32_BUILD=ON, STM_FAMILY=G4, STM_PRODUCT=G474RE, STM_TYPE=G474xx
# and fetches CMSIS/HAL sources when FETCH_ST_SOURCES=ON.

add_definitions(-DSTM32_BUILD=1)
get_filename_component(DATASETS_ABS "${CMAKE_CURRENT_SOURCE_DIR}/../datasets" ABSOLUTE)
add_definitions(-DDATASET_PATH="${DATASETS_ABS}")

# CMSIS/HAL target variables (non-H7 path)
set(CMSIS_FAMILY_TARGET "CMSIS::STM32::${STM_FAMILY}")
set(CMSIS_TYPE_TARGET   "CMSIS::STM32::${STM_TYPE}")
set(HAL_RCC_TARGET      "HAL::STM32::${STM_FAMILY}::LL_RCC")
set(HAL_GPIO_TARGET     "HAL::STM32::${STM_FAMILY}::LL_GPIO")
set(HAL_FLASH_TARGET    "HAL::STM32::${STM_FAMILY}::LL_FLASH")
set(HAL_UTILS_TARGET    "HAL::STM32::${STM_FAMILY}::LL_UTILS")
set(HAL_PWR_TARGET      "HAL::STM32::${STM_FAMILY}::LL_PWR")
set(HAL_CORTEX_TARGET   "HAL::STM32::${STM_FAMILY}::CORTEX")
set(STM32_TARGET        "STM32::${STM_TYPE}")

find_package(CMSIS COMPONENTS STM32G4 REQUIRED)
find_package(HAL COMPONENTS STM32G4 REQUIRED)

# =============================================================================
# Testing infrastructure (needed by ento-bench sub-CMakeLists)
# =============================================================================
enable_testing()
add_custom_target(check COMMAND ctest "--timeout" "60")

# =============================================================================
# Build EntoBench libraries (bench, ento-mcu-semihosted, ento_util, etc.)
# =============================================================================
add_subdirectory(${ENTOBENCH_SRC} ${CMAKE_BINARY_DIR}/ento-bench-src)

# =============================================================================
# OpenOCD setup (optional — only needed for flashing/debugging on hardware)
# =============================================================================
set(OPENOCD_CFG "stm32g4x.cfg" CACHE STRING "STM32 OpenOCD device config")

find_program(OPENOCD_EXECUTABLE NAMES openocd
  PATHS ~/openocd-latest/bin /usr/local/bin /opt/homebrew/bin /usr/bin
        ~/external/openocd/bin
  NO_CACHE
)
find_file(OPENOCD_INTERFACE NAMES stlink.cfg
  PATHS /usr/share/openocd/scripts/interface
        /opt/local/share/openocd/scripts/interface
        /opt/homebrew/share/openocd/scripts/interface
        ~/openocd-latest/share/openocd/scripts/interface
        ~/research/openocd/tcl/interface
  NO_CACHE
)

if(OPENOCD_EXECUTABLE AND OPENOCD_INTERFACE)
  message(STATUS "OpenOCD found: ${OPENOCD_EXECUTABLE}")
  message(STATUS "OpenOCD interface: ${OPENOCD_INTERFACE}")
else()
  message(STATUS "OpenOCD not found — flash/debug targets will not be available")
endif()

# =============================================================================
# Build microbenchmarks
# =============================================================================
add_subdirectory(microbench)

# =============================================================================
# Build EntoBench application benchmarks (perception, control, state-est)
# =============================================================================
add_subdirectory(${ENTOBENCH_DIR}/benchmark/perception ${CMAKE_BINARY_DIR}/ento-bench-perception)
add_subdirectory(${ENTOBENCH_DIR}/benchmark/control ${CMAKE_BINARY_DIR}/ento-bench-control)
add_subdirectory(${ENTOBENCH_DIR}/benchmark/state-est ${CMAKE_BINARY_DIR}/ento-bench-state-est)

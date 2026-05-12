# STM32G474RE Nucleo — board-specific settings used by the top-level
# CMakeLists.txt. Anything tied to this MCU's memory map, flash
# accelerator, or debug-probe target file lives here.
#
# The Cortex-M4 core itself (FPU, DWT, vector table shape) is reflected
# in the CMakeLists toolchain flags and in the board's dwt.h header,
# both of which target this specific silicon.

# Path to the board's linker script. Pinned addresses + memory regions
# all live in here.
set(BOARD_LINKER_SCRIPT
    "${CMAKE_CURRENT_LIST_DIR}/stm32g474re.ld")

# OpenOCD config file selecting this MCU family (paired with a generic
# probe config like openocd/stlink.cfg at the project root).
set(BOARD_OPENOCD_TARGET_CFG
    "${CMAKE_CURRENT_LIST_DIR}/openocd.cfg")

# Header search path for board-specific includes (dwt.h, etc.). Added
# to the project's include directories so kernels can still write
# `#include "dwt.h"`.
set(BOARD_INCLUDE_DIR
    "${CMAKE_CURRENT_LIST_DIR}")

# Adaptive Real-Time Memory Accelerator (ART) cache sizes for this MCU,
# per RM0440 (STM32G4 family reference). The instruction cache is the
# binding constraint for cycle measurements: the warmup call has to
# fit the kernel body in I-cache for every subsequent rep to hit a
# warm cache. The CMakeLists.txt build asserts this at post-link.
set(ICACHE_SIZE_BYTES 1024)   # 32 lines × 32 bytes
set(DCACHE_SIZE_BYTES 256)    # caches literal-pool / .rodata reads from flash

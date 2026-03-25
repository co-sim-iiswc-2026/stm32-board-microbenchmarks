cmake_minimum_required(VERSION 3.16)
project(stm32g474re_microbenchmarks ASM)

# -- Compiler and linker flags for Cortex-M4 bare-metal --
set(MCU_FLAGS "-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16")
set(CMAKE_ASM_FLAGS "${CMAKE_ASM_FLAGS} ${MCU_FLAGS} -I${CMAKE_SOURCE_DIR}")
set(CMAKE_EXE_LINKER_FLAGS
    "${CMAKE_EXE_LINKER_FLAGS} ${MCU_FLAGS} -nostdlib -T ${CMAKE_SOURCE_DIR}/stm32g474re.ld --specs=nosys.specs -Wl,--no-warn-rwx-segments"
)

set(BENCHMARKS
    # --- Original benchmarks ---
    bench_nop
    bench_alu
    bench_mul
    bench_div
    bench_load
    bench_store
    bench_pushpop
    bench_branch
    bench_exc_entry
    bench_exc_return
    bench_systick
    bench_fpu
    bench_art_prefetch
    # --- New: model validation benchmarks ---
    bench_alu16
    bench_load_dep
    bench_ldr_literal
    bench_store_burst
    bench_icache_miss
    bench_mixed_width
    bench_div_short
    bench_dmb
    bench_ccm_sram
    bench_scs_read
    bench_scs_store
    # --- New: exception benchmarks ---
    bench_exc_entry_fp
    bench_tail_chain
    bench_stacking
    bench_stacking_fp
    # --- New: branch prediction reverse-engineering ---
    bench_bp_tight
    bench_bp_long_body
    bench_bp_forward
    bench_bp_alternating
    bench_bp_nested
    bench_bp_align
)

foreach(bench ${BENCHMARKS})
    add_executable(${bench}.elf src/${bench}.S)
endforeach()

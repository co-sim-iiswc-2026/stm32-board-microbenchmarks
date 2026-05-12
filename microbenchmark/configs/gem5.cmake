# gem5 build config — Cortex-M simulation.
#
# No flash-accelerator knobs: gem5 doesn't model the STM32 FLITF, so
# ICACHE/DCACHE/PREFETCH would be inert here. Cache/memory behaviour
# for gem5 is configured in the gem5 invocation, not in this binary.
set(INNER_REPS 10)

# SDIV latency calibration microbenches

## Purpose

Resolve an ambiguity in the existing `bench-div` / `bench-div_short`
silicon-vs-gem5 comparison. Both report a residual gap (gem5 too slow
by ~5-7 % in the `none` config) after the dynamic-latency SDIV fix.
The gap could be in either:

(a) the **per-SDIV** cycle count (the
[Cortex-M4 TRM Table 3-1][trm] formula `clamp(4 + ⌈sigBits/4⌉, 2, 12)`),
or
(b) the **per-call** glue (function call / return / inner-loop branch
refetches modeled by the F-stage).

A line-trace of `bench-div` strongly suggests (b) — F idles for the
full 12-cy latency of the last SDIV because it has no return-address
prediction past `bx lr`. But with only two silicon data points
(dividend = 0x7FFFFFFF and dividend = 15), we can't separate the
per-SDIV from the per-call cost.

This set adds **multiple SDIV counts** at each dividend so a linear
fit `cycles(N) = N × per_sdiv_cy + glue_cy` reveals the two
quantities independently.  The slope is what the formula needs to
match; the intercept is what the F-stage modeling work would close.

[trm]: https://developer.arm.com/documentation/ddi0439/d/

## Benches

Built into the `microbench-sdiv-calibration-all` cmake target.
All kernels are stamped from the same `KERNEL_BODY` template in
[`kernels.h`](kernels.h) so the kernel-body bytes are byte-identical
modulo the `.rept` count and the dividend-load instruction.

| Bench | N sdivs | Dividend | sigBits | Formula lat |
|---|---|---|---|---|
| `bench-sdiv-cal-baseline`   |  0 | n/a              |  — | n/a |
| `bench-sdiv-cal-max-10`     | 10 | 0x7FFFFFFF       | 31 | 12 |
| `bench-sdiv-cal-max-20`     | 20 | 0x7FFFFFFF       | 31 | 12 |
| `bench-sdiv-cal-max-40`     | 40 | 0x7FFFFFFF       | 31 | 12 |
| `bench-sdiv-cal-mid-20`     | 20 | 0xFF             |  8 |  6 |
| `bench-sdiv-cal-short-10`   | 10 | 0xF              |  4 |  5 |
| `bench-sdiv-cal-short-20`   | 20 | 0xF              |  4 |  5 |
| `bench-sdiv-cal-short-40`   | 40 | 0xF              |  4 |  5 |

The `baseline` has zero SDIVs (just dividend setup + `bx lr`) — it
measures the **pure non-SDIV overhead** including the `.balign` pad,
the setup MOVs, the function return, and the inner-loop glue. Useful
as a sanity-check anchor for the `glue_cy` intercept.

## Build target

```
cmake --build $BUILD_DIR --target microbench-sdiv-calibration-all -j5
```

Builds all 8 ELFs for both the gem5 (build-gem5) and STM32 (build-stm32-*)
toolchains. Each `.elf` lands in `$BUILD_DIR/bin/<bench-name>.elf`.

## Usage in the experiment

See
[`experiments/gem5-sdiv-dynamic-latency/`](../../../../experiments/gem5-sdiv-dynamic-latency/README.md)
for the linear-fit slope/intercept extraction and silicon-vs-gem5
comparison.

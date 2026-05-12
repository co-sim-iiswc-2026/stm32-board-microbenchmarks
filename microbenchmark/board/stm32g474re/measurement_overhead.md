# STM32G474RE measurement-overhead reference

Empirically-measured **per-NOP cost** (effective CPI for instruction
fetch) and **harness framing overhead** for each hardware variant on
the STM32G474RE Nucleo board, plus the method used to derive them so
the numbers can be re-confirmed on any board.

Measured 2026-05-12 against the BENCH/END_BENCH harness with
`kernel_body` pinned at `0x08001000` and `INNER_REPS=10`. PLL at
170 MHz, FLASH LATENCY=4. Per-rep DWT_CYCCNT snap pair around each
measured `bl kernel_body`. Linear fits across 10 sample sizes
(`bench_nop16_{8,16,24,32,40,48,56,64,72,80}`) gave residual = 0 on
every variant — the data is fully deterministic once the sweep size
is a multiple of one 64-bit flash fetch (= 4 × `nop.n`).

## Headline overheads

The measured `inner` cycle count for a kernel of N × `nop.n` is exactly:

```
inner  =  slope · N  +  intercept
```

| Variant                       | ICACHE | DCACHE | PREFETCH | slope (cycles/NOP) | intercept (framing, cycles) |
|-------------------------------|:------:|:------:|:--------:|-------------------:|----------------------------:|
| `hw-stm32g474re`              |   on   |   on   |    on    |          **1.000** |                    **6**    |
| `hw-noprefetch-stm32g474re`   |   on   |   on   |   off    |          **1.000** |                    **7**    |
| `hw-nocache-stm32g474re`      |  off   |  off   |    on    |          **1.250** |                   **20**    |
| `hw-none-stm32g474re`         |  off   |  off   |   off    |          **1.500** |                   **17**    |

(Same numbers from the linear-fit residual = 0 sweep; rounded to integers
because every datapoint landed exactly on the fit line.)

### What the slopes mean

- **1.000 c/NOP** — every `nop.n` costs exactly 1 cycle. Achieved when
  the I-cache holds the warmed kernel lines. The warmup call before
  `INNER_REPS` primes the FLITF cache; on the all-on and prefetch-off
  variants the cache is the only thing that matters, so the slope is
  identical.
- **1.250 c/NOP** — `hw-nocache`. No I-cache, but prefetch is on. The
  prefetcher feeds 4 × `nop.n` per 64-bit flash fetch, paying 1 wait
  cycle once every 4 NOPs: `(4·1 + 1)/4 = 1.25`.
- **1.500 c/NOP** — `hw-none`. No I-cache, no prefetch. Every 64-bit
  flash fetch costs 2 wait cycles on top of the 4 NOPs it contains:
  `(4·1 + 2)/4 = 1.5`.

### What the intercepts mean

The framing is the harness cost that is **not** in your kernel body —
i.e. the fixed overhead the per-rep DWT snap pair always sees:

- `ldr r4, [r0]`  (start snap)
- `bl kernel_body` (enter)
- (your kernel runs)
- `bx lr` (exit kernel)
- `ldr r1, [r0]` (end snap)
- (back in the rep loop)

With caches on, that's roughly `bl (2c) + bx (3c) + ldr-distance (1c)
= 6c` — and the measurement matches exactly. The extra cycle on the
no-prefetch variant comes from the cold target fetch of `bl
kernel_body`. The +14c jump on the no-cache variants comes from
running those same scaffolding instructions through the slow flash
path.

### How to use these numbers

Given an `inner` cycle count from a custom kernel of size N
instructions (assuming all are 16-bit Thumb instructions like
`nop.n`), the **pure body cycles** on a given variant are:

```
pure_body  =  inner  -  intercept
```

So a kernel that reports `inner = 86` on `hw-stm32g474re` ran for
exactly 80 cycles of "real work." On `hw-none-stm32g474re` an `inner =
137` corresponds to 120 cycles of work (or equivalently 80 NOPs at
CPI=1.5).

Conversely, predicting the result of a new kernel: if you know the
kernel's pure-cycle cost, the expected `inner` on each variant is just
`slope·N + intercept` with the table above.

## How to reproduce

The script that produced the numbers above:
[`scripts/scaling_nop16_sweep.py`](../../scripts/scaling_nop16_sweep.py).

Prerequisites — same as for any board run:

- ST-Link visible to `lsusb` inside WSL (see the microbenchmark
  [`README.md`](../../README.md#one-time-wsl-setup) for usbipd-win).
- The 10 sweep kernels built for all 4 hardware variants. They live in
  [`../../kernels/bench_nop16_{8,16,24,32,40,48,56,64,72,80}.S`](../../kernels/)
  and are listed in [`../../CMakeLists.txt`](../../CMakeLists.txt)'s
  `BENCHMARKS` block, so a `cmake --build` of any hardware preset
  produces them.

Then:

```bash
cd microbenchmark
for p in hw-stm32g474re hw-nocache-stm32g474re \
         hw-noprefetch-stm32g474re hw-none-stm32g474re; do
    cmake --build build/$p -j4
done

python3 ./scripts/scaling_nop16_sweep.py
```

The script flashes each variant × each kernel (40 board runs ≈ 6
minutes at the default 15s timeout), tabulates the average `inner`
per cell, and prints a linear-fit summary. Successful output looks
like:

```
=== hw-stm32g474re ===
  bench_nop16_  8: inner = 14
  bench_nop16_ 16: inner = 22
  …
================================================================================
 NOPs   hw-stm32g474re   hw-nocache-…   hw-noprefetch-…   hw-none-…
   8              14              30               15            29
  16              22              40               23            41
  …
================================================================================

Linear fit  inner = slope · N + intercept
  hw-stm32g474re            slope = 1.000   intercept =  6.00   max|resid| = 0.00
  hw-nocache-stm32g474re    slope = 1.250   intercept = 20.00   max|resid| = 0.00
  hw-noprefetch-stm32g474re slope = 1.000   intercept =  7.00   max|resid| = 0.00
  hw-none-stm32g474re       slope = 1.500   intercept = 17.00   max|resid| = 0.00
```

The headline "max|resid| = 0" is what tells you the sweep was clean.
Non-zero residuals usually mean the sample sizes don't align to your
target's flash-fetch granularity — for the 64-bit FLITF on STM32G4,
that's a multiple of 4 × `nop.n`; for cleanest stair-steps we use 8.

### When to re-run

Re-derive the overheads when any of the following changes:

1. **The BENCH/END_BENCH macros change** — the framing intercept comes
   directly from the per-rep snap+`bl`+`bx`+snap sequence inside
   `bench_entry`. Any tweak to `harness.h`'s asm shifts the intercept.
2. **The board changes** — different MCU, different flash controller,
   different FLITF geometry. Use the same script on the new board's
   presets.
3. **The variant configs change** — adding a new hardware variant
   (a different combination of `ENABLE_ICACHE` / `ENABLE_DCACHE` /
   `ENABLE_PREFETCH`) gets its own row.
4. **PLL / FLASH LATENCY changes** — currently fixed at 170 MHz +
   LATENCY=4 by [`src/system_init.c`](../../src/system_init.c). A
   different clock would shift both slope and intercept.

### Methodology in one line

For any board: build kernels of sizes `[N₁, N₂, …]` where each Nᵢ is a
multiple of the target's flash-fetch granularity (in **single-cycle**
16-bit Thumb instructions like `nop.n`); measure `inner` for each;
fit `inner = slope·N + intercept`. The slope is the effective
instruction-fetch CPI; the intercept is the harness's per-rep
measurement framing.

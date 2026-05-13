# microbenchmark — low-overhead Cortex-M4 cycle harness

Bare-metal microbenchmark harness for the **STM32G474RE Nucleo** board
and a Cortex-M gem5 fork. The same kernel source builds for either
target; the harness picks a target-appropriate measurement mechanism
(DWT_CYCCNT on hardware, `m5_work_begin` / `m5_work_end` markers on
gem5).

Each `bench_entry()` invocation does one cold-cache warmup call into
the kernel (no instrumentation around it) followed by **`INNER_REPS`**
measured calls, each independently bracketed by its own start/end
snap pair. Every measured call's cycles are reported separately —
one `MICROBENCH name=<bench> rep=<i> inner=<N>` line per rep on
hardware, one stats window per rep in `m5out/stats.txt` on gem5.

`INNER_REPS` is set per-variant in [`configs/<variant>.cmake`](configs/)
(default 10 across the board today). The build target is described by
three CMake cache vars — `PLATFORM`, `BOARD`, and (for hardware)
`HW_VARIANT` — bundled into one preset per combination:

```bash
cmake --preset gem5-stm32g474re                # PLATFORM=gem5     BOARD=stm32g474re
cmake --preset hw-stm32g474re                  # PLATFORM=hardware BOARD=stm32g474re HW_VARIANT=full
cmake --preset hw-nocache-stm32g474re          # PLATFORM=hardware BOARD=stm32g474re HW_VARIANT=nocache
# … etc
```

Per-board resources (linker script, openocd target cfg, I-cache size,
board-specific headers) live in [`board/<board>/`](board/). Adding
support for a new board means creating one of those directories and a
matching set of presets — no edits to the source tree.

## Quick start

```bash
cd microbenchmark
cmake --preset hw-stm32g474re && cmake --build build/hw-stm32g474re -j4
python3 ./test/test_board_run.py
```

Example output (INNER_REPS=10):

```
==> Flashing build/hw-stm32g474re/bin/bench_nop16_100.elf and capturing semihosting output (timeout 15s) ...
  observed: 10 rep(s)
    rep= 0  inner=106   (MICROBENCH name=bench_nop16_100 rep=0 inner=106)
    rep= 1  inner=106   (MICROBENCH name=bench_nop16_100 rep=1 inner=106)
    rep= 2  inner=106   (MICROBENCH name=bench_nop16_100 rep=2 inner=106)
    ...
    rep= 9  inner=106   (MICROBENCH name=bench_nop16_100 rep=9 inner=106)
  log:      test/logs/hw-stm32g474re/bench_nop16_100.log
  cycles:   test/logs/hw-stm32g474re/bench_nop16_100.cycles.txt  (avg=106)

Board run OK (hw-stm32g474re / bench_nop16_100): 10 reps, avg=106 (min=106 max=106).
```

The `.cycles.txt` file holds the **average** inner cycles across all
reps (one integer). The full per-rep list lives in the OpenOCD log.

**`inner` is what you read** — cycles between two `ldr [DWT_CYCCNT]`
snaps bracketing one warm-cache call to the kernel. For the 100-NOP
template kernel that's 100 cycles of NOPs at CPI=1.0 plus ~6 cycles
of `bl/bx`/snap framing.

## How it works

### Memory layout — the three pinned flash regions

The linker script
([board/stm32g474re/stm32g474re.ld](board/stm32g474re/stm32g474re.ld))
pins three regions of flash to fixed addresses across every build
(gem5 + all 4 hardware variants):

```
0x08000000   .isr_vector              (vector table, 64 bytes)
0x08000400   .bench_kernel            ┐  ≤ 0xc00 bytes; bench_entry wrapper
  0x08000400   bench_entry:           │    .bench_prologue   — setup (untimed)
  0x08000470 .bench_prologue_snap     │    16-byte filler slot (no instrumentation)
  0x08000480   _bench_body_start      │    .bench_body       — warmup + N-rep loop
             _bench_body_end          │
             .bench_epilogue          │    bx lr
                                      ┘
0x08001000   .text.kernel_body        ← 1 KiB reserved (= ICACHE_SIZE_BYTES);
             kernel_body              ←   your kernel body lives HERE
0x08001400   .rodata.kernel_data      ← 256 B reserved (= DCACHE_SIZE_BYTES);
             __kernel_data_start      ←   flash data the kernel opts into
             __kernel_data_end        ←
0x08001500+  .text                    ← everything else: Reset_Handler, main,
                                          system_init, flash_config, helpers …
```

The two new pins are **`kernel_body`** at `0x08001000` and
**`__kernel_data_start`** at `0x08001400`. Because they're at the same
address in every build, the I/D-cache set indices the kernel touches
are identical between gem5 and hardware — when you compare cycle
counts across builds, only the cache/prefetch policy differs, not the
addresses being cached.

The reserved slot sizes match this board's cache geometry (1 KiB
I-cache, 256 B D-cache from
[board/stm32g474re/board.cmake](board/stm32g474re/board.cmake)). Going
over the limit is caught twice: by a linker `ASSERT` (link-time) and
by [scripts/check_kernel_size.py](scripts/check_kernel_size.py)
(post-link, with the `-DALLOW_KERNEL_EXCEED_{I,D}CACHE=ON` overrides).

Pinned by `.bench_kernel`:

- **`bench_entry`** at `0x08000400` — the function `main()` calls.
- The 16-byte slot at offset `0x70..0x7F` (the `.bench_prologue_snap`
  section) — exists for historical layout reasons and to keep the body
  start address pinned regardless of prologue size. It is currently
  filled with Thumb NOPs on every target; no measurement instrumentation
  lives there anymore. The slot is reserved by
  `. = _bench_kernel_start + 0x80 - 0x10` in the linker, with a linker
  `ASSERT` enforcing the size. Padding from the end of the prologue
  setup to the slot is filled with Thumb NOPs (`bf00`, via
  `FILL(0x00bf00bf)`).
- **`_bench_body_start`** at `0x08000480` — start of the harness
  measurement body.

The `BENCH` macro emits the kernel into an input section
`.text.kernel_body`; the linker `KEEP()`s that into the pinned
`.text.kernel_body` output section at `0x08001000` (1 KiB-aligned, so
`kernel_body` lands exactly at `0x08001000`). The wrapper-bytes
identity (verified across the 4 hardware variants) and the kernel-body
identity (verified across all 5 builds) together mean every measured
instruction lives at the same flash address with the same encoding —
exactly what cross-target cycle comparisons need.

The `MEMORY`, `_estack`, `_Min_Heap_Size`, and `_Min_Stack_Size`
declarations match entobench's generated `G474RE.ld` for STM32G474RE;
only the three pinned sections above are added.

### Warmup + measurement flow

`main()` does standard init (PLL→170 MHz on hardware, FLASH ACR per
variant, enable DWT TRCENA + CYCCNT) and then calls `bench_entry()`.
The hardware wrapper body looks like:

```asm
bench_entry:                           @ at 0x08000400
    movw  r0, #0x1004
    movt  r0, #0xe000                  @ r0 = &DWT->CYCCNT
    [Thumb-NOP fill bytes ...]         @ pads up to the 16-byte filler slot
    [16 bytes of nops at 0x70..0x7F]   @ no instrumentation here

_bench_body_start:                     @ at 0x08000480
    push  {r3, r4, r5, lr}
    bl    kernel_body             @ (1) WARMUP — caches the body
    movw  r3, #:lower16:_inner_delta_cyc
    movt  r3, #:upper16:_inner_delta_cyc   @ r3 → _inner_delta_cyc[0]
    movs  r5, #INNER_REPS                  @ rep counter
1:
    ldr   r4, [r0]                     @ inner-ROI start snap
    bl    kernel_body             @ MEASURED CALL
    ldr   r1, [r0]                     @ inner-ROI end snap
    subs  r1, r1, r4                   @ delta = end - start
    str   r1, [r3], #4                 @ _inner_delta_cyc[i++] = delta
    subs  r5, r5, #1
    bne   1b
    pop   {r3, r4, r5, lr}
    bx    lr
```

Each rep produces one independent cycle delta into `_inner_delta_cyc[i]`.
After `bench_entry` returns, `main()` walks the array and prints one
`MICROBENCH name=<bench> rep=<i> inner=<N>` line per rep via
semihosting.

The gem5 wrapper has the same shape, except the snap-ldrs are replaced
by `m5_work_begin` / `m5_work_end` `bkpt #0xab` instructions around the
measured call — one work region per rep — and the filler slot at
offset 0x70 is 16 bytes of NOPs (no instrumentation there).

### Expected overhead — what's inside one rep's inner ROI

Between the start-snap `ldr` and the end-snap `ldr` of any one rep the
CPU executes exactly:


| instruction                                            | cycles on Cortex-M4                                                                                   |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| `bl kernel_body`                                       | **1 + P** — direct branch, PC-relative immediate. Prefetcher predicts the target; P ≈ 1. → ~2 cycles. |
| `<kernel body>`                                        | N cycles (your instructions).                                                                         |
| `bx lr` (inside `kernel_body`, emitted by `END_BENCH`) | **1 + P** — indirect branch, target in a register. No early speculation; P ≈ 2. → ~3 cycles.          |
| inter-ldr sampling distance                            | the cycles between the two `ldr [DWT_CYCCNT]` sampling phases. Inherent ~1 cycle.                     |


Total framing = `bl + bx + ldr-distance ≈ 6 cycles`. So `inner = N + 6`
on hardware, where N is your kernel body's cycle count. For the
100-NOP template that's `100 + 6 = 106`.

For gem5 the framing is similar but ~2 cycles more: `m5_work_end`'s
3 setup instructions (`mov.w r0, #0x100; movw r1, ...; movt r1, ...`)
run before its `bkpt` fires, so they're inside the work region.

If your body uses `push {r4-r11}` / `pop {r4-r11}` to preserve
callee-saved registers, add `1 + N` cycles per push/pop pair (one for
the address generation + one per pushed register).

### Why the warmup matters

A cold-flash call to a 100-NOP body costs ~127 cycles (CPI ≈ 1.25),
not 100 — the FLITF prefetcher can't quite keep up with the CPU's
2-bytes/cycle Thumb fetch rate, leaving ~0.25 cycles per NOP of
unhidden wait-state latency. After the warmup call, all of
`kernel_body`'s cache lines are in the FLITF I-cache (1 KiB =
32 lines × 32 bytes on STM32G474RE), so the second call fetches every
instruction in 1 cycle.

The body must fit in the I-cache for the warmup to be complete. Build
fails at post-link if it doesn't (see `ALLOW_KERNEL_EXCEED_ICACHE`
below). The cache size comes from the board's `board.cmake`, so a
different board picks up its own value automatically.

### gem5 vs hardware — what differs in the binary

The same kernel source compiles for both targets, and `bench_entry`
is pinned at `0x08000400` in both, so the measurement scaffolding sits
at the same flash address regardless of build. What differs is the
*instrumentation instructions* inside the wrapper.


| aspect                             | hardware (`hardware`* preset)                                                 | gem5 (`gem5` preset)                                                                                                             |
| ---------------------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `bench_entry` address              | pinned at `0x08000400`                                                        | pinned at `0x08000400` (same)                                                                                                    |
| `_bench_body_start` address        | pinned at `0x08000480`                                                        | pinned at `0x08000480` (same)                                                                                                    |
| `kernel_body` bytes                | byte-identical across all 4 hardware variants                                 | byte-identical to hardware — same source, same compiler                                                                          |
| 16-byte filler slot at offset 0x70 | `8 × nop` — no instrumentation                                                | `8 × nop` — no instrumentation                                                                                                   |
| Per-rep start instrumentation      | `ldr r4, [DWT_CYCCNT]` — start snap                                           | `mov.w r0, #0x100; movw/movt r1, &m5_pb_begin; bkpt #0xab` → `m5_work_begin`                                                     |
| Per-rep end instrumentation        | `ldr r1, [DWT_CYCCNT]; subs r1,r1,r4; str r1,[r3],#4` → `_inner_delta_cyc[i]` | `mov.w r0, #0x100; movw/movt r1, &m5_pb_end; bkpt #0xab` → `m5_work_end`                                                         |
| Around the warmup call             | **no instrumentation**                                                        | **no instrumentation** — `m5_work_begin` fires only after the warmup returns                                                     |
| Reported cycle counts              | semihosting: one `MICROBENCH name=<bench> rep=<i> inner=<N>` line per rep     | semihosting: a single `MICROBENCH name=<bench>` marker; per-rep cycles come from gem5's stat machinery (one work region per rep) |
| Framing inside the measurement     | `bl + bx lr + ldr-distance ≈ 6 cycles`                                        | `bl + bx lr + 3 setup instr before m5_work_end's bkpt ≈ 8 cycles`                                                                |
| One-time chip init                 | `system_init()` configures PLL → 170 MHz, sets `FLASH->ACR`, enables DWT      | `system_init()` skips PLL/FLASH writes (gem5 doesn't model them); FPU enable still runs                                          |


What you can rely on being identical across all targets:

- `kernel_body`'s bytes (your kernel) — verified by
`test_layout_identical.py` to hash to the same SHA-256 across all 5
builds (gem5 + 4 hardware). This is what makes the cross-target
comparison valid.
- The address of `bench_entry` and `_bench_body_start` — pinned in
both.
- Both targets call the kernel exactly `1 + INNER_REPS` times — one
warmup, then INNER_REPS measured reps. Both wrap *only* the measured
reps in instrumentation; the warmup runs naked.

What differs and matters for interpretation:

- gem5's reported cycles ≈ hardware's `inner` + ~2 cycles, because
m5_work_end's 3 setup instructions live inside the work region.
- gem5's CPU/cache model parameters are set in your gem5 invocation,
not in this harness. To compare gem5 against a specific hardware
variant, configure gem5 to match that variant's `FLASH->ACR`.

## Layout

```
microbenchmark/
├── CMakeLists.txt
├── CMakePresets.json          # 5 presets: gem5 + 4 hardware cache variants
├── arm-none-eabi.cmake        # toolchain
├── linker/
│   └── stm32g474re.ld         # linker — entobench G474RE.ld + .bench_kernel
├── configs/                   # per-variant ENABLE_ICACHE / ENABLE_DCACHE / ENABLE_PREFETCH / INNER_REPS
├── include/
│   ├── harness.h              # BENCH / END_BENCH (+ internal KERNEL_BEGIN/END)
│   ├── dwt.h                  # DWT register defines
│   └── m5ops_semi.h           # m5 op codes + param-block layout
├── src/
│   ├── startup.c              # vector table + Reset_Handler → main
│   ├── system_init.c          # FPU + PLL170 + FLASH LATENCY
│   ├── flash_config.c         # FLASH->ACR cache/prefetch bits per variant
│   └── main.c                 # init → bench_entry() → semihosting print → exit
├── kernels/
│   └── alu/                  # categorized subdir; one dir per category (alu, branch, mem, …)
│       ├── bench_nop16_8.S   # scaling-sweep NOP kernels (8..80, step 8)
│       ├── ...
│       └── bench_nop16_100.S # canonical 100 × nop.n template
├── openocd/
│   ├── stlink.cfg
│   └── stm32g4x.cfg
├── scripts/
│   └── parse_results.py
└── test/                      # build / layout / disassembly / board-run scripts
```

## Build

Requires `arm-none-eabi-gcc`, `cmake ≥ 3.20`, GNU make, and (for
flashing) `openocd`.

```bash
cd microbenchmark

# hardware — default variant (all flash accelerators on)
cmake --preset hw-stm32g474re && cmake --build build/hw-stm32g474re -j4

# hardware — cache/prefetch variants
cmake --preset hw-nocache-stm32g474re    && cmake --build build/hw-nocache-stm32g474re    -j4
cmake --preset hw-noprefetch-stm32g474re && cmake --build build/hw-noprefetch-stm32g474re -j4
cmake --preset hw-none-stm32g474re       && cmake --build build/hw-none-stm32g474re       -j4

# gem5 (m5op-instrumented; feed the ELF to your gem5 Cortex-M fork)
cmake --preset gem5-stm32g474re && cmake --build build/gem5-stm32g474re -j4
```

Each per-target build prints a post-build report with size, pinned
symbols, kernel-body symbols, and the I-cache size check:

```
[100%] Linking C executable bin/bench_nop16_100.elf
   text    data     bss     dec     hex filename
   1768      24    1672    3464     d88 build/hw-stm32g474re/bin/bench_nop16_100.elf
kernel-body symbols:
080004a8 T _bench_body_end
08000480 T _bench_body_start
08000400 T bench_entry
[bench_nop16_100] kernel_body = 202 bytes / I-cache = 1024 bytes — ok
```

Verify `_bench_body_start = 08000480` for every variant.

### Variant matrix


| Preset                      | PLATFORM   | BOARD         | HW_VARIANT   | ICACHE | DCACHE | PREFETCH |
| --------------------------- | ---------- | ------------- | ------------ | ------ | ------ | -------- |
| `gem5-stm32g474re`          | `gem5`     | `stm32g474re` | —            | —      | —      | —        |
| `hw-stm32g474re`            | `hardware` | `stm32g474re` | `full`       | on     | on     | on       |
| `hw-nocache-stm32g474re`    | `hardware` | `stm32g474re` | `nocache`    | off    | off    | on       |
| `hw-noprefetch-stm32g474re` | `hardware` | `stm32g474re` | `noprefetch` | on     | on     | off      |
| `hw-none-stm32g474re`       | `hardware` | `stm32g474re` | `none`       | off    | off    | off      |


(All hardware variants run at PLL 170 MHz with FLASH LATENCY=4; gem5
doesn't model RCC/FLASH so those columns don't apply.)

### Measurement overhead per variant

Empirically the harness reports

```
inner  =  slope · N  +  intercept
```

for an N-instruction warm-cache kernel. The slope is the effective
fetch CPI under each variant's cache+prefetch policy; the intercept is
the per-rep measurement framing (the `ldr/bl/…/bx/ldr` scaffolding
around your kernel body). Measured 2026-05-12 on STM32G474RE:

| Variant                     | slope (c/NOP) | intercept (framing, c) |
|-----------------------------|--------------:|-----------------------:|
| `hw-stm32g474re`            |         1.000 |                      6 |
| `hw-noprefetch-stm32g474re` |         1.000 |                      7 |
| `hw-nocache-stm32g474re`    |         1.250 |                     20 |
| `hw-none-stm32g474re`       |         1.500 |                     17 |

So to back out the **pure kernel cycles** from a measured `inner`
on a given variant, subtract that variant's intercept.

Full derivation, residuals, methodology, and reproduction steps:
[`board/stm32g474re/measurement_overhead.md`](board/stm32g474re/measurement_overhead.md).
Re-run the sweep with `python3 ./scripts/scaling_nop16_sweep.py` after
any change to the BENCH macro, the clock, or the variant set.

### Post-link size check

Every build runs [`scripts/check_kernel_size.py`](scripts/check_kernel_size.py)
post-link: extract the `.size`-tagged byte length of `kernel_body`
from the ELF and compare it against `ICACHE_SIZE_BYTES` from the
board config. If the kernel exceeds the I-cache (so the warmup can't
fully prime it and "warm-cache" measurements lose meaning), the build
fails with a message naming the kernel, both sizes, and the override.

To intentionally measure an oversized kernel:

```bash
cmake --preset hw-stm32g474re -DALLOW_KERNEL_EXCEED_ICACHE=ON
```

The check still prints sizes; it just no longer fails the build.

## Running on the board (WSL via usbipd-win)

The board's ST-Link is on USB. Inside WSL we need it to enumerate as a
USB device, which requires `usbipd-win` on the Windows host.

### One-time WSL setup

```powershell
# Windows PowerShell, admin:
winget install --interactive --exact dorssel.usbipd-win
usbipd list                              # find ST-Link bus-id, e.g. 1-4
usbipd bind --busid 1-4
```

### Per-session attach

```powershell
# Windows, each time you plug in the board or reboot WSL:
usbipd attach --wsl --busid 1-4
```

```bash
# Inside WSL — confirm:
lsusb | grep -iE "ST-?LINK"
# Bus 001 Device 002: ID 0483:374e STMicroelectronics STLINK-V3
```

If `lsusb` doesn't show ST-Link, the attach didn't take — re-run
`usbipd attach` on Windows.

### Flash + run + capture log

```bash
python3 ./test/test_board_run.py                          # defaults: hw-stm32g474re + bench_nop16_100
python3 ./test/test_board_run.py hw-nocache-stm32g474re   # a different variant
python3 ./test/test_board_run.py hw-stm32g474re bench_<name>   # a different kernel
python3 ./test/test_board_run_all.py                      # sweep all 4 hw variants
python3 ./test/test_board_run_all.py bench_<name>         # sweep, different kernel
```

Example sweep output (INNER_REPS=10):

```
========== summary (bench_nop16_100) ==========
variant                       avg  log
-------                       ---  ---
hw-stm32g474re                106  test/logs/hw-stm32g474re/bench_nop16_100.log
hw-nocache-stm32g474re        150  test/logs/hw-nocache-stm32g474re/bench_nop16_100.log
hw-noprefetch-stm32g474re     106  test/logs/hw-noprefetch-stm32g474re/bench_nop16_100.log
hw-none-stm32g474re           167  test/logs/hw-none-stm32g474re/bench_nop16_100.log
```

Notice the data: `hw-stm32g474re` and `hw-noprefetch-stm32g474re` both
give an average `inner=106` (the warmup populates the I-cache, so
every measured call hits cache). `hw-nocache-stm32g474re` and
`hw-none-stm32g474re` give 150 and 167 — with I-cache OFF, the warmup
can't actually warm anything, so the "warm-cache" measured calls are
still cold-flash. The exact gap (~44–61 cycles for 100 NOPs) matches
the flash-bandwidth model.

The full per-rep list for each variant is in
`test/logs/<variant>/<bench>.log`. The headline average is in
`test/logs/<variant>/<bench>.cycles.txt` (one integer).

The test script handles flashing + capture + parsing + saving the log
under `test/logs/<variant>/<bench>.{log,cycles.txt}`. To invoke
OpenOCD directly:

```bash
openocd -f openocd/stlink.cfg -f openocd/stm32g4x.cfg \
        -c 'init' -c 'reset' -c 'halt' \
        -c 'arm semihosting enable' \
        -c 'program build/hw-stm32g474re/bin/<bench>.elf verify' \
        -c 'reset run'
```

OpenOCD stays attached and prints the board's semihosting output. Stop
with Ctrl-C.

## Reading results

### Hardware (`hardware*` builds)

The board prints one semihosting line per measured rep:

```
MICROBENCH name=bench_nop16_100 rep=0 inner=106
MICROBENCH name=bench_nop16_100 rep=1 inner=106
...
MICROBENCH name=bench_nop16_100 rep=9 inner=106
```

- **`inner`** — cycles between the two snap-ldrs around one warm-cache
  call. Reported independently for every rep.
- **`rep`** — the rep index (0..INNER_REPS-1). The cold warmup call
  before rep 0 is NOT in any rep's window.

Extract programmatically. The headline metric is the **average**:

```bash
grep MICROBENCH test/logs/hw-stm32g474re/bench_nop16_100.log
# MICROBENCH name=bench_nop16_100 rep=0 inner=106
# MICROBENCH name=bench_nop16_100 rep=1 inner=106
# ...

python3 ./scripts/parse_results.py test/logs/hw-stm32g474re/bench_nop16_100.log
# bench_nop16_100    106                # average across all reps

python3 ./scripts/parse_results.py test/logs/hw-stm32g474re/bench_nop16_100.log --per-rep
# bench_nop16_100    0    106
# bench_nop16_100    1    106
# ...
```

For a body that fits in cache, every rep on every cache-on hw variant
should give the same `inner` — the warmup primes the cache once and
every subsequent measured call hits it. Variance between reps (or
between cache-on and cache-off variants) tells you what cache and
prefetch contribute.

### gem5

The gem5 ELF prints a single `MICROBENCH name=<bench>` marker line via
semihosting (no cycle field — gem5 doesn't write the cycle count back
into the binary the way DWT_CYCCNT does). Instead, the harness emits
**`m5_work_begin`** immediately before each measured call and
**`m5_work_end`** immediately after, producing **one work region per
rep** (INNER_REPS regions total). Cycles inside each region come from
gem5's stat machinery.

How to capture them depends on your gem5 fork's configuration. Common
setups:

- Run with stat-dumping on work-begin / work-end transitions (your
fork's flag for this varies). Each rep appears in `m5out/stats.txt`
as its own `Begin … End Simulation Statistics` block; read
`system.cpu.numCycles` (or your fork's equivalent) inside each.
- After the program exits via `m5_exit`, gem5 dumps a final stats
block. With `m5_work_begin` / `m5_work_end` as scope markers, gem5
may also report `system.cpu.workload.statistics::numCycles` keyed on
the work id.

```bash
python3 ./scripts/parse_results.py m5out/stats.txt
# system.cpu.numCycles    <average across all reps>

python3 ./scripts/parse_results.py m5out/stats.txt --per-rep
# system.cpu.numCycles    0    <N>
# system.cpu.numCycles    1    <N>
# ...
```

Override the stat name with `--stat <name>` if your fork uses a
different identifier; `--window all` dumps every rep's full stats
window for browsing.

The warmup call's cycles are NOT in any work region — `m5_work_begin`
fires only after the warmup returns, just before rep 0's measured call.

## Adding your own kernel

The harness exposes one assembly macro pair, `BENCH ... END_BENCH`.
It wraps your code as a function, calls it once to warm the I-cache,
then loops `INNER_REPS` times bracketing each measured call with
snapshots placed immediately around it. So if your body executes `N`
cycles of instructions, every rep reports `inner = N + 6` on hardware
(6 = bl + bx lr + 1c ldr-distance).

### Step 1 — Write the kernel file

Drop a new file under `kernels/<category>/`, named
`kernels/<category>/bench_<your_name>.S`. The category is one of the
existing subdirs (`alu`, …); create a new subdir for a new category
(e.g. `kernels/branch/`). Register the `(category, bench)` pair in
`CMakeLists.txt`'s `BENCHMARKS_BY_CATEGORY` list and in the experiment's
`config/benchmarks.txt` so MAE attribution picks it up.

Inside, write a single block of Thumb-2 assembly between the
`BENCH` markers:

```asm
#include "harness.h"

    BENCH
        @ your instructions go here
        @ — runs as a function called by the harness
        @ — must follow AAPCS (preserve r4-r11 if you touch them)
        @ — DO NOT emit `bx lr` — END_BENCH does it for you
    END_BENCH
```

Three examples, escalating in register usage:

**a) 100 × `nop.n`** — the template (`kernels/alu/bench_nop16_100.S`):

```asm
#include "harness.h"

    BENCH
        .rept 100
        nop.n
        .endr
    END_BENCH
```

Expected: `inner = 100 (NOPs at CPI=1.0) + 6 (framing) = 106`.

**b) 100 × `adds`** — free caller-saved registers only, no push/pop:

```asm
#include "harness.h"

    BENCH
        movs r1, #0                @ r1 is free on both platforms
        .rept 100
        adds r1, r1, #1
        .endr
    END_BENCH
```

Expected: `inner ≈ 107` (1 movs + 100 adds + 6c framing).
**Don't use r0 or r3** here — they hold harness state across each
measured `bl` on hardware (see register contract below). r1, r2, r12
are always safe.

**c) Using callee-saved registers** — push/pop them yourself:

```asm
#include "harness.h"

    BENCH
        push {r4, r5}              @ AAPCS: must preserve r4-r11
        movs r4, #0
        movs r5, #1
        .rept 100
        adds r4, r4, r5
        .endr
        pop  {r4, r5}
    END_BENCH
```

Expected: `inner ≈ 113` (push + 2 movs + 100 adds + pop + 6c framing,
where push/pop {r4,r5} is ~3 cycles each = 1+N for N=2 registers).

### Step 2 — Register it in CMake

Open [CMakeLists.txt](CMakeLists.txt), find the `BENCHMARKS` line,
and append your kernel name:

```cmake
set(BENCHMARKS bench_nop16_100 bench_<your_name>)
```

### Step 3 — Build

```bash
cmake --build build/hw-stm32g474re -j4 --target bench_<your_name>.elf
```

If the CMake cache is stale, `cmake --preset hw-stm32g474re` refreshes it.

### Step 4 — Run

```bash
python3 ./test/test_board_run.py hw-stm32g474re bench_<your_name>
```

The per-rep `inner` values in the output are your kernel's warm-cache
cycle count. Subtract 6 to get just your body's instruction cost.

### Constraints

- **Body must fit in the board's FLITF I-cache** (1 KiB = 32 × 32-byte
  lines on STM32G474RE; size comes from
  [`board/<board>/board.cmake`](board/stm32g474re/board.cmake)). Builds
  fail at post-link if `kernel_body` exceeds it — override with
  `-DALLOW_KERNEL_EXCEED_ICACHE=ON` if you intentionally want to
  measure a partially-cold-cache kernel.
- **Flash-resident kernel data must fit in the board's D-cache**
(256 bytes on STM32G474RE). A kernel opts into the check by placing
its read-only data in a `.rodata.kernel_data` (or
`.rodata.kernel_data.*`) input section; the linker brackets that
region with `__kernel_data_start` / `__kernel_data_end` symbols and
the post-link guard compares `end - start` to `DCACHE_SIZE_BYTES`.
Override with `-DALLOW_KERNEL_EXCEED_DCACHE=ON`. Kernels that don't
declare a `.rodata.kernel_data` section have a zero-byte data
footprint and always pass.
- **Register contract.** The harness keeps live state in specific
registers across every measured `bl kernel_body`. The kernel must
leave those unchanged on return (or push/pop them itself):

  | Reg        | Hardware — what the harness keeps here           | gem5 — what the harness keeps here |
  | ---------- | ------------------------------------------------ | ---------------------------------- |
  | `r0`       | DWT_CYCCNT address (per-rep `ldr [r0]` snaps)    | reloaded around each bkpt — free   |
  | `r1`, `r2` | not used across `bl` — free                      | not used across `bl` — free        |
  | `r3`       | `&_inner_delta_cyc[]` (post-incremented per rep) | not used — free                    |
  | `r4`       | start CYCCNT (read back for end − start)         | not used — free                    |
  | `r5`       | remaining rep count                              | remaining rep count                |
  | `r6`–`r11` | not used across `bl` — AAPCS callee-saved        | same                               |
  | `r12`      | not used — free                                  | not used — free                    |
  | `lr`, `sp` | harness-managed — don't touch                    | same                               |

  Most of those are already AAPCS-callee-saved (r4–r11), so writing
  AAPCS-compliant code automatically protects **r4** and **r5**. The
  two registers that need EXTRA discipline beyond AAPCS — because
  they're caller-saved but the harness still keeps live state in them
  across the `bl` — are **r0** and **r3** on hardware.
  Short rule: **on hardware, don't clobber r0, r3, r4, r5** across the
  measured call. Free caller-saved scratch on both platforms: r1, r2,
  r12 (plus r6–r11 with push/pop). For kernels that build on both
  platforms from the same source, treat r0, r3, r4, r5 as
  harness-reserved everywhere — strictest contract, works on both.
- **Do NOT emit `bx lr` yourself.** `END_BENCH` emits it for you.
- **No `.data` / `.bss` inside the macro.** If you need SRAM scratch,
declare it in a separate file and reference the symbol from your
kernel.

### What if my body is bigger than the I-cache?

Loop a smaller body inside `BENCH` — `inner` reports per-call
cycles including the branch overhead:

```asm
    BENCH
        movs r1, #4                @ outer counter (caller-saved)
loop:
        .rept 50                   @ inner body — 100 bytes, fits in cache
        nop.n
        .endr
        subs r1, r1, #1
        bne  loop
    END_BENCH
```

Cache footprint here: 100-byte inner + 4 bytes subs + 4 bytes bne ≈
108 bytes ≤ 256. Each iteration costs 50 NOPs + 1 subs + ~2 bne
(taken) ≈ 53 cycles, so `inner ≈ 4 × 53 + 6 ≈ 218`.

## Tests

The Python scripts under `test/` cover build verification, layout
invariants, disassembly artifacts, and board sweeps.

```bash
python3 ./test/run_all_tests.py            # all stages in order; board stage auto-skips if no ST-Link
python3 ./test/run_all_tests.py --no-board # explicit skip of stage 4
python3 ./test/test_build_all.py           # configure + build all 5 presets, verify pinned symbols
python3 ./test/test_layout_identical.py    # SHA-256 invariants
python3 ./test/test_disassembly.py         # dump test/disasm/<preset>/ artifacts + cross-build diffs
python3 ./test/test_board_run.py           # flash + run one preset
python3 ./test/test_board_run_all.py       # flash + run all 4 hw variants
```

Example layout-invariant output:

```
==> kernel_body bytes byte-identical across all targets (gem5 + 4 hardware)
    gem5-stm32g474re           209f4cbfb35c39085321b035c7549c9e49f285c186b8ab50543405b34501a279
    hw-stm32g474re             209f4cbfb35c39085321b035c7549c9e49f285c186b8ab50543405b34501a279
    hw-nocache-stm32g474re     209f4cbfb35c39085321b035c7549c9e49f285c186b8ab50543405b34501a279
    hw-noprefetch-stm32g474re  209f4cbfb35c39085321b035c7549c9e49f285c186b8ab50543405b34501a279
    hw-none-stm32g474re        209f4cbfb35c39085321b035c7549c9e49f285c186b8ab50543405b34501a279

==> bench_entry wrapper bytes byte-identical across the 4 hardware cache variants
    hw-stm32g474re             ae2bc9fc92b57cae3a2b73d89e5038c5a7930afba4c2bdd0032cb83cea4f6d72
    hw-nocache-stm32g474re     ae2bc9fc92b57cae3a2b73d89e5038c5a7930afba4c2bdd0032cb83cea4f6d72
    hw-noprefetch-stm32g474re  ae2bc9fc92b57cae3a2b73d89e5038c5a7930afba4c2bdd0032cb83cea4f6d72
    hw-none-stm32g474re        ae2bc9fc92b57cae3a2b73d89e5038c5a7930afba4c2bdd0032cb83cea4f6d72

All layout invariants hold.
```

The two invariants:

1. **`kernel_body` bytes** are identical across **all 5 builds**
   (gem5 + 4 hardware). This is what makes gem5↔hardware cycle
   comparisons meaningful — same workload bytes execute on both
   targets.
2. **bench_entry wrapper bytes** are identical across the **4 hardware
  cache variants**. Wrapper bytes differ between hardware and gem5 by
   design (different markers); they only need to be consistent within
   the hardware family so cross-variant comparisons see only the
   cache/prefetch difference.

See [test/README.md](test/README.md) for per-script details.

## Adding a new HW variant (same board, different cache settings)

1. Drop a `configs/hardware-<name>.cmake` setting `ENABLE_ICACHE`,
  `ENABLE_DCACHE`, `ENABLE_PREFETCH`, and `INNER_REPS`.
2. Add a matching preset to `CMakePresets.json` with
  `"PLATFORM": "hardware"`, `"BOARD": "<board>"`, and
   `"HW_VARIANT": "<name>"`. The preset name convention is
   `hw-<variant>-<board>`.

## Adding a new board

1. Create `board/<board>/` with:
  - `board.cmake` defining `BOARD_LINKER_SCRIPT`,
   `BOARD_OPENOCD_TARGET_CFG`, `BOARD_INCLUDE_DIR`,
   `ICACHE_SIZE_BYTES`, `DCACHE_SIZE_BYTES`.
  - The linker script (with the `__kernel_data_start` /
  `__kernel_data_end` sentinels inside `.rodata` so the D-cache
  check works).
  - The board-specific openocd target cfg.
  - Any board-specific headers (e.g. `dwt.h` if the board's debug
  architecture differs).
2. Add presets to `CMakePresets.json`: at minimum
  `gem5-<board>` and `hw-<board>` (plus any cache variants).

Build and run (substituting `<name>` for your new variant on the
existing `stm32g474re` board):

```bash
cmake --preset hw-<name>-stm32g474re && cmake --build build/hw-<name>-stm32g474re -j4
python3 ./test/test_board_run.py hw-<name>-stm32g474re
```


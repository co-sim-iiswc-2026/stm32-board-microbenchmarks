# kernels/

Microbenchmark kernels for the Cortex-M4 ↔ gem5 cycle-accuracy
validation workflow. Each `.S` file under `alu/` and `fp/` builds into
one runnable ELF via the
[BENCH harness](../include/harness.h) and reports per-rep cycle counts
on the STM32G474RE board and on Zhantong's gem5 Cortex-M fork.

Build, flash, and run mechanics live in
[`../README.md`](../README.md). This document is about *what the
kernels in this directory measure, why we designed them this way, and
what they actually report*.

## Purpose — gem5 decoder validation

Each kernel exercises one well-defined path in the gem5 M-profile
decoder at
[`gem5/src/arch/arm/m_decoder.cc`](../../../gem5/src/arch/arm/m_decoder.cc).
Because every measured call to `kernel_body` flows through exactly one
mnemonic in a controlled register/dependency pattern, the
board-reported `inner` cycles become **per-mnemonic ground truth**.
Diff the same kernels' gem5 `numCycles` (one work region per rep, see
[`../README.md§gem5`](../README.md)) against the board numbers below to
spot decoder modelling bugs — wrong op-class assignment, wrong
operand-bit decoding, missing data-dependent latency, etc.

## Naming convention

```
bench_<op>[_<variant>]_<N>.S
```

- **`op`** — mnemonic family (`vadd`, `vfma`, `sdiv`, `mul`, `lsl_reg`, …).
- **`variant`** — optional disambiguator, e.g.
  - `_imm` / `_reg` / `_c2f` / `_f2c` for VMOV forms,
  - `_zero` for VCMP-against-zero,
  - `_fast` / `_mid` / `_slow` for DIV operand strata,
  - `_f32_s32` / `_s16_f32fx` / … for VCVT direction × type.
- **`N`** — instruction count in the body.

## Size convention — why 8 / 9 / 16 / 100

Every kernel (except the NOP scaling sweep, see below) exists at four
sizes for a specific reason:

| N | what it tells you |
|---|---|
| **8**   | Baseline. 8 × 2 B Thumb = 16 B = exactly **2 × 64-bit FLITF flash lines** — all instructions aligned with the fetch granularity. |
| **9**   | One past the boundary. The 9th instruction spills onto a 3rd flash line, exposing partial-cache-line fetch cost. |
| **16**  | 8 more aligned instructions than N=8. Differencing `inner(16) − inner(8)` reveals steady-state per-op cost without harness framing. |
| **100** | A larger, "more complex" body. Pipelining, prefetching, and any non-linear effects show; small enough to fit the 1 KiB I-cache. |

The four-size design also lets us **fit a linear model** to each
kernel — see *How to read the cycle tables* below.

The one exception is the **NOP scaling sweep**
(`bench_nop16_{8,9,16,24,32,40,48,56,64,72,80,100}`): 12 sizes stepping
by 8 NOPs (= 2 × FLITF flash lines), used by
`scripts/scaling_nop16_sweep.py` to linear-fit per-NOP fetch cost and
the harness framing intercept per hardware variant.

## Register contract — quick reference

See [`../include/harness.h:39-67`](../include/harness.h) for the
canonical table. Short rule:

- **Reserved across the body on hardware**: `r0`, `r3`, `r4`, `r5`. Do
  not clobber.
- **Free caller-saved scratch on both platforms**: `r1`, `r2`, `r12`.
- **AAPCS callee-saved** (use with push/pop): `r6`–`r11`.
- **FP registers**: all of `s0`–`s15` / `d0`–`d7` are free. The harness
  keeps no state in the FPU register file.
- **`lr`, `sp`**: harness-managed; do not touch.
- **Do not emit `bx lr`** — `END_BENCH` emits it.

## How to read the cycle tables

For every kernel × hardware variant, we fit the **linear model**

```
inner = CPI · N + OH
```

via least-squares across all four measured sizes (or all 12 for the
NOP sweep), where:

- **`CPI`** is the per-instruction cycle cost under this kernel's
  specific dependency-chain shape on this variant. A two-source op
  with `s0` as both destination and source (`vadd s0,s0,s1`) exposes
  back-to-back latency; a no-dep op (`vabs s0,s1`) exposes throughput.
  The CPI you measure depends on the dep pattern, not just the
  instruction.
- **`OH`** is the per-(kernel, variant) overhead in cycles. It bundles:
  - the harness framing (~6 cycles: `bl` + `bx lr` + ldr-distance — see
    [`../README.md§Measurement-overhead-per-variant`](../README.md)),
  - the one-shot register setup inside `BENCH` before `.rept` (e.g.
    `vmov.f32 s1, #1.0` adds ~1 cycle; the DIV `movw/movt` quartet
    adds ~4 cycles),
  - any variant-specific cache-warming effect on the first measured rep.
- A trailing **`(±err)`** indicates the maximum absolute residual
  (cycles between measured and predicted at any single N) when the
  linear model doesn't fit perfectly. Residuals below 0.5 are not
  shown — those rows are *perfectly linear* in N.

So each table cell `2·N+6` reads as: per-op cost 2 cycles, kernel
overhead 6 cycles. A cell like `2.49·N+21 (±1.6)` says CPI ≈ 2.49,
overhead ≈ 21, and the model misses any single size by at most 1.6
cycles.

### Worked example — `bench_vadd_100` on `hw-full`

Measured raw values: N=8 → 22, N=9 → 24, N=16 → 38, N=100 → 206.

Least-squares fit gives **`CPI = 2.000`, `OH = 6.000`** — a perfectly
linear model (residual 0 at every size). Interpretation:

- The 6-cycle `OH` is **exactly** the harness framing cost on `hw-full`
  (no setup contribution here, because `vmov.f32 s1, #1.0` lands at the
  same place in every size and the framing intercept on this variant
  is 6).
- The 2-cycle/op CPI is **double** the M4's nominal 1-cycle issue rate
  for `vadd.f32` — because the kernel writes `s0` and reads `s0` on
  consecutive iterations, every `vadd` has to wait for the previous
  one's result to forward. The kernel measures **latency under a
  back-to-back dep chain**, not throughput.

Same exercise on `hw-nocache`: `CPI = 2.49, OH = 20.96, ±1.6`. CPI
climbs because the prefetcher can't keep up with the 2 B/cycle Thumb
fetch when the I-cache is off; OH absorbs the larger framing cost (the
variant-specific intercept is 20, not 6); and the small residual
reflects the partial-line fetch boundary at N=9 — fetch cost is not
perfectly linear in N when each new line costs a wait-state burst.

The next sections give the per-family fits. Whenever a residual
exceeds ~1 cycle, it's flagged with `(±err)` so readers can see at a
glance which kernels are clean linear and which carry measurement noise.

---
## `alu/` category — 56 kernels

### NOP scaling sweep — 12 kernels

`bench_nop16_{8,9,16,24,32,40,48,56,64,72,80,100}` — 12 × 16-bit Thumb
NOPs (`nop.n`). Used by `scripts/scaling_nop16_sweep.py` to linear-fit
per-NOP fetch cost and harness framing per variant. Sizes step by 8 NOPs
= 2 × 64-bit FLITF flash lines. `bench_nop16_9` is the off-grid
datapoint that tests the "fetch finishes inside or outside the inner
window" question.

**Body shape:** `.rept N; nop.n; .endr` — no register state.

**Linear fit across all 12 sizes:**

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `nop16` | 1·N+6 | 1·N+6.7 (±0.8) | 1.25·N+19.7 (±1.0) | 1.49·N+17.9 (±2.7) |

**Raw measured cycles (for the slope/intercept derivation):**

| N | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| 8 | 14 | 15 | 30 | 29 |
| 9 | 15 | 15 | 30 | 34 |
| 16 | 22 | 23 | 40 | 41 |
| 24 | 30 | 31 | 50 | 53 |
| 32 | 38 | 39 | 60 | 65 |
| 40 | 46 | 47 | 70 | 77 |
| 48 | 54 | 55 | 80 | 89 |
| 56 | 62 | 63 | 90 | 101 |
| 64 | 70 | 71 | 100 | 113 |
| 72 | 78 | 79 | 110 | 125 |
| 80 | 86 | 87 | 120 | 137 |
| 100 | 106 | 107 | 145 | 167 |

### ADD encoding-width sweep — 8 kernels

`bench_add16_{8,16,24,100}` (narrow Thumb T1, 2 B) vs.
`bench_add32_{8,16,24,100}` (wide Thumb-2 T3, 4 B). Same semantic
operation (`adds Rd, Rd, #1` on `r1`), different encoding width.
Pairing them at matched N isolates fetch cost from execute cost.

**Body shape:** `.rept N; adds.n r1, r1, #1; .endr`  (or `adds.w` for `add32`).

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `add16` | 1·N+6 | 1·N+7 | 1.25·N+20 | 1.5·N+17 |
| `add32` | 1·N+6 | 1·N+6 | 2.5·N+20 | 3·N+17 |

### Integer ALU validation — 36 kernels (new)

#### `mul` — 4 sizes

T2 32-bit Thumb-2 encoding, separate destination, no flag-set.
Cortex-M4 = 1 cycle/op (per attached TRM errata correction).

**Body:** `mul r12, r1, r2` after `movw r1,#0x1234; movw r2,#0x0005`.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `mul` | 1·N+8 | 1·N+8 | 2.51·N+24 (±1.6) | 2.99·N+23.8 (±1.3) |

#### `umull` — 4 sizes

32×32 → 64 unsigned multiply long; writes the `RdLo:RdHi` register
pair. Cortex-M4 = 1 cycle/op.

**Body:** `umull r12, r2, r1, r1` after `movw r1, #0x1234`. The
`Rn = Rm = r1` (squared-multiplicand) trick avoids needing a fourth
free register beyond `r1`, `r2`, `r12`.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `umull` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |

#### `lsl_reg` — 4 sizes

Logical shift left by **register** (T2 32-bit Thumb-2 form). Distinct
decoder path from `LSL Rd, Rn, #imm` (shift by immediate). Cortex-M4 =
1 cycle/op.

**Body:** `lsl.w r12, r1, r2` after `movw r1, #0x00FF; movs r2, #4`.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `lsl_reg` | 1·N+8 | 1·N+8 | 2.49·N+21 (±1.6) | 2.99·N+23.2 (±2.0) |

#### SDIV / UDIV — *significant*, 6 latency strata × 4 sizes = 24 kernels

Cortex-M4 integer divide is **2 to 12 cycles via early termination**,
based on the relationship between the dividend's and divisor's leading
bits (per the Cortex-M4 TRM Errata 01 table). Both `sdiv` and `udiv`
dispatch to gem5's `IntDivOp`; correct modelling requires
**data-dependent latency**, which a naïve simulator with a fixed cost
can easily miss.

Three latency strata per sign:

| stratum | r1 (dividend) | r2 (divisor) | observed CPI on hw-full | rationale |
|---|---|---|---|---|
| **fast** | 0x00000001              | 0xFFFFFFFE |  ~3–5  | small dividend → terminator fires early |
| **mid**  | 0x00FFFFFF              | 0x00000010 |  ~9    | ~24-bit dividend vs ~5-bit divisor |
| **slow** | 0x7FFFFFFF / 0xFFFFFFFF | 0x00000001 |  12    | full-width / divisor=1 → no early termination |

(UDIV slow uses `0xFFFFFFFF` for full unsigned width; SDIV slow uses
`0x7FFFFFFF` to stay positive after sign-interpretation.)

**Setup:** 4 movw/movt before `.rept` loads `r1`, `r2` once. **Body:**
`sdiv r12, r1, r2` (or `udiv`). Every iteration reads the same `r1`,
`r2` so every divide takes the same latency.

**Note:** Observed CPI is the **measured** per-op cost from the
least-squares fit, not the M4 TRM's nominal range estimate. The TRM
documents 2–12 cycles total range; the observed `fast` cases land
slightly above the nominal "2c best case" — the operands used here
exercise early termination but not the absolute fastest path. Treat
the measured CPI as ground truth.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `sdiv_fast` | 5·N+10 | 5·N+10 | 5·N+22 | 5·N+25 |
| `sdiv_mid` | 9·N+10 | 9·N+10 | 9·N+22 | 9·N+25 |
| `sdiv_slow` | 12·N+10 | 12·N+10 | 12·N+22 | 12·N+25 |
| `udiv_fast` | 3·N+10 | 3·N+10 | 2.98·N+26.3 (±1.9) | 2.99·N+29.8 (±1.3) |
| `udiv_mid` | 9·N+10 | 9·N+10 | 9·N+22 | 9·N+25 |
| `udiv_slow` | 12·N+10 | 12·N+10 | 12·N+22 | 12·N+25 |

---

## `fp/` category — 128 kernels (new)

All single-precision (FPv4-SP-d16). The board has no double-precision
FPU; double-precision arithmetic is excluded by design.

Each kernel uses inline FP register setup (e.g. `vmov.f32 s1, #1.0`)
right before `.rept`. All `s0`–`s15` are entirely free of harness
state, so kernels can freely overwrite them.

### Decoder-coverage matrix

Maps each FP kernel family to the gem5 class it exercises in
[`m_decoder.cc`](../../../gem5/src/arch/arm/m_decoder.cc):

| gem5 decoder class | OpClass | mnemonics covered |
|---|---|---|
| `MFpBinS` | `SimdFloatAddOp`     | `vadd`, `vsub` |
| `MFpBinS` | `SimdFloatMultOp`    | `vmul`, `vnmul` |
| `MFpBinS` | `SimdFloatDivOp`     | `vdiv` |
| `MFpTernaryS` | `SimdFloatMultAccOp` | `vmla`, `vmls`, `vnmla`, `vnmls` |
| `MFpFusedMulAddS` | `SimdFloatMultAccOp` | `vfma`, `vfms`, `vfnma`, `vfnms` |
| `MFpUnaryS` | `SimdFloatSqrtOp`  | `vsqrt` |
| `MFpUnaryS` | `SimdFloatMiscOp`  | `vabs`, `vneg` |
| `MFpMovImmS` | —                 | `vmov_imm` |
| `MFpMovRegS` | —                 | `vmov_reg` |
| VFP↔core single-prec transfer | — | `vmov_c2f`, `vmov_f2c` |
| `MFpCmpS` | `SimdFloatCmpOp`    | `vcmp`, `vcmpe`, `vcmp_zero`, `vcmpe_zero` |
| `MFpCvtS` | `SimdFloatCvtOp`    | `vcvt_f32_{s32,u32}`, `vcvt_{s32,u32}_f32` |
| `MFpCvtFixedS` | `SimdFloatCvtOp` | `vcvt_f32_{s16fx,u16fx}`, `vcvt_{s16,u16}_f32fx` |

---

### Family: Binary arithmetic — 4 ops × 4 sizes

`vadd / vsub / vmul / vnmul`. Body: `<op>.f32 s0, s0, s1` after
`vmov.f32 s1, #1.0`. The destination is also a source on `s0` — every
iteration's result feeds the next iteration's operand, so the
measurement exposes **back-to-back FP-add/mul latency**, not pipelined
throughput.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `vadd` | 2·N+6 | 2·N+6 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vsub` | 2·N+6 | 2·N+6 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vmul` | 2·N+6 | 2·N+6 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vnmul` | 2·N+6 | 2·N+6 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |

### Family: Non-fused multiply-accumulate — 4 ops × 4 sizes

`vmla / vmls / vnmla / vnmls`. Body: `<op>.f32 s0, s1, s2` after
`vmov.f32 s1, #1.0; vmov.f32 s2, #2.0`. `s0` is the accumulator and
appears as both source and destination → inter-iteration dep chain on
`s0`. gem5 routes all four to `MFpTernaryS → SimdFloatMultAccOp` —
**double-rounding** semantics (one rounding for the multiply, one for
the add), which is **distinct** from the fused MAC family below.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `vmla` | 3·N+6 | 3·N+6 | 2.98·N+21.3 (±1.9) | 2.99·N+23.8 (±1.3) |
| `vmls` | 3·N+6 | 3·N+6 | 2.98·N+21.3 (±1.9) | 2.99·N+23.8 (±1.3) |
| `vnmla` | 3·N+6 | 3·N+6 | 2.98·N+21.3 (±1.9) | 2.99·N+23.8 (±1.3) |
| `vnmls` | 3·N+6 | 3·N+6 | 2.98·N+21.3 (±1.9) | 2.99·N+23.8 (±1.3) |

### Family: Fused multiply-accumulate — 4 ops × 4 sizes

`vfma / vfms / vfnma / vfnms`. Body: `<op>.f32 s0, s1, s2` after
`vmov.f32 s1, #1.0; vmov.f32 s2, #2.0`. Same dep-chain shape as
non-fused MAC, but gem5 routes these to `MFpFusedMulAddS` which calls
`fplibMulAdd<uint32_t>` for a **bit-exact single-rounding** result.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `vfma` | 3·N+6 | 3·N+6 | 2.98·N+21.3 (±1.9) | 2.99·N+23.8 (±1.3) |
| `vfms` | 3·N+6 | 3·N+6 | 2.98·N+21.3 (±1.9) | 2.99·N+23.8 (±1.3) |
| `vfnma` | 3·N+6 | 3·N+6 | 2.98·N+21.3 (±1.9) | 2.99·N+23.8 (±1.3) |
| `vfnms` | 3·N+6 | 3·N+6 | 2.98·N+21.3 (±1.9) | 2.99·N+23.8 (±1.3) |

### Family: Unary — 2 ops × 4 sizes

`vabs / vneg`. Body: `<op>.f32 s0, s1` after `vmov.f32 s1, #1.0`. No
inter-iteration dependence (s0 is destination only; s1 is constant), so
this is the throughput-bound case. Both route to `MFpUnaryS →
SimdFloatMiscOp`.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `vabs` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vneg` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |

### Significant: VDIV — non-pipelined ~14 cycles

gem5 `MFpBinS → SimdFloatDivOp` (m_decoder.cc:1066). **Body:**
`vdiv.f32 s0, s1, s2` after `vmov.f32 s1, #2.0; vmov.f32 s2, #3.0`.
Unlike integer divide, **FP divide on Cortex-M4 is not data-dependent**
— the FPU runs a fixed-latency non-pipelined sequence regardless of
operand bit-pattern. What makes this kernel interesting is the
non-pipelined property: even with no register dep between iterations
(`s0` is destination-only, `s1`/`s2` stay constant), every `vdiv.f32`
must wait for the previous one to leave the divide unit, so the kernel
measures the unit's full ~14-cycle non-pipelined latency per op.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `vdiv` | 14·N+-5 | 14·N+-5 | 14·N+8 | 14·N+10 |

### Significant: VSQRT — non-pipelined ~14 cycles

gem5 `MFpUnaryS → SimdFloatSqrtOp` (m_decoder.cc:1137). **Body:**
`vsqrt.f32 s0, s1` after `vmov.f32 s1, #2.0`. Same non-pipelined story
as VDIV.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `vsqrt` | 14·N+-6 | 14·N+-6 | 14·N+4 | 14·N+5 |

### Family: VMOV — 4 forms × 4 sizes

Four distinct decoder paths.

- **`vmov_imm`** — `VMOV.F32 Sd, #imm` via gem5 `MFpMovImmS`
  (m_decoder.cc:1116). Body: `vmov.f32 s0, #1.0`. No source register.
- **`vmov_reg`** — `VMOV.F32 Sd, Sm` via gem5 `MFpMovRegS`
  (m_decoder.cc:1123). Body: `vmov.f32 s0, s1` after
  `vmov.f32 s1, #1.0`.
- **`vmov_c2f`** — `VMOV Sn, Rt` (core→FPU) at m_decoder.cc:860. Body:
  `vmov s0, r1` after `movs r1, #1`. **Note** the elevated CPI here
  reflects the FP/integer register-file boundary crossing.
- **`vmov_f2c`** — `VMOV Rt, Sn` (FPU→core) at m_decoder.cc:858. Body:
  `vmov r1, s0` after `vmov.f32 s0, #1.0`.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `vmov_imm` | 1·N+6 | 1·N+6 | 2.51·N+19 (±1.6) | 2.99·N+17.8 (±1.3) |
| `vmov_reg` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vmov_c2f` | 1.34·N+6.3 | 1.34·N+6.3 | 2.51·N+19 (±1.6) | 3.01·N+20.8 (±2.0) |
| `vmov_f2c` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |

### Significant: VCMP family — gem5 has a documented decoder bug-fix here

gem5 `MFpCmpS` at [`m_decoder.cc:1140-1175`](../../../gem5/src/arch/arm/m_decoder.cc)
carries an in-source comment recording a fix to the `withExc`/`withZero`
bit decoding. Before the fix, `VCMPE-register` and `VCMP-zero` both
mis-decoded; the bug was hidden when the operand happened to be zero.
These four kernels exercise each combination:

| variant | mnemonic | distinguishing bit |
|---|---|---|
| `vcmp`       | VCMP register, no exception     | opc2 bit 0 = 0, opc3 bit 1 = 0 |
| `vcmpe`      | VCMPE register, with exception  | opc2 bit 0 = 0, opc3 bit 1 = 1 |
| `vcmp_zero`  | VCMP zero,    no exception      | opc2 bit 0 = 1, opc3 bit 1 = 0 |
| `vcmpe_zero` | VCMPE zero,   with exception    | opc2 bit 0 = 1, opc3 bit 1 = 1 |

Body for the register forms: `vcmp(e).f32 s0, s1` after `vmov.f32 s0,#1.0;
vmov.f32 s1,#2.0`. For the zero forms: `vcmp(e).f32 s0, #0.0` after
`vmov.f32 s0, #1.0`.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `vcmp` | 1·N+8 | 1·N+8 | 2.51·N+24 (±1.6) | 2.99·N+23.8 (±1.3) |
| `vcmpe` | 1·N+8 | 1·N+8 | 2.51·N+24 (±1.6) | 2.99·N+23.8 (±1.3) |
| `vcmp_zero` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vcmpe_zero` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |

### Significant: VCVT int↔float — gem5 has another documented bug-fix here

gem5 `MFpCvtS` at [`m_decoder.cc:1199-1212`](../../../gem5/src/arch/arm/m_decoder.cc)
carries an in-source comment recording a fix to the signed/unsigned bit
decoding for int→float. The prior implementation read the constant `1`
bit as the op bit, making every `vcvt.f32.u32` decode as
`vcvt.f32.s32`. These four kernels probe each direction × signedness:

| kernel | direction | sign |
|---|---|---|
| `vcvt_f32_s32` | int → float | signed |
| `vcvt_f32_u32` | int → float | unsigned |
| `vcvt_s32_f32` | float → int | signed |
| `vcvt_u32_f32` | float → int | unsigned |

Body: `<op> s0, s1` after `vmov.f32 s1, #1.0`. No inter-iter dep.

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `vcvt_f32_s32` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vcvt_f32_u32` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vcvt_s32_f32` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vcvt_u32_f32` | 1·N+7 | 1·N+7 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |

### Family: VCVT fixed-point — 4 forms × 4 sizes

gem5 `MFpCvtFixedS` (m_decoder.cc:1243). Unlike int↔float, the
fixed-point form uses a **single register for both source and
destination** (`VCVT.<dst>.<src> Sd, Sd, #fbits`) — the result of one
iteration becomes the input to the next, so this kernel has an
inter-iter dep on `s0` even though the body is single-operand.

All four use 16-bit fixed and `fbits = 1`. (The M-profile decoder
routes these through `MFpCvtFixedS` instead of the A-profile path,
which calls `checkAdvSIMDOrFPEnabled32()` and segfaults on an
M-profile system — see decoder comment at m_decoder.cc:1218-1245.)

| kernel | direction | sign | bit-width |
|---|---|---|---|
| `vcvt_f32_s16fx` | fixed → float | signed   | 16-bit |
| `vcvt_f32_u16fx` | fixed → float | unsigned | 16-bit |
| `vcvt_s16_f32fx` | float → fixed | signed   | 16-bit |
| `vcvt_u16_f32fx` | float → fixed | unsigned | 16-bit |

| op | hw-full | hw-noprefetch | hw-nocache | hw-none |
|---|---|---|---|---|
| `vcvt_f32_s16fx` | 2·N+6 | 2·N+6 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vcvt_f32_u16fx` | 2·N+6 | 2·N+6 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vcvt_s16_f32fx` | 2·N+6 | 2·N+6 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |
| `vcvt_u16_f32fx` | 2·N+6 | 2·N+6 | 2.49·N+21 (±1.6) | 3.01·N+21.2 (±1.3) |

---

## Measurement error — where the linear model breaks

Across all 184 kernels × 4 hardware variants, the linear fit
`inner = CPI · N + OH` is **exact** for most (kernel, variant) pairs —
the residual at every measured size is 0 or sub-cycle noise.

The exceptions cluster on the cache-off variants (`hw-nocache`,
`hw-none`), where each new 64-bit flash line costs the full
wait-state burst (5 HCLK at LATENCY=4) and the marginal cost of the
9th, 17th, 25th, … instruction is non-linear in N. For these kernels
the README's per-cell `(±err)` annotation surfaces the worst-case
residual; the cell is still useful (CPI captures the average per-op
cost in the linear region) but readers should know the fit isn't
mathematically tight.

Concretely, the largest residuals in this catalog:

| op | variant | CPI | OH | max\|resid\| | per-size residuals (N, resid) |
|---|---|---|---|---|---|
| `nop16` | hw-none | 1.49 | 17.9 | 2.72 | (8,-0.80), (9,+2.72), (16,-0.69), (24,-0.58), (32,-0.48), (40,-0.37), (48,-0.26), (56,-0.15), (64,-0.05), (72,+0.06), (80,+0.17), (100,+0.43) |
| `lsl_reg` | hw-none | 2.99 | 23.2 | 1.95 | (8,-1.06), (9,+1.95), (16,-0.96), (100,+0.06) |
| `vmov_c2f` | hw-none | 3.01 | 20.8 | 1.95 | (8,+1.06), (9,-1.95), (16,+0.96), (100,-0.06) |
| `vmla` | hw-nocache | 2.98 | 21.3 | 1.93 | (8,-0.12), (9,+1.90), (16,-1.93), (100,+0.15) |
| `vmls` | hw-nocache | 2.98 | 21.3 | 1.93 | (8,-0.12), (9,+1.90), (16,-1.93), (100,+0.15) |
| `vnmla` | hw-nocache | 2.98 | 21.3 | 1.93 | (8,-0.12), (9,+1.90), (16,-1.93), (100,+0.15) |
| `vnmls` | hw-nocache | 2.98 | 21.3 | 1.93 | (8,-0.12), (9,+1.90), (16,-1.93), (100,+0.15) |
| `vfma` | hw-nocache | 2.98 | 21.3 | 1.93 | (8,-0.12), (9,+1.90), (16,-1.93), (100,+0.15) |
| `vfms` | hw-nocache | 2.98 | 21.3 | 1.93 | (8,-0.12), (9,+1.90), (16,-1.93), (100,+0.15) |
| `vfnma` | hw-nocache | 2.98 | 21.3 | 1.93 | (8,-0.12), (9,+1.90), (16,-1.93), (100,+0.15) |
| `vfnms` | hw-nocache | 2.98 | 21.3 | 1.93 | (8,-0.12), (9,+1.90), (16,-1.93), (100,+0.15) |
| `udiv_fast` | hw-nocache | 2.98 | 26.3 | 1.93 | (8,-0.12), (9,+1.90), (16,-1.93), (100,+0.15) |
| `vadd` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vsub` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vmul` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vnmul` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vabs` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vneg` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vmov_reg` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vmov_f2c` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vcmp_zero` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vcmpe_zero` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vcvt_f32_s32` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vcvt_f32_u32` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |
| `vcvt_s32_f32` | hw-nocache | 2.49 | 21.0 | 1.63 | (8,-0.88), (9,+1.63), (16,-0.80), (100,+0.05) |

(71 (op, variant) pairs have max|resid| ≥ 0.5; 105 are perfectly linear.)

**Reading the residual sign:** a positive residual at small N means
the model underpredicts there — i.e. the kernel was actually slightly
slower than the linear fit suggests, usually because the first cache
line is colder than steady state. Negative residual at small N means
the model overpredicts — usually because the framing intercept absorbs
the small-N edge cases imperfectly.

**Where to put trust:** for gem5 validation, prefer comparing **CPI
extracted from the N=8 → N=100 difference**, which is robust to the
small-N nonlinearities, rather than comparing any single N's raw cycle
count. For absolute cycle reproduction, use N=100 — that's the row
where any small-N residual is washed out by the much larger body cost.

---
## What's NOT covered

Explicit list of gaps so this catalog isn't mistaken for full ISA
coverage:

- **Double-precision FP** (`vadd.f64`, `vmul.f64`, …). The board's
  FPv4-SP-d16 has no DP arithmetic; gem5's decoder rejects DP ops on
  M-profile (m_decoder.cc:1005-1013).
- **VFP loads/stores**: `VLDR`, `VSTR`, `VLDM`, `VSTM`, `VPUSH`,
  `VPOP`. Excluded by design — load/store paths bring D-cache and bus
  effects that aren't ALU.
- **System-register transfers**: `VMSR`, `VMRS`. Different
  decoder/permission paths.
- **VMOV with D-register-pair operands**: `vmov Rt, Rt2, Dm` and
  inverse. Out of scope for now.
- **Other integer ALU paths** the gem5 decoder dispatches but this
  catalog doesn't probe: `CLZ`, `SSAT`/`USAT`, `MLA`, `SMULL`,
  `UMAAL`, `SDIV`/`UDIV` with mixed-sign operand strata, `MOV-to-PC`,
  shifts other than `LSL`-by-register, `RBIT`, `REV`/`REV16`/`REVSH`,
  saturated arithmetic, bit-field ops.
- **Branches and control-flow**: separate decoder path; not in this
  catalog.
- **Other data-dependence patterns**: every kernel here uses one
  specific dep-chain (either "dest also reads — chain on s0/r1" or
  "no inter-iter dep"). A different pattern (fan-out, longer chain,
  parallel sources, etc.) may produce different CPI on the same
  mnemonic. The kernels here measure what each mnemonic does *under
  the chosen pattern*; full characterization of any one mnemonic
  across all patterns is future work.

## Adding a new kernel

See [`../README.md`](../README.md) §"Adding your own kernel" for the
full step-by-step (file location, CMakeLists registration, build/run).
Short template:

```asm
/*
 * bench_<name> — <N> × <mnemonic> via BENCH harness.
 *
 * <one-line rationale: what gem5 decoder path this probes>
 */
#include "harness.h"

    BENCH
        @ optional one-shot register setup
        .rept <N>
        <mnemonic>
        .endr
    END_BENCH
```

Then add `(category, bench_<name>)` to `BENCHMARKS_BY_CATEGORY` in
[`../CMakeLists.txt`](../CMakeLists.txt) and document the new family
in the appropriate section of this README. After running the board
sweep, regenerate the fit tables here (per-(kernel, variant) CPI/OH +
residuals — see `/tmp/gen_kernels_readme.py` for the script that
produced this README).

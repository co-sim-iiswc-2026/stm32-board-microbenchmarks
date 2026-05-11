# FPU-ALU latency calibration microbenches

## Purpose

The existing `bench-fpu` (mixed VADD + VMUL + VDIV in one kernel)
shows the SignalCPU model is off by −19 % (no-ART) to −31 % (ART)
vs silicon.  Root cause: SignalCPU has no per-FP-op latency
modeling — every FP inst takes the legacy 1-cy direct-execute path
because [`AluFunctionUnit::accepts()`](../../../../gem5/src/cpu/signal-3-stage-in-order-cpu/alu_fu.cc#L48)
rejects `isFloating()`.

This set isolates **one FP-ALU instruction per kernel** so the
silicon-vs-gem5 gap can be attributed per inst.  The output drives
a follow-up `FpuFunctionUnit` modeling plan tracked in
[`issues/2026-05-11-fpu-calibration/`](../../../../issues/2026-05-11-fpu-calibration/README.md).

Scope: **FP-ALU only**.  Memory FPU ops (VLDR / VSTR / VLDM / VSTM /
VPUSH / VPOP) are excluded — those hit the LSQ / flash subsystem
and are tracked separately.

## Benches

Built into the `microbench-fpu-calibration-all` cmake target.  Every
kernel uses the `KERNEL_INLINE` + `.balign 16` + setup-then-`.rept`
pattern from [`kernels_inline.h`](../kernels_inline.h), so the
per-iteration cost measured by the harness is exactly the target FPU
instruction.

| Bench | Inst tested | Operands | TRM (Cortex-M4) |
|---|---|---|---|
| `bench-fpu-cal-baseline`        | (none)                | s0=1.0, s1=2.0          | n/a |
| `bench-fpu-cal-vadd`            | `vadd.f32 s2, s0, s1` | s0=1.0, s1=2.0          | 1 |
| `bench-fpu-cal-vsub`            | `vsub.f32 s2, s0, s1` | s0=2.0, s1=1.0          | 1 |
| `bench-fpu-cal-vmul`            | `vmul.f32 s2, s0, s1` | s0=1.0, s1=2.0          | 1 |
| `bench-fpu-cal-vnmul`           | `vnmul.f32 s2, s0, s1`| s0=1.0, s1=2.0          | 1 |
| `bench-fpu-cal-vdiv`            | `vdiv.f32 s2, s0, s1` | s0=8.0, s1=2.0 → 4.0    | 14 |
| `bench-fpu-cal-vmla`            | `vmla.f32 s2, s0, s1` | s0=1.0, s1=2.0, s2=0.5  | 1 (non-fused) |
| `bench-fpu-cal-vmls`            | `vmls.f32 s2, s0, s1` | same                    | 1 (non-fused) |
| `bench-fpu-cal-vfma`            | `vfma.f32 s2, s0, s1` | same                    | 3 (fused) |
| `bench-fpu-cal-vfms`            | `vfms.f32 s2, s0, s1` | same                    | 3 (fused) |
| `bench-fpu-cal-vneg`            | `vneg.f32 s1, s0`     | s0=-1.5                 | 1 |
| `bench-fpu-cal-vabs`            | `vabs.f32 s1, s0`     | s0=-1.5                 | 1 |
| `bench-fpu-cal-vsqrt`           | `vsqrt.f32 s1, s0`    | s0=4.0 → 2.0            | 14 |
| `bench-fpu-cal-vmov-imm`        | `vmov.f32 s0, #1.0`   | (immediate)             | 1 |
| `bench-fpu-cal-vmov-reg`        | `vmov.f32 s1, s0`     | s0=1.0                  | 1 |
| `bench-fpu-cal-vmov-core-to-s`  | `vmov s0, r0`         | r0=42                   | 1 |
| `bench-fpu-cal-vmov-s-to-core`  | `vmov r0, s0`         | s0=1.0                  | 1 |
| `bench-fpu-cal-vcmp`            | `vcmp.f32 s0, s1`     | s0=1.0, s1=2.0          | 1 |
| `bench-fpu-cal-vcmpe`           | `vcmpe.f32 s0, s1`    | same                    | 1 |
| `bench-fpu-cal-vcvt-f32-s32`    | `vcvt.f32.s32 s1, s0` | int 42 in s0            | 1+ |
| `bench-fpu-cal-vcvt-s32-f32`    | `vcvt.s32.f32 s1, s0` | f32 16.0 in s0          | 1+ |
| `bench-fpu-cal-vmrs`            | `vmrs r0, fpscr`      | (no operand)            | 1 or 2 |
| `bench-fpu-cal-vmsr`            | `vmsr fpscr, r0`      | r0=0 (clean FPSCR)      | 1 or 2 |

`baseline` has zero FPU ops in the kernel body — measures pure
per-call glue cost.  Subtract it from every other bench to isolate
the per-inst cost.

## Operand-setup rationale

Each kernel pre-loads operands **outside** the `.rept` block so the
per-iteration cycle count is dominated by the target instruction,
not setup.  Operands are chosen so the inst produces a normal-range
result over 100 iterations:

- Arithmetic (VADD / VSUB / VMUL / VNMUL): `s0=1.0, s1=2.0` —
  encodable in VMOV.F32 immediate.
- VDIV: `s0=8.0, s1=2.0` — quotient = 4.0 stays normal (no
  denormalization across iterations).
- VSQRT: `s0=4.0` — result = 2.0 stays normal.
- VABS / VNEG: `s0=-1.5` — normal, non-zero, non-NaN.
- VMLA / VMLS / VFMA / VFMS: `s0=1.0, s1=2.0, s2=0.5` — accumulator
  grows mathematically but stays representable.
- VCVT int→float: `r0=42` → `vmov s0, r0` (s0 holds the *int bit
  pattern*, not 42.0); then `vcvt.f32.s32` interprets s0 as s32.
- VCVT float→int: `s0=16.0` — exact integer-valued float, no
  rounding ambiguity.
- VMRS: no operand.  VMSR: `r0=0` so FPSCR stays at default state
  (no exceptions, no flush-to-zero, round-to-nearest).
- VCMP / VCMPE: `s0=1.0, s1=2.0` — clean compare, FPSCR.NZCV updated
  identically each iter.

## Build target

```
cmake --build "$GEM5_FIRMWARE_DIR"   --target microbench-fpu-calibration-all -j5
cmake --build "$STM32_BUILD_NONE_DIR" --target microbench-fpu-calibration-all -j5
```

Builds all 23 ELFs (1 baseline + 22 per-inst) for both gem5 and
STM32 toolchains. Each `.elf` lands in `<build-dir>/bin/<bench-name>.elf`.

## Usage in the experiment

See
[`experiments/gem5-fpu-calibration/`](../../../../experiments/gem5-fpu-calibration/README.md)
for the gem5-vs-board sweep + per-inst gap analysis.

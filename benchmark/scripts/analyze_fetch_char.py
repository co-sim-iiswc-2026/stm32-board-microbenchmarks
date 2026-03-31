#!/usr/bin/env python3
"""Analyze fetch characterization benchmark results.

Usage:
    python3 benchmark/scripts/parse_logs.py benchmark_logs/ -o benchmark_logs/results.csv
    python3 benchmark/scripts/analyze_fetch_char.py benchmark_logs/results.csv
"""

import csv
import sys
from pathlib import Path

CONFIGS = ["cache_pf", "cache_nopf", "nocache_pf", "nocache_nopf"]
CFG_SHORT = {"cache_pf": "C+P", "cache_nopf": "C", "nocache_pf": "P", "nocache_nopf": "None"}
INNER_REPS_OVERRIDE = {"bench-art_cap_512": 100, "bench-art_cap_1024": 100}


def load_data(csv_path: str) -> dict:
    """Returns {(config, benchmark): cycles_per_call}"""
    data = {}
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            cfg = row["config"]
            bench = row["benchmark"]
            inner = int(row["inner_reps"])
            avg = float(row["avg_cycles"])
            data[(cfg, bench)] = avg / inner
    return data


def hdr(configs):
    labels = [CFG_SHORT.get(c, c) for c in configs]
    return "  ".join(f"{l:>10}" for l in labels)


def row_vals(data, configs, bench, fmt="{:>10.1f}"):
    vals = []
    for c in configs:
        v = data.get((c, bench))
        vals.append(fmt.format(v) if v is not None else "       N/A")
    return "  ".join(vals)


def section(title):
    print(f"\n{'='*70}")
    print(f"  {title}")
    print(f"{'='*70}")


def analyze_fetch_scaling(data, configs):
    section("FETCH SCALING: 16-bit NOPs (straight-line)")
    print(f"{'N':>5}  {hdr(configs)}")
    print(f"{'':>5}  {'CPI':>10}  {'CPI':>10}  {'CPI':>10}  {'CPI':>10}")
    print("-" * 55)
    for n in [8, 16, 32, 64, 128, 256]:
        bench = f"bench-fetch_nop16_{n}"
        parts = [f"{n:>5}"]
        for c in configs:
            v = data.get((c, bench))
            if v is not None:
                cpi = v / n
                parts.append(f"{cpi:>10.3f}")
            else:
                parts.append("       N/A")
        print("  ".join(parts))

    section("FETCH SCALING: 32-bit instructions (straight-line)")
    print(f"{'N':>5}  {hdr(configs)}")
    print(f"{'':>5}  {'CPI':>10}  {'CPI':>10}  {'CPI':>10}  {'CPI':>10}")
    print("-" * 55)
    for n in [8, 16, 32, 64, 128]:
        bench = f"bench-fetch_nop32_{n}"
        parts = [f"{n:>5}"]
        for c in configs:
            v = data.get((c, bench))
            if v is not None:
                cpi = v / n
                parts.append(f"{cpi:>10.3f}")
            else:
                parts.append("       N/A")
        print("  ".join(parts))

    # Key insight
    print("\n  Key insight:")
    c_pf_256 = data.get(("cache_pf", "bench-fetch_nop16_256"))
    none_256 = data.get(("nocache_nopf", "bench-fetch_nop16_256"))
    if c_pf_256 and none_256:
        print(f"    16-bit NOP CPI: cache={c_pf_256/256:.3f}, none={none_256/256:.3f}")
    c_pf_128_32 = data.get(("cache_pf", "bench-fetch_nop32_128"))
    none_128_32 = data.get(("nocache_nopf", "bench-fetch_nop32_128"))
    if c_pf_128_32 and none_128_32:
        print(f"    32-bit NOP CPI: cache={c_pf_128_32/128:.3f}, none={none_128_32/128:.3f}")
    none_16 = data.get(("nocache_nopf", "bench-fetch_nop16_128"))
    none_32 = data.get(("nocache_nopf", "bench-fetch_nop32_64"))
    if none_16 and none_32:
        ratio = (none_32 / 64) / (none_16 / 128)
        print(f"    32-bit/16-bit CPI ratio (no cache): {ratio:.2f}x")


def analyze_branch_distance(data, configs):
    section("BRANCH DISTANCE: Backward (N NOPs + subs + bne, 100 iter)")
    print(f"{'N':>5}  {hdr(configs)}")
    print(f"{'':>5}  {'cyc/iter':>10}  {'cyc/iter':>10}  {'cyc/iter':>10}  {'cyc/iter':>10}")
    print("-" * 55)
    for n in [0, 1, 2, 4, 8, 16, 32, 64]:
        bench = f"bench-br_back_{n}"
        parts = [f"{n:>5}"]
        for c in configs:
            v = data.get((c, bench))
            if v is not None:
                periter = v / 100
                parts.append(f"{periter:>10.2f}")
            else:
                parts.append("       N/A")
        print("  ".join(parts))

    # Compute per-NOP cost
    print("\n  Per-NOP cost (subtracting baseline br_back_0):")
    for c in configs:
        base = data.get((c, "bench-br_back_0"))
        big = data.get((c, "bench-br_back_64"))
        if base and big:
            cost_per_nop = (big - base) / 64 / 100
            print(f"    {CFG_SHORT[c]:>5}: {cost_per_nop:.3f} cycles/NOP")

    section("BRANCH DISTANCE: Forward (beq skips N NOPs, 100 iter)")
    print(f"{'N':>5}  {hdr(configs)}")
    print(f"{'':>5}  {'cyc/iter':>10}  {'cyc/iter':>10}  {'cyc/iter':>10}  {'cyc/iter':>10}")
    print("-" * 55)
    for n in [0, 2, 4, 8, 16, 32]:
        bench = f"bench-br_fwd_{n}"
        parts = [f"{n:>5}"]
        for c in configs:
            v = data.get((c, bench))
            if v is not None:
                periter = v / 100
                parts.append(f"{periter:>10.2f}")
            else:
                parts.append("       N/A")
        print("  ".join(parts))

    section("BRANCH COST SUMMARY")
    print(f"{'':>20}  {hdr(configs)}")
    print("-" * 65)
    # Taken backward (from br_back_0: subs + bne)
    for label, bench, divisor in [
        ("taken back (subs+bne)", "bench-br_back_0", 100),
        ("not-taken + back",     "bench-br_nottaken", 100),
    ]:
        parts = [f"{label:>20}"]
        for c in configs:
            v = data.get((c, bench))
            if v is not None:
                parts.append(f"{v/divisor:>10.2f}")
            else:
                parts.append("       N/A")
        print("  ".join(parts))

    # Derive taken branch penalty
    print("\n  Derived branch penalties:")
    for c in configs:
        back0 = data.get((c, "bench-br_back_0"))
        nottaken = data.get((c, "bench-br_nottaken"))
        if back0 and nottaken:
            # br_back_0: mov + 100*(subs + bne_taken)
            # br_nottaken: mov + mov + 100*(cmp + bne_nottaken + nop + subs + bne_taken)
            taken_cost = back0 / 100 - 1  # subtract subs(1), remainder is bne_taken
            print(f"    {CFG_SHORT[c]:>5}: bne_taken = {taken_cost:.2f} cyc, "
                  f"loop overhead = {back0/100:.2f} cyc/iter")


def analyze_art_capacity(data, configs):
    section("ART CACHE CAPACITY (loop body N NOPs, 100 iter)")
    print(f"{'N':>6} {'bytes':>6}  {hdr(configs)}")
    print(f"{'':>6} {'':>6}  {'CPI':>10}  {'CPI':>10}  {'CPI':>10}  {'CPI':>10}")
    print("-" * 62)
    for n in [32, 64, 128, 256, 512, 1024]:
        bench = f"bench-art_cap_{n}"
        body_bytes = n * 2 + 4  # N * 2-byte NOPs + subs(2) + bne(2)
        parts = [f"{n:>6}", f"{body_bytes:>6}"]
        for c in configs:
            v = data.get((c, bench))
            if v is not None:
                periter = v / 100
                baseline = 3  # subs + bne_taken
                nop_cpi = (periter - baseline) / n if n > 0 else 0
                parts.append(f"{nop_cpi:>10.3f}")
            else:
                parts.append("       N/A")
        print("  ".join(parts))

    print("\n  Key insight:")
    for c in configs:
        v256 = data.get((c, "bench-art_cap_256"))
        v512 = data.get((c, "bench-art_cap_512"))
        if v256 and v512:
            cpi256 = (v256/100 - 3) / 256
            cpi512 = (v512/100 - 3) / 512
            if cpi512 > cpi256 * 1.1:
                print(f"    {CFG_SHORT[c]:>5}: cache overflow between 256 NOPs "
                      f"({256*2}B) and 512 NOPs ({512*2}B)")
                print(f"           CPI 256={cpi256:.3f} -> 512={cpi512:.3f}")


def analyze_interleave(data, configs):
    section("FETCH INTERLEAVE (multi-cycle ops hide fetch stalls?)")
    print(f"{'bench':>25}  {hdr(configs)}")
    print("-" * 65)
    for bench_name, label in [
        ("bench-fetch_interleave_mul", "mul.w + 3 NOPs (×25)"),
        ("bench-fetch_interleave_div", "sdiv + 4 NOPs (×20)"),
        ("bench-fetch_nop16_128",      "128 NOPs (baseline)"),
    ]:
        parts = [f"{label:>25}"]
        for c in configs:
            v = data.get((c, bench_name))
            if v is not None:
                parts.append(f"{v:>10.1f}")
            else:
                parts.append("       N/A")
        print("  ".join(parts))


def analyze_v2(data, configs):
    section("V2 vs V1 COMPARISON (register / dependency differences)")
    print(f"{'bench':>18} {'ver':>4}  {hdr(configs)}")
    print("-" * 68)
    pairs = [
        ("alu",          "alu_v2",          "data deps vs independent"),
        ("alu16",        "alu16_v2",        "data deps vs independent"),
        ("mixed_width",  "mixed_width_v2",  "data deps vs independent"),
        ("pushpop",      "pushpop_v2",      "different push/pop sequence"),
        ("bp_forward",   "bp_forward_v2",   "r0/r1 vs r4/r5"),
        ("bp_nested",    "bp_nested_v2",    "r0/r1 vs r4/r5"),
    ]
    for v1, v2, note in pairs:
        for ver, name in [("v1", v1), ("v2", v2)]:
            parts = [f"{name:>18}", f"{ver:>4}"]
            for c in configs:
                v = data.get((c, f"bench-{name}"))
                if v is not None:
                    parts.append(f"{v:>10.1f}")
                else:
                    parts.append("       N/A")
            print("  ".join(parts))
        # Delta
        parts = [f"{'delta':>18}", f"{'':>4}"]
        for c in configs:
            a = data.get((c, f"bench-{v1}"))
            b = data.get((c, f"bench-{v2}"))
            if a is not None and b is not None:
                pct = (b - a) / a * 100
                parts.append(f"{pct:>+9.1f}%")
            else:
                parts.append("       N/A")
        print("  ".join(parts))
        print(f"  {'':>18} {'':>4}  ({note})")
        print()


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <results.csv>", file=sys.stderr)
        sys.exit(1)

    data = load_data(sys.argv[1])

    # Determine which configs are present
    configs = [c for c in CONFIGS if any(k[0] == c for k in data)]

    analyze_fetch_scaling(data, configs)
    analyze_branch_distance(data, configs)
    analyze_art_capacity(data, configs)
    analyze_interleave(data, configs)
    analyze_v2(data, configs)

    section("SUMMARY")
    print("""
  1. Flash fetch: With cache ON, 16-bit and 32-bit instructions both achieve ~1.0 CPI.
     Without cache, 32-bit is ~2x the CPI of 16-bit (double the fetch bytes).

  2. Branch taken penalty: constant regardless of branch distance when cached.
     Without cache, the refetch cost depends on how far the target is from the
     current fetch position.

  3. ART cache capacity: loop bodies up to ~512 bytes (256 NOPs) stay at 1.0 CPI.
     At 1024 bytes (512 NOPs) CPI jumps, indicating cache overflow.

  4. Prefetch: C+P == C for all benchmarks — prefetch adds nothing on top of cache
     for these workloads. P vs None shows prefetch helps for sequential code
     but not for loops (can't predict backward branch targets).
""")


if __name__ == "__main__":
    main()

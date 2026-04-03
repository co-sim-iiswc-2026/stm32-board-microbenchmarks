#!/usr/bin/env python3
"""Generate LaTeX tables for ART cache capacity and fetch throughput analysis.

Usage:
    python3 benchmark/scripts/generate_art_tables.py benchmark_logs/results.csv
    python3 benchmark/scripts/generate_art_tables.py benchmark_logs/results.csv -o benchmark_logs/tables_art_cap.tex
"""

from __future__ import annotations
import argparse
import csv
import sys
from pathlib import Path


def load_data(csv_path: str) -> dict:
    data = {}
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            cfg = row["config"]
            bench = row["benchmark"].replace("bench-", "")
            inner = int(row["inner_reps"])
            avg = float(row["avg_cycles"])
            data[(cfg, bench)] = avg / inner
    return data


def cpi(data, cfg, name, n_instr):
    v = data.get((cfg, name))
    if v is None:
        return None
    return (v / 100 - 3) / n_instr


def fcpi(v):
    if v is None:
        return "--"
    return f"{v:.3f}"


# Benchmark definitions: (name, type, n_instructions, bytes_per_instr, total_bytes, instr_per_line)
# instr_per_line is for 128-bit (single bank) lines
BENCHMARKS = [
    ("art_cap_32",      "16-bit",   32, 2.0,   64, 8),
    ("art_cap_64",      "16-bit",   64, 2.0,  128, 8),
    ("art_cap_128",     "16-bit",  128, 2.0,  256, 8),
    ("art_cap_256",     "16-bit",  256, 2.0,  512, 8),
    ("art_cap_512",     "16-bit",  512, 2.0, 1024, 8),
    ("art_cap_1024",    "16-bit", 1024, 2.0, 2048, 8),
    ("art_mix3x1_64",   "3:1",     256, 2.5,  640, 6),
    ("art_mix3x1_128",  "3:1",     512, 2.5, 1280, 6),
    ("art_capmix_32",   "1:1",      64, 3.0,  192, 5),
    ("art_capmix_64",   "1:1",     128, 3.0,  384, 5),
    ("art_capmix_128",  "1:1",     256, 3.0,  768, 5),
    ("art_capmix_256",  "1:1",     512, 3.0, 1536, 5),
    ("art_mix1x3_64",   "1:3",     256, 3.5,  896, 4),
    ("art_mix1x3_128",  "1:3",     512, 3.5, 1792, 4),
    ("art_cap32_64",    "32-bit",   64, 4.0,  256, 4),
    ("art_cap32_128",   "32-bit",  128, 4.0,  512, 4),
    ("art_cap32_256",   "32-bit",  256, 4.0, 1024, 4),
]

# Benchmarks used for the fetch throughput model (large N, pre-overflow)
MODEL_POINTS = [
    (2.0, 8, "art_cap_256",    256, "16-bit"),
    (2.5, 6, "art_mix3x1_64",  256, "3:1 mix"),
    (3.0, 5, "art_capmix_128", 256, "1:1 mix"),
    (3.5, 4, "art_mix1x3_64",  256, "1:3 mix"),
    (4.0, 4, "art_cap32_128",  128, "32-bit"),
]

# Benchmarks for prefetcher threshold analysis (overflow sizes, single bank)
PREFETCH_POINTS = [
    (2.0, 8, "art_cap_1024",    1024, "16-bit"),
    (2.5, 6, "art_mix3x1_128",   512, "3:1 mix"),
    (3.0, 5, "art_capmix_256",   512, "1:1 mix"),
    (3.5, 4, "art_mix1x3_128",   512, "1:3 mix"),
    (4.0, 4, "art_cap32_256",    256, "32-bit"),
]


def generate_table_a(data):
    """ART Cache Capacity and Fetch Throughput — all variants."""
    lines = []
    lines.append("% Table A: ART Cache Capacity and Fetch Throughput")
    lines.append(r"\footnotesize")
    lines.append(r"\begin{tabular}{@{}l r r r r r r r@{}}")
    lines.append(r"  \toprule")
    lines.append(r"  & & & & \multicolumn{2}{c}{Dual Bank CPI} & Single & \\")
    lines.append(r"  \cmidrule(lr){5-6}")
    lines.append(r"  Type & I/line & Instr & Bytes & C+P & None & C+P & Overflow? \\")
    lines.append(r"  \midrule")

    prev_type = None
    for name, typ, n_instr, bpi, total_bytes, ipl in BENCHMARKS:
        if typ != prev_type:
            if prev_type is not None:
                lines.append(r"  \addlinespace[2pt]")
            prev_type = typ

        d_cp = cpi(data, "cache_pf", name, n_instr)
        d_no = cpi(data, "nocache_nopf", name, n_instr)
        s_cp = cpi(data, "cache_pf_singlebank", name, n_instr)
        overflow = r"$\bullet$" if d_cp is not None and d_cp > 1.05 else ""

        lines.append(f"  {typ} & {ipl} & {n_instr} & {total_bytes:,} & "
                     f"{fcpi(d_cp)} & {fcpi(d_no)} & {fcpi(s_cp)} & {overflow} \\\\")

    lines.append(r"  \bottomrule")
    lines.append(r"\end{tabular}")
    return lines


def generate_table_b(data):
    """Flash Fetch Throughput Model Validation."""
    lines = []
    lines.append("% Table B: Flash Fetch Throughput Model Validation")
    lines.append(r"\small")
    lines.append(r"\begin{tabular}{@{}r r r r r r@{}}")
    lines.append(r"  \toprule")
    lines.append(r"  B/I & I/line & Measured & Model & Error & Type \\")
    lines.append(r"  \midrule")

    for bpi, ipl, name, n_instr, typ in MODEL_POINTS:
        measured = cpi(data, "nocache_nopf", name, n_instr)
        predicted = 0.75 * bpi
        err = (measured - predicted) / predicted * 100 if measured else 0
        lines.append(f"  {bpi:.1f} & {ipl} & {fcpi(measured)} & {predicted:.3f} & "
                     f"{err:+.1f}\\% & {typ} \\\\")

    lines.append(r"  \bottomrule")
    lines.append(r"\end{tabular}")
    return lines


def generate_table_c(data):
    """Prefetcher Effectiveness vs Instruction Density."""
    lines = []
    lines.append("% Table C: Prefetcher Effectiveness vs Instruction Density")
    lines.append(r"\small")
    lines.append(r"\begin{tabular}{@{}r r r r l@{}}")
    lines.append(r"  \toprule")
    lines.append(r"  B/I & I/line & Single C+P & Single None & Prefetch hides stall? \\")
    lines.append(r"  \midrule")

    for bpi, ipl, name, n_instr, typ in PREFETCH_POINTS:
        s_cp = cpi(data, "cache_pf_singlebank", name, n_instr)
        s_no = cpi(data, "nocache_nopf_singlebank", name, n_instr)
        if s_no is None:
            s_no = cpi(data, "nocache_nopf", name, n_instr)

        if s_cp is not None and s_cp < 1.01:
            hides = "Yes"
        elif s_cp is not None and s_cp < 1.15:
            hides = "Partial"
        else:
            hides = "No"

        lines.append(f"  {bpi:.1f} & {ipl} & {fcpi(s_cp)} & {fcpi(s_no)} & "
                     f"{hides} ({typ}) \\\\")

    lines.append(r"  \midrule")
    lines.append(r"  \multicolumn{5}{@{}l@{}}{Threshold: instructions per line "
                 r"$\geq$ wait states + 1 = 5} \\")
    lines.append(r"  \bottomrule")
    lines.append(r"\end{tabular}")
    return lines


def main():
    parser = argparse.ArgumentParser(
        description="Generate ART cache capacity LaTeX tables"
    )
    parser.add_argument("csv_file", type=str, help="Input CSV file")
    parser.add_argument("--output", "-o", type=Path, default=None,
                        help="Output .tex file (default: stdout)")
    args = parser.parse_args()

    data = load_data(args.csv_file)

    all_lines = []
    all_lines.extend(generate_table_a(data))
    all_lines.append("")
    all_lines.extend(generate_table_b(data))
    all_lines.append("")
    all_lines.extend(generate_table_c(data))

    tex = "\n".join(all_lines) + "\n"

    if args.output:
        args.output.write_text(tex)
        print(f"Written to {args.output}", file=sys.stderr)
    else:
        print(tex)


if __name__ == "__main__":
    main()

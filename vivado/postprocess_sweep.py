#!/usr/bin/env python3
"""Build a resource and Fmax table from one sweep_results directory.

Each run folder (bf<N>_skip_y<0|1>) is expected to contain metrics.txt,
written by sweep_one.tcl. If metrics.txt is missing, the script falls
back to utilization_impl.rpt and timing_summary.rpt.
"""

import csv
import re
import sys
from pathlib import Path


COLUMNS = [
    "bf",
    "skip_y",
    "lut",
    "ff",
    "lut_mem",
    "bram",
    "dsp",
    "period_ns",
    "wns_ns",
    "whs_ns",
    "fmax_mhz",
    "status",
]


def parse_metrics(path: Path) -> dict:
    data = {}
    for line in path.read_text().splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def used_from_util(text: str, label: str) -> str:
    pattern = rf"^\|\s*{re.escape(label)}\s*\|\s*([0-9,]+)"
    match = re.search(pattern, text, re.M)
    if not match:
        return "NA"
    return match.group(1).replace(",", "")


def parse_reports(run_dir: Path) -> dict:
    data = {"status": "FAIL"}
    util_path = run_dir / "utilization_impl.rpt"
    timing_path = run_dir / "timing_summary.rpt"
    if util_path.is_file():
        util = util_path.read_text(errors="replace")
        data["lut"] = used_from_util(util, "Slice LUTs")
        data["lut_logic"] = used_from_util(util, "LUT as Logic")
        data["lut_mem"] = used_from_util(util, "LUT as Memory")
        data["ff"] = used_from_util(util, "Slice Registers")
        data["bram"] = used_from_util(util, "Block RAM Tile")
        data["dsp"] = used_from_util(util, "DSPs")
    if timing_path.is_file():
        timing = timing_path.read_text(errors="replace")
        slack = re.search(
            r"WNS\(ns\)\s+TNS\(ns\).*?\n\s*-+.*?\n\s*"
            r"([+-]?\d+\.\d+)\s+([+-]?\d+\.\d+)\s+\d+\s+\d+\s+([+-]?\d+\.\d+)",
            timing,
        )
        clock = re.search(
            r"^clk\s+\{[^}]+\}\s+([0-9.]+)\s+([0-9.]+)",
            timing,
            re.M,
        )
        if slack and clock:
            wns = float(slack.group(1))
            period = float(clock.group(1))
            data["wns_ns"] = f"{wns:.3f}"
            data["whs_ns"] = f"{float(slack.group(3)):.3f}"
            data["period_ns"] = f"{period:.3f}"
            data["fmax_mhz"] = f"{1000.0 / (period - wns):.3f}"
            data["status"] = "PASS"
    name = run_dir.name
    match = re.fullmatch(r"bf(\d+)_skip_y([01])", name)
    if match:
        data["bf"] = match.group(1)
        data["skip_y"] = match.group(2)
    return data


def load_run(run_dir: Path) -> dict:
    metrics = run_dir / "metrics.txt"
    if metrics.is_file():
        data = parse_metrics(metrics)
    else:
        data = parse_reports(run_dir)
    row = {key: data.get(key, "NA") for key in COLUMNS}
    return row


def markdown_table(rows: list[dict]) -> str:
    header = (
        "| BF | skip_y | LUT | FF | LUTRAM | BRAM | DSP | "
        "Period (ns) | WNS (ns) | WHS (ns) | Fmax (MHz) | Status |"
    )
    rule = "|" + "---|" * 12
    lines = [header, rule]
    for row in rows:
        lines.append(
            "| {bf} | {skip_y} | {lut} | {ff} | {lut_mem} | {bram} | {dsp} | "
            "{period_ns} | {wns_ns} | {whs_ns} | {fmax_mhz} | {status} |".format(**row)
        )
    note = (
        "\nFmax is `1000 / (period_ns - WNS)`. "
        "It is the post-route estimate against the clock in `clk.xdc` "
        "(part xc7a100tiftg256-1L, out-of-context).\n"
    )
    return "\n".join(lines) + "\n" + note


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} RESULTS_DIR", file=sys.stderr)
        return 2
    results = Path(sys.argv[1])
    if not results.is_dir():
        print(f"results directory not found: {results}", file=sys.stderr)
        return 1

    runs = sorted(
        p for p in results.iterdir()
        if p.is_dir() and re.fullmatch(r"bf\d+_skip_y[01]", p.name)
    )
    rows = [load_run(run) for run in runs]
    rows.sort(key=lambda row: (int(row["bf"]) if row["bf"].isdigit() else 99, row["skip_y"]))

    csv_path = results / "summary.csv"
    with csv_path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    md_path = results / "summary.md"
    table = markdown_table(rows) if rows else "No run folders found.\n"
    md_path.write_text(table)
    print(table, end="")
    print(f"wrote {csv_path}")
    print(f"wrote {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
import sys
import json
import argparse
import math
import matplotlib
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter, ScalarFormatter, NullFormatter

# ---------- Global style ----------

matplotlib.rcParams["font.family"] = "Inter"
matplotlib.rcParams["font.sans-serif"] = ["Inter"]
matplotlib.rcParams["font.weight"] = "normal"
matplotlib.rcParams["axes.titleweight"] = "bold"

BACKGROUND_COLOR = "#2B2B2B"

VENDOR_COLOR = {
    "ClickHouse": "#FDFF88",
    "Redshift":   "#FF9F1C",
    "Databricks": "#2EC4B6",
    "Snowflake":  "#A259FF",
    "BigQuery":   "#3A86FF",
}

# Default ticks (can be overridden)
DEFAULT_XTICKS = [1e9, 1e10, 1e11]   # 1B, 10B, 100B
DEFAULT_YTICKS = None                # let Matplotlib choose unless overridden


# ---------- Helpers ----------

def load_records_from_file(path):
    records = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            records.append(json.loads(line))
    return records


def parse_tick_list(value):
    if not value:
        return None
    return [float(v.strip()) for v in value.split(",") if v.strip()]


def parse_range(s):
    if not s:
        return None
    parts = [p.strip() for p in s.split(",")]
    if len(parts) != 2:
        raise ValueError("Invalid range format, expected 'min,max'")
    return float(parts[0]), float(parts[1])


def select_largest_per_system(records):
    """
    From a list of records (one dataset size), pick the 'largest'
    configuration per system using simple bar_label heuristics.
    Returns dict: system -> record.
    """
    chosen = {}

    for r in records:
        system = r.get("system", "")
        label = (r.get("bar_label") or "").lower()

        if system == "ClickHouse":
            # for now: just pick any ClickHouse row (usually only one)
            chosen[system] = r

        elif system == "Databricks":
            # pick 4X-Large if present
            if "4x-large" in label:
                chosen[system] = r

        elif system == "Snowflake":
            # pick 4X-L
            if "4x-l" in label:
                chosen[system] = r

        elif system == "Redshift":
            if "redshift" in label:
                chosen[system] = r

        elif system == "BigQuery":
            if "bigquery" in label:
                chosen[system] = r

    return chosen


def format_rows(x, pos):
    """Format 1e9 -> '1 B', 1e10 -> '10 B', 1e11 -> '100 B'."""
    if x <= 0:
        return ""
    value = x / 1e9
    if value.is_integer():
        value = int(value)
    return f"{value:g} B"


# ---------- Main ----------

def main():
    parser = argparse.ArgumentParser(
        description="Render scaling chart: how runtime or cost grows with rows."
    )
    parser.add_argument("input_1b", help="NDJSON file for 1 B rows")
    parser.add_argument("input_10b", help="NDJSON file for 10 B rows")
    parser.add_argument("input_100b", help="NDJSON file for 100 B rows")

    parser.add_argument("-o", "--out", help="Output PNG filename.")
    parser.add_argument("--dpi", type=int, default=300)

    parser.add_argument(
        "--metric",
        choices=["runtime", "cost"],
        default="runtime",
        help="Metric to plot on Y-axis: 'runtime' (rt_hot) or 'cost' (cost_hot).",
    )

    parser.add_argument(
        "--marker-size",
        type=float,
        default=9.0,
        help="Marker size (points) for each dataset point (default: 9).",
    )

    parser.add_argument(
        "--xticks",
        type=str,
        help="Comma-separated list of X-axis ticks (e.g. '1e9,1e10,1e11'). Overrides defaults.",
    )
    parser.add_argument(
        "--yticks",
        type=str,
        help="Comma-separated list of Y-axis ticks. Overrides defaults.",
    )
    parser.add_argument(
        "--xlim",
        type=str,
        help='Override X-axis limits as "min,max" (e.g. "5e8,2e11").',
    )
    parser.add_argument(
        "--ylim",
        type=str,
        help='Override Y-axis limits as "min,max".',
    )
    parser.add_argument(
        "--no-title",
        action="store_true",
        help="Disable rendering of the chart title.",
    )

    args = parser.parse_args()

    # ---------- Load + select records ----------

    rec_1b = select_largest_per_system(load_records_from_file(args.input_1b))
    rec_10b = select_largest_per_system(load_records_from_file(args.input_10b))
    rec_100b = select_largest_per_system(load_records_from_file(args.input_100b))

    # union of systems present
    systems = sorted(set(rec_1b.keys()) | set(rec_10b.keys()) | set(rec_100b.keys()))
    if not systems:
        print("No systems found to plot.", file=sys.stderr)
        sys.exit(1)

    # dataset sizes (fixed positions on X-axis)
    row_positions = [1e9, 1e10, 1e11]
    datasets = [
        ("1B", rec_1b, row_positions[0]),
        ("10B", rec_10b, row_positions[1]),
        ("100B", rec_100b, row_positions[2]),
    ]

    # ---------- Figure setup ----------

    fig, ax = plt.subplots(figsize=(8, 6))
    fig.patch.set_facecolor(BACKGROUND_COLOR)
    ax.set_facecolor(BACKGROUND_COLOR)

    # ---------- Plot lines ----------

    for system in systems:
        color = VENDOR_COLOR.get(system, "#FFFFFF")

        xs = []
        ys = []

        for ds_name, rec_map, x_pos in datasets:
            rec = rec_map.get(system)
            if not rec:
                continue
            xs.append(x_pos)
            if args.metric == "runtime":
                ys.append(float(rec["rt_hot"]))
            else:
                ys.append(float(rec["cost_hot"]))

        if not xs:
            continue

        # plot line with markers
        ax.plot(
            xs,
            ys,
            marker="o",
            markersize=args.marker_size,
            linewidth=2.0,
            color=color,
            label=system,
        )

    # ---------- Axes setup ----------

    ax.set_xscale("log")
#     ax.set_yscale("log")
    ax.set_yscale("linear")

    # Linear axes
#     ax.set_xscale("linear")
#     ax.set_yscale("linear")

    # Limits
    if args.xlim:
        xmin, xmax = parse_range(args.xlim)
        ax.set_xlim(xmin, xmax)
    else:
        # auto: a bit of padding around 1B..100B
        ax.set_xlim(row_positions[0] / 1.5, row_positions[-1] * 1.5)

    if args.ylim:
        ymin, ymax = parse_range(args.ylim)
        ax.set_ylim(ymin, ymax)

    # Ticks
    xticks = parse_tick_list(args.xticks) or DEFAULT_XTICKS
    yticks = parse_tick_list(args.yticks) or DEFAULT_YTICKS

    if xticks:
        ax.set_xticks(xticks)
    if yticks:
        ax.set_yticks(yticks)

    # Format X as "1 B", "10 B", ...
    ax.xaxis.set_major_formatter(FuncFormatter(format_rows))

    # Y-axis formatting
    if args.metric == "runtime":
        # seconds, no scientific notation
        yfmt = ScalarFormatter()
        yfmt.set_scientific(False)
        yfmt.set_useOffset(False)
        ax.yaxis.set_major_formatter(yfmt)
    else:
        # cost, also non-scientific
        ax.yaxis.set_major_formatter(FuncFormatter(lambda y, pos: f"{y:g}"))
        ax.yaxis.set_minor_formatter(NullFormatter())
        ax.yaxis.get_offset_text().set_visible(False)

    # Labels and title
    ax.set_xlabel("Rows processed (log scale)", color="white")

    if args.metric == "runtime":
        ax.set_ylabel("Runtime (s; log scale)", color="white")
    else:
        ax.set_ylabel("Total cost (USD; log scale)", color="white")

    if not args.no_title:
        title_metric = "Runtime" if args.metric == "runtime" else "Cost"
        ax.set_title(
            f"Scaling behavior: {title_metric} vs rows\n(ClickBench, 1 B / 10 B / 100 B rows)",
            color="white",
            pad=15,
        )

    ax.tick_params(colors="white")

    for spine in ("left", "bottom"):
        ax.spines[spine].set_visible(True)
        ax.spines[spine].set_color("white")
    for spine in ("right", "top"):
        ax.spines[spine].set_visible(False)

    ax.grid(False)

    # Legend
    legend = ax.legend(
        facecolor=BACKGROUND_COLOR,
        edgecolor="white",
        framealpha=0.9,
        fontsize=10,
    )
    for text in legend.get_texts():
        text.set_color("white")

    plt.tight_layout()

    if args.out:
        plt.savefig(
            args.out,
            dpi=args.dpi,
            facecolor=fig.get_facecolor(),
        )
    else:
        plt.show()


if __name__ == "__main__":
    main()
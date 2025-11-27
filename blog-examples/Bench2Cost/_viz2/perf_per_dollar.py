#!/usr/bin/env python3
import sys
import json
import argparse
import math
import matplotlib
import matplotlib.pyplot as plt


# Global font config
matplotlib.rcParams['font.family'] = 'Inter'
matplotlib.rcParams['font.sans-serif'] = ['Inter']
matplotlib.rcParams['font.weight'] = 'normal'
matplotlib.rcParams['axes.titleweight'] = 'bold'

# ---------- Configuration ----------

VENDOR_COLOR = {
    "ClickHouse": "#FDFF88",
    "Redshift":   "#FF9F1C",
    "Databricks": "#2EC4B6",
    "Snowflake":  "#A259FF",
    "BigQuery":   "#3A86FF",   # BigQuery color
}

BACKGROUND_COLOR = "#2B2B2B"
TEXT_COLOR = "white"


# ---------- Helpers ----------

def load_records_from_stdin():
    """Read newline-delimited JSON records from stdin."""
    records = []
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        records.append(json.loads(line))
    return records


def vendor_from_system(system: str) -> str:
    """Map system name to vendor key for colors."""
    return system


# ---------- Main ----------

def main():
    parser = argparse.ArgumentParser(
        description="Render performance-per-dollar bar chart from NDJSON input."
    )
    parser.add_argument(
        "-o", "--out",
        help="Output PNG filename. If omitted, show interactively instead.",
    )
    parser.add_argument(
        "--dpi",
        type=int,
        default=300,
        help="DPI for saved PNG (default: 300).",
    )
    parser.add_argument(
        "--no-title",
        action="store_true",
        help="Disable rendering of the chart title.",
    )
    parser.add_argument(
        "--no-labels",
        action="store_true",
        help="Disable rendering of bar labels on the left.",
    )
    parser.add_argument(
        "--bar-height",
        type=float,
        default=0.55,
        help="Vertical bar height (thickness). Default: 0.55",
    )
    parser.add_argument(
        "--bar-distance",
        type=float,
        default=1.0,
        help="Vertical distance between bar centers. Default: 1.0",
    )
    args = parser.parse_args()

    records = load_records_from_stdin()
    if not records:
        print("No input records read from stdin.", file=sys.stderr)
        sys.exit(1)

    # Compute performance per dollar: 1 / (runtime * cost)
    enriched = []
    for r in records:
        rt = float(r["rt_hot"])
        cost = float(r["cost_hot"])
        perf = 1.0 / (rt * cost)
        enriched.append((r, perf))

    # Normalize to best = 1.0, sort descending
    max_perf = max(p for _, p in enriched)
    rows = []
    for r, perf in enriched:
        norm = perf / max_perf  # 1.0 for best
        rows.append(
            {
                "record": r,
                "perf_raw": perf,
                "perf_norm": norm,
                "percent": norm * 100.0,
            }
        )
    rows.sort(key=lambda x: x["perf_norm"], reverse=True)

    labels = [row["record"].get("bar_label") or row["record"]["system"]
              for row in rows]
    systems = [row["record"]["system"] for row in rows]
    percents = [row["percent"] for row in rows]

    x_vals = [p / 100.0 for p in percents]

#     fig, ax = plt.subplots(figsize=(10, 6))
    fig, ax = plt.subplots(figsize=(8, 6))
    fig.patch.set_facecolor(BACKGROUND_COLOR)
    ax.set_facecolor(BACKGROUND_COLOR)

    # Positions with configurable distance
    bar_height = args.bar_height
    bar_distance = args.bar_distance
    y_positions = [i * bar_distance for i in range(len(rows))]

    # Draw bars
    for y, x, system, row in zip(y_positions, x_vals, systems, rows):
        color = VENDOR_COLOR.get(vendor_from_system(system), "#FFFFFF")
        ax.barh(
            y,
            x,
            color=color,
            edgecolor="none",
            height=bar_height,
        )

    # Best at the top
    ax.invert_yaxis()

    # Labels on the left (or not)
    ax.set_yticks(y_positions)
    if args.no_labels:
        ax.set_yticklabels([])
    else:
        ax.set_yticklabels(labels, color=TEXT_COLOR)

    ax.set_xticks([])
    ax.set_xlim(0, max(x_vals) * 1.05 if x_vals else 1.0)

    if not args.no_title:
        ax.set_title("Performance per dollar", color=TEXT_COLOR, pad=20, fontsize=18)

    # Spines & ticks
    ax.spines["left"].set_visible(True)
    ax.spines["bottom"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["top"].set_visible(False)
    ax.spines["left"].set_color(TEXT_COLOR)

    ax.tick_params(axis="y", colors=TEXT_COLOR)
    ax.tick_params(axis="x", bottom=False, labelbottom=False)

    # Percent + "× worse" labels on the right of each bar
    for y, x, row in zip(y_positions, x_vals, rows):
        percent = row["percent"]
        if math.isclose(row["perf_norm"], 1.0, rel_tol=1e-9):
            text_percent = "100%"
            worse_text = ""
        else:
            text_percent = f"{percent:.1f}%" if percent < 1 else f"{percent:.0f}%"
            factor_worse = 1.0 / row["perf_norm"]
            worse_text = f"   → {int(round(factor_worse))}× worse"

        x_text = x * 1.01
        ax.text(
            x_text,
            y,
            text_percent + worse_text,
            va="center",
            ha="left",
            color=TEXT_COLOR,
            fontsize=12,
        )

    plt.tight_layout()

    if args.out:
        plt.savefig(
            args.out,
            dpi=args.dpi,
#             bbox_inches="tight",
            facecolor=fig.get_facecolor(),
        )
    else:
        plt.show()


if __name__ == "__main__":
    main()
#!/usr/bin/env python3
import sys
import json
import argparse
import matplotlib
import matplotlib.pyplot as plt
from matplotlib.ticker import ScalarFormatter
from matplotlib.ticker import FuncFormatter, NullFormatter
from adjustText import adjust_text

# Global font config
matplotlib.rcParams['font.family'] = 'Inter'
matplotlib.rcParams['font.sans-serif'] = ['Inter']
matplotlib.rcParams['font.weight'] = 'normal'
matplotlib.rcParams['axes.titleweight'] = 'bold'

# ---------- Configuration ----------

# VENDOR_COLOR = {
#     "ClickHouse": "#FDFF88",
#     "Redshift":   "#FF9F1C",
#     "Databricks": "#2EC4B6",
#     "Snowflake":  "#A259FF",
#     "BigQuery":   "#3A86FF",
# }

VENDOR_COLOR = {
    "ClickHouse": "#FDFF88",  # ClickHouse yellow
    "Redshift":   "#FFB30A",  # AWS-ish orange, softened for dark bg
    "Databricks": "#FF4B3A",  # Databricks red, slightly softened
    "Snowflake":  "#29B5E8",  # Snowflake cyan
    "BigQuery":   "#4285F4",  # Google blue
}

XTICKS = [100, 200, 300, 500, 1000, 2000, 3000, 5000, 10000, 20000]
YTICKS = [10, 20, 30, 50, 70, 100, 150, 200]

BACKGROUND_COLOR = "#2B2B2B"


# ---------- Helpers (must be top-level!) ----------

def load_records_from_stdin():
    records = []
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        records.append(json.loads(line))
    return records


def vendor_from_system(system: str) -> str:
    return system


def auto_label(rec: dict) -> str:
    system = rec.get("system", "")
    cluster = str(rec.get("cluster", "")).lower()

    if system in ("Databricks", "Snowflake"):
        if "4x" in cluster:
            size = "4XL"
        elif "large" in cluster or cluster in ("8",):
            size = "L"
        else:
            size = cluster or "?"
        return f"{system}-{size}"
    else:
        return system or "unknown"


def parse_tick_list(value):
    """Convert '100,200,500' → [100, 200, 500]"""
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

# ---------- Main ----------

def main():
    parser = argparse.ArgumentParser(
        description="Render hot runtime vs cost scatter plot from NDJSON input."
    )
    parser.add_argument("-o", "--out", help="Output PNG filename.")
    parser.add_argument("--dpi", type=int, default=300)
    parser.add_argument("--no-title", action="store_true")
    parser.add_argument("--no-labels", action="store_true")
    parser.add_argument(
        "--marker-size",
        type=float,
        default=70,
        help="Base marker size for scatter points (default: 70).",
    )
    parser.add_argument(
        "--xticks",
        type=str,
        help="Comma-separated list of X-axis ticks (e.g. '100,200,500,1000'). Overrides defaults."
    )
    parser.add_argument(
        "--yticks",
        type=str,
        help="Comma-separated list of Y-axis ticks. Overrides defaults."
    )
    parser.add_argument(
        "--xlim",
        type=str,
        help='Override X-axis limits as "min,max" (e.g. "10,1200").'
    )
    args = parser.parse_args()

    records = load_records_from_stdin()
    if not records:
        print("No input records from stdin.", file=sys.stderr)
        sys.exit(1)

    runtimes = [float(r["rt_hot"]) for r in records]
    costs    = [float(r["cost_hot"]) for r in records]
    labels   = [
        r["bar_label"] if "bar_label" in r and r["bar_label"] else auto_label(r)
        for r in records
    ]
    vendors  = [vendor_from_system(r["system"]) for r in records]

    fig, ax = plt.subplots(figsize=(8, 6))
    fig.patch.set_facecolor(BACKGROUND_COLOR)
    ax.set_facecolor(BACKGROUND_COLOR)

    texts = []
    for x, y, label, vendor in zip(runtimes, costs, labels, vendors):
        color = VENDOR_COLOR.get(vendor, "#FFFFFF")
        base = args.marker_size
        size = base * (1.3 if ("4X" in label or "4XL" in label) else 1.0)

        ax.scatter(
            x, y,
            s=size,
            marker="o",
            color=color,
            edgecolors="black",
            linewidths=0.8,
            zorder=3,
        )

        if not args.no_labels:
            # custom initial offset per system to avoid collisions
#             if "BigQuery" in label:
#                 x_text = x * 1.00
#                 y_text = y * 0.92   # slightly below and to the right
#             elif "Redshift" in label:
#                 x_text = x * 1.00
#                 y_text = y * 1.05   # slightly above
#             else:
#                 x_text = x * 1.03
#                 y_text = y * 1.03

            x_text = x * 1.03
            y_text = y * 1.03
            text = ax.text(
                x_text,
                y_text,
                label,
                fontsize=10,
                color="white",
                ha="left",
                va="bottom",
            )
            texts.append(text)

    # Log scales first
    ax.set_xscale("log")
    ax.set_yscale("log")


    # Apply manual x-limits if provided
    if args.xlim:
        xmin, xmax = parse_range(args.xlim)
        ax.set_xlim(xmin, xmax)

    # Now adjust text (prevents weird jumps)
    if not args.no_labels and texts:
        adjust_text(
            texts,
            arrowprops=None,
            expand_points=(1.2, 1.4),
            expand_text=(1.1, 1.2),
            force_points=0.4,
            force_text=0.5,
        )

    # Determine ticks: CLI overrides hardcoded defaults
    xticks = parse_tick_list(args.xticks) or XTICKS
    yticks = parse_tick_list(args.yticks) or YTICKS

    ax.set_xticks(xticks)
    ax.set_yticks(yticks)

    # X: keep ScalarFormatter if you like it
    xfmt = ScalarFormatter()
    xfmt.set_scientific(False)
    xfmt.set_useOffset(False)
    ax.xaxis.set_major_formatter(xfmt)

    # Y: custom formatter to avoid scientific notation
    ax.yaxis.set_major_formatter(
        FuncFormatter(lambda y, pos: f"{y:g}")  # prints 4, 5, 8, 10, 15, 20
    )
    ax.yaxis.set_minor_formatter(NullFormatter())
    ax.yaxis.get_offset_text().set_visible(False)

    ax.set_xlabel("Total runtime (s; log scale)\n↓ lower is better", color="white")
    ax.set_ylabel("Total cost (USD; log scale)\n↓ lower is better", color="white")

    if not args.no_title:
        ax.set_title("Hot Runtime vs Cost (log-log)", color="white", pad=15)

    ax.tick_params(colors="white")

    ax.spines["left"].set_visible(True)
    ax.spines["bottom"].set_visible(True)
    ax.spines["left"].set_color("white")
    ax.spines["bottom"].set_color("white")
    ax.spines["right"].set_visible(False)
    ax.spines["top"].set_visible(False)

    ax.grid(False)

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
#!/usr/bin/env python3
import sys
import json
import argparse
import math
import matplotlib
import matplotlib.pyplot as plt

# Font config
matplotlib.rcParams['font.family'] = 'Inter'
matplotlib.rcParams['font.sans-serif'] = ['Inter']
matplotlib.rcParams['font.weight'] = 'normal'
matplotlib.rcParams['axes.titleweight'] = 'bold'

# ---------- Colors ----------
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

BACKGROUND_COLOR = "#2B2B2B"
TEXT_COLOR = "white"
FORMULA_COLOR = "#6C6C6C"     # Light gray formula annotation

# ---------- Helpers ----------
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

# ---------- Main ----------
def main():
    parser = argparse.ArgumentParser(
        description="Render cost-performance index bar chart from NDJSON input."
    )
    parser.add_argument("-o", "--out", help="Output PNG filename.")
    parser.add_argument("--dpi", type=int, default=300)
    parser.add_argument("--no-title", action="store_true")
    parser.add_argument("--no-labels", action="store_true")
    parser.add_argument("--bar-height", type=float, default=0.55)
    parser.add_argument("--bar-distance", type=float, default=1.0)
    args = parser.parse_args()

    records = load_records_from_stdin()
    if not records:
        print("No input records!", file=sys.stderr)
        sys.exit(1)

    # ---- New metric: index = runtime * cost (lower is better) ----
    enriched = []
    for r in records:
        rt = float(r["rt_hot"])
        cost = float(r["cost_hot"])
        index = rt * cost
        enriched.append((r, index))

    best_index = min(idx for _, idx in enriched)

    rows = []
    for r, idx in enriched:
        factor = idx / best_index
        rows.append({
            "record": r,
            "index_raw": idx,
            "index_factor": factor,
        })

    # Sort ascending: best first
    rows.sort(key=lambda x: x["index_factor"])

    # Build ranking labels
    base_labels = [
        row["record"].get("bar_label") or row["record"]["system"]
        for row in rows
    ]
    labels = []
    for rank, base_label in enumerate(base_labels, start=1):
        suffix = "th"
        if rank == 1:
            suffix = "st"
        elif rank == 2:
            suffix = "nd"
        elif rank == 3:
            suffix = "rd"
        labels.append(f"{rank}{suffix} • {base_label}")

    systems = [row["record"]["system"] for row in rows]
    factors = [row["index_factor"] for row in rows]
    x_vals = factors

    fig, ax = plt.subplots(figsize=(8, 6))
    fig.patch.set_facecolor(BACKGROUND_COLOR)
    ax.set_facecolor(BACKGROUND_COLOR)

    bar_height = args.bar_height
    bar_distance = args.bar_distance
    y_positions = [i * bar_distance for i in range(len(rows))]

    # Draw bars
    for y, x, system in zip(y_positions, x_vals, systems):
        color = VENDOR_COLOR.get(system, "#FFFFFF")
        ax.barh(y, x, color=color, height=bar_height, edgecolor="none")

    ax.invert_yaxis()

    # Y labels
    ax.set_yticks(y_positions)
    if args.no_labels:
        ax.set_yticklabels([])
    else:
        ax.set_yticklabels(labels, color=TEXT_COLOR)

    # X axis — no ticks or values
    ax.set_xlim(0, max(x_vals) * 1.05)
    ax.set_xlabel("Cost × runtime (smaller is better)", color=TEXT_COLOR, labelpad=15)
    ax.set_xticks([])
    ax.tick_params(axis="x", bottom=False, labelbottom=False)
    ax.spines["bottom"].set_visible(False)

    # Title
    if not args.no_title:
        ax.set_title("Price-performance leaderboard", color=TEXT_COLOR, pad=20, fontsize=18)

    # Style spines
    ax.spines["left"].set_visible(True)
    ax.spines["left"].set_color(TEXT_COLOR)
    for side in ["right", "top"]:
        ax.spines[side].set_visible(False)

    ax.tick_params(axis="y", colors=TEXT_COLOR)
    ax.tick_params(axis="y", pad=10)

    # Right-hand "baseline / Nx worse"
    for y, factor in zip(y_positions, x_vals):
        if math.isclose(factor, 1.0, rel_tol=1e-9):
            txt = "best"
        else:
            txt = f"{int(round(factor))}× worse"
        ax.text(factor * 1.01, y, txt, va="center", ha="left", color=TEXT_COLOR, fontsize=12)

    # ---- Formula annotation BELOW each bar ----
    for y, row in zip(y_positions, rows):
        r = row["record"]
        rt = float(r["rt_hot"])
        cost = float(r["cost_hot"])
        idx = row["index_raw"]

        formula = f"${cost:,.1f} × {int(rt)}s = {idx:,.0f}"

        y_formula = y + (bar_height * 0.8)   # Move slightly below bar
        x_formula = max(x_vals) * 0.01        # Slight indent from left

        ax.text(
            x_formula,
            y_formula,
            formula,
            va="center",
            ha="left",
            color=FORMULA_COLOR,
            fontsize=10,
        )

    plt.tight_layout()

    if args.out:
        plt.savefig(args.out, dpi=args.dpi, facecolor=fig.get_facecolor())
    else:
        plt.show()


if __name__ == "__main__":
    main()
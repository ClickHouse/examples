#!/usr/bin/env python3
import sys
import json
import argparse
import matplotlib
import matplotlib.pyplot as plt

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

# ---------- Helpers ----------

def load_records_from_stdin():
    records = []
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        records.append(json.loads(line))
    return records


def select_one_per_system(records):
    """
    For each system, pick a single representative record for storage cost.

    Rules:
    - Skip rows where compute_model == "on_demand" (e.g. BigQuery On-demand).
    - For each system, keep the first non-on_demand record encountered.
      (In your data, storage size/cost is the same across service sizes,
       so choice of service size doesn't matter.)
    """
    chosen = {}
    for r in records:
        system = r.get("system", "")
        if not system:
            continue

        compute_model = (r.get("compute_model") or "").lower()
        if compute_model == "on_demand":
            continue  # skip on-demand pricing rows

        if system not in chosen:
            chosen[system] = r

    return chosen


# ---------- Main ----------

def main():
    parser = argparse.ArgumentParser(
        description="Render storage cost bar chart from NDJSON input."
    )
    parser.add_argument(
        "-o", "--out",
        help="Output PNG filename. If omitted, show interactively."
    )
    parser.add_argument(
        "--dpi",
        type=int,
        default=300,
        help="DPI for saved PNG (default: 300)."
    )
    parser.add_argument(
        "--no-title",
        action="store_true",
        help="Disable chart title."
    )
    parser.add_argument(
        "--logy",
        action="store_true",
        help="Use logarithmic scale on the Y axis."
    )
    parser.add_argument(
        "--rows-label",
        type=str,
        default="100 B",
        help="Label for dataset size (e.g. '1 B', '10 B', '100 B').",
    )

    args = parser.parse_args()

    records = load_records_from_stdin()
    if not records:
        print("No input records read from stdin.", file=sys.stderr)
        sys.exit(1)

    per_system = select_one_per_system(records)
    if not per_system:
        print("No eligible systems found (after filtering).", file=sys.stderr)
        sys.exit(1)

    # Build lists and sort by storage cost
    rows = []
    for system, r in per_system.items():
        try:
            cost_data = float(r["cost_data"])
        except (KeyError, ValueError, TypeError):
            continue

        bar_label = r.get("bar_label") or system
        data_sz   = r.get("data_sz", "?")
        rows.append({
            "system": system,
            "bar_label": bar_label,
            "data_sz": data_sz,
            "cost_data": cost_data,
        })

    if not rows:
        print("No rows with valid cost_data.", file=sys.stderr)
        sys.exit(1)

    # Sort cheapest -> most expensive
    rows.sort(key=lambda x: x["cost_data"])

    systems    = [r["system"] for r in rows]
    bar_labels = [r["bar_label"] for r in rows]
    sizes      = [r["data_sz"] for r in rows]
    costs      = [r["cost_data"] for r in rows]

    # ---------- Plot ----------

    fig, ax = plt.subplots(figsize=(8, 6))
    fig.patch.set_facecolor(BACKGROUND_COLOR)
    ax.set_facecolor(BACKGROUND_COLOR)

    x = range(len(rows))
    colors = [VENDOR_COLOR.get(s, "#FFFFFF") for s in systems]

    bars = ax.bar(
        x,
        costs,
        color=colors,
        edgecolor="black",
        linewidth=0.8,
    )

    if args.logy:
        ax.set_yscale("log")

    # X tick labels: system + small data size line
    x_labels = [
        f"{s}\n({sz})"
        for s, sz in zip(systems, sizes)
    ]
    ax.set_xticks(x)
    ax.set_xticklabels(x_labels, rotation=0, ha="center", color="white")

    # Y label and title
    ax.set_ylabel(f"Monthly storage cost (USD)\n{args.rows_label}-row ClickBench dataset", color="white")

    if not args.no_title:
        ax.set_title(f"What does it cost to store {args.rows_label} rows?", color="white", pad=20)

    # Value labels on top of bars
    for rect, cost in zip(bars, costs):
        height = rect.get_height()
        ax.text(
            rect.get_x() + rect.get_width() / 2.0,
            height * (1.05 if not args.logy else 1.1),
            f"${cost:.0f}" if cost >= 10 else f"${cost:.2f}",
            ha="center",
            va="bottom",
            color="white",
            fontsize=10,
        )

    # Ticks & spines
    ax.tick_params(axis="y", colors="white")
    # x tick colors already set above via labels

    for spine in ("left", "bottom"):
        ax.spines[spine].set_visible(True)
        ax.spines[spine].set_color("white")
    for spine in ("right", "top"):
        ax.spines[spine].set_visible(False)

    ax.grid(False)

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
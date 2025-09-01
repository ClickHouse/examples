#!/usr/bin/env python3
import argparse, json, pathlib, re
import matplotlib.pyplot as plt
import numpy as np

plt.rcParams['font.family'] = 'Inter'

# ------------------------------------------------------
# Helpers: compact labels
# ------------------------------------------------------
def compact_rows_total(s: str) -> str:
    s = s.strip().lower()
    s = s.replace(" rows/s", "").replace(" total", "")
    s = re.sub(r"\bmillion\b", "M", s)
    s = re.sub(r"\bbillion\b", "B", s)
    return f"{s} rows/s"

def compact_bytes_total(s: str) -> str:
    return s.strip().replace(" total", "")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("json_path", type=pathlib.Path, help="summary JSON path")
    ap.add_argument("mode", choices=["cold","hot","hot_avg"], help="which timing to plot")
    ap.add_argument("--outdir", type=pathlib.Path, help="Optional output folder")
    ap.add_argument("--max-cores", type=int, default=None,
                    help="only render core counts <= this value (e.g. 64)")
    ap.add_argument(
        "--label-threshold",
        type=float,
        default=2.5,
        help=("Multiple of label text height a bar must exceed to place runtime label inside "
              "(default: 2.5). Lower values keep labels inside more often (e.g. 2.1).")
    )
    grp = ap.add_mutually_exclusive_group()
    grp.add_argument("--always-inside", action="store_true",
                     help="Force runtime labels to always be drawn inside bars.")
    grp.add_argument("--always-outside", action="store_true",
                     help="Force runtime labels to always be drawn above bars.")
    args = ap.parse_args()

    # -----------------------------
    # Load results JSON
    # -----------------------------
    with args.json_path.open("r") as f:
        results = json.load(f)

    node_list  = results.get("node_list", [])
    cores_list = results.get("cores_list", [])

    if len(node_list) != 1:
        raise SystemExit("For a cores chart, JSON must contain exactly one value in node_list.")
    if not cores_list:
        raise SystemExit("cores_list missing or empty in JSON.")
    fixed_nodes = node_list[0]

    if args.max_cores is not None:
        cores_list = [c for c in cores_list if c <= args.max_cores]
        if not cores_list:
            raise SystemExit(f"No cores <= {args.max_cores} found in cores_list.")

    order_cores = cores_list
    keys        = [f"n{fixed_nodes}c{c}" for c in order_cores]

    xticks   = [str(c) for c in order_cores]
    runtimes = [results["result_matrix"][k]["timing"][args.mode] for k in keys]
    stats_key = "cold_stats" if args.mode == "cold" else "hot_stats"

    # Metric boxes (2 groups)
    metric_boxes = []
    for k in keys:
        hs = results["result_matrix"][k][stats_key]
        g1 = [
            compact_rows_total(hs["initiator_rows_per_sec"]),
            compact_bytes_total(hs["initiator_bytes_per_sec"]),
        ]
        g2 = [f'{hs["avg_replica_bytes_read"]["human"]} read']
        metric_boxes.append("\n".join(g1) + "\n\n" + "\n".join(g2))

    # ----------------
    # Style constants
    # ----------------
    BG        = "#2B2B2B"
    BAR_COLOR = "#FDFF89"
    BOX_FACE  = "#393939"
    BOX_EDGE  = "#818181"
    AXIS_GRAY = "#575757"
    GRID_GRAY = "#575757"

    fig, ax = plt.subplots(figsize=(14, 7), facecolor=BG)
    ax.set_facecolor(BG)

    x = np.arange(len(order_cores))
    bars = ax.bar(x, runtimes, width=0.8, color=BAR_COLOR, zorder=2)

    max_rt  = max(runtimes) if len(runtimes) else 1.0
    pad_top = max(1.0, 0.12 * max_rt)
    ax.set_ylim(0, max_rt + pad_top)

    for spine in ax.spines.values():
        spine.set_color(AXIS_GRAY)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.tick_params(axis="both", which="major", labelsize=12, colors="white")
    ax.set_xlabel("Number of CPU cores", color="white", labelpad=14, fontsize=14)
    ax.set_ylabel("Runtime (s)", color="white", labelpad=10, fontsize=14)

    ax.grid(axis="y", color=GRID_GRAY, linestyle="--", alpha=0.35, zorder=0)
    ax.grid(axis="x", visible=False)
    ax.set_xticks(x)
    ax.set_xticklabels(xticks)

    # --- Text height in data units ---
    label_pt = 12
    label_px = (label_pt / 72.0) * fig.dpi
    inv = ax.transData.inverted()
    _, label_h_data = inv.transform((0, label_px)) - inv.transform((0, 0))
    gap_above = max(0.40, 0.5 * label_h_data)

    extra_above = []
    thr = max(1.0, args.label_threshold)

    # Runtime labels
    for bar, rt in zip(bars, runtimes):
        cx, h = bar.get_x() + bar.get_width() / 2, bar.get_height()
        label = f"{rt:.2f}s"

        if args.always_inside:
            ax.text(cx, h / 2, label,
                ha="center", va="center",
                fontsize=label_pt, fontweight="bold",
                color="black", zorder=5)
            extra_above.append(0.0)

        elif args.always_outside:
            ax.text(cx, h + gap_above, label,
                ha="center", va="bottom",
                fontsize=label_pt, fontweight="bold",
                color=BAR_COLOR, zorder=5)  # <-- use bar color
            extra_above.append(gap_above + label_h_data)

        else:
            if h < thr * label_h_data:
                ax.text(cx, h + gap_above, label,
                    ha="center", va="bottom",
                    fontsize=label_pt, fontweight="bold",
                    color=BAR_COLOR, zorder=5)  # <-- use bar color
                extra_above.append(gap_above + label_h_data)
            else:
                ax.text(cx, h / 2, label,
                    ha="center", va="center",
                    fontsize=label_pt, fontweight="bold",
                    color="black", zorder=5)
                extra_above.append(0.0)

    # Metric boxes above bars; lift further if runtime label was outside
    for i, (bar, txt) in enumerate(zip(bars, metric_boxes)):
        x_text = bar.get_x() + bar.get_width() / 2
        offset_points = 12
        offset_pixels = (offset_points / 72.0) * fig.dpi
        _, dy = inv.transform((0, offset_pixels)) - inv.transform((0, 0))
        gap = max(0.40, dy, 0.05 * bar.get_height())
        y_text = bar.get_height() + gap + extra_above[i]

        ax.text(
            x_text, y_text, txt,
            ha="center", va="bottom",
            color="white", fontsize=10,
            linespacing=1.3,
            bbox=dict(
                boxstyle="round,pad=0.35,rounding_size=0.4",
                facecolor=BOX_FACE, edgecolor=BOX_EDGE, linewidth=1.0
            ),
            zorder=4
        )

    plt.tight_layout()
    stem   = args.json_path.stem
    suffix = f"_upto{args.max_cores}" if args.max_cores is not None else ""
    fname  = f"{stem}_cores_{args.mode}{suffix}.png"

    outdir = pathlib.Path(args.outdir) if args.outdir else args.json_path.parent
    outdir.mkdir(parents=True, exist_ok=True)
    out    = outdir / fname

    plt.savefig(out, dpi=200, bbox_inches="tight")
    print(f"saved: {out}")
    plt.show()

if __name__ == "__main__":
    main()
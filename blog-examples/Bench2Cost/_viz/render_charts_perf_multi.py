#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json, argparse
from pathlib import Path
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from matplotlib.ticker import FuncFormatter, MaxNLocator
import matplotlib.transforms as mtransforms


# ---------- THEME ----------
DARK_BG  = "#222425"
DARK_AX  = "#2A2C2D"
FG_TEXT  = "#FFFFFF"
GRID     = "#8E9396"
TITLE    = "#FFFFFF"

COLOR_BY_SYSTEM = {
    "ClickHouse": "#FFF59D",
    "BigQuery":   "#4E79A7",
    "Redshift":   "#E15759",
}

MINOR_YAX = -0.02    # per-bar labels
MAJOR_YAX = -0.145   # scale labels (group names)

def apply_dark_theme():
    plt.rcParams.update({
        "figure.facecolor": DARK_BG,
        "axes.facecolor": DARK_AX,
        "savefig.facecolor": DARK_BG,
        "axes.edgecolor": FG_TEXT,        # not drawn after we hide spines
        "axes.labelcolor": FG_TEXT,
        "xtick.color": FG_TEXT,
        "ytick.color": FG_TEXT,
        "text.color": FG_TEXT,
        "grid.color": GRID,
        "grid.alpha": 0.25,
        "font.size": 12,
        "font.family": "Inter",
    })

def ytick_formatter(val, _pos):
    return f"{val:.0f}×" if val >= 1 else f"{val:.2f}×"

def rel_luminance(hex_color):
    h = hex_color.lstrip('#')
    r, g, b = [int(h[i:i+2], 16)/255.0 for i in (0,2,4)]
    return 0.2126*r + 0.7152*g + 0.0722*b

def color_for(system):
    return COLOR_BY_SYSTEM.get(system, plt.rcParams['axes.prop_cycle'].by_key()['color'][0])

def fmt_money(v): return f"${v:0.2f}"
def fmt_secs(v):  return f"{v:0.2f} s" if v >= 1 else f"{v:0.3f} s"

def add_left_rail(ax, text):
    ax.text(-0.10, 0.5, text, transform=ax.transAxes,
            va='center', ha='center', rotation=90,
            fontsize=56, weight='bold', color=FG_TEXT, alpha=0.95)

def annotate_bars(ax, bars, multipliers, raw_texts, bar_colors, inside_threshold=0.22):
    ymax = ax.get_ylim()[1]
    for rect, mult, raw, color in zip(bars, multipliers, raw_texts, bar_colors):
        h = rect.get_height()
        x = rect.get_x() + rect.get_width()/2.0
        label1 = f"{mult:0.2f}×"
        label2 = f"({raw})"
        txt_color = "#000000" if rel_luminance(color) > 0.7 else "#FFFFFF"
        if h >= ymax * inside_threshold:
            ax.text(x, h*0.55, label1, ha='center', va='center',
                    fontsize=14, color=txt_color, weight='bold')
            ax.text(x, h*0.35, label2, ha='center', va='center',
                    fontsize=11, color=txt_color, weight='bold')
        else:
            ax.text(x, h + ymax*0.11, label1, ha='center', va='bottom',
                    fontsize=14, color=FG_TEXT, weight='bold')
            ax.text(x, h + ymax*0.03, label2, ha='center', va='bottom',
                    fontsize=11, color=FG_TEXT, weight='bold')

def read_jsonl(path):
    with open(path, "r", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]

def parse_scales(scale_args):
    out = []
    for item in scale_args:
        if "=" not in item:
            raise SystemExit(f'Invalid --scale "{item}". Use LABEL=PATH.')
        label, path = item.split("=", 1)
        out.append((label.strip(), path.strip()))
    return out

def draw_labels_at_x(ax, x_positions, labels, y_axes, *, size=10, weight=None):
    trans = mtransforms.blended_transform_factory(ax.transData, ax.transAxes)
    for x, lbl in zip(x_positions, labels):
        ax.text(x, y_axes, lbl, transform=trans,
                ha='center', va='top', fontsize=size,
                weight=weight, clip_on=False)

def render_multi(out_path, scale_specs, runtime_key="rt_hot", cost_key="cost_hot",
                 group_spacing=0.8,
                 title_perf="Elapsed Time (Lower is Better)",
                 title_cost="Total Cost (Lower is Better)"):
    apply_dark_theme()

    data = []
    max_rt = max_cost = 1.0
    for scale_label, path in scale_specs:
        recs = read_jsonl(path)
        if not recs: continue
        labels  = [r["bar_label"] for r in recs]
        systems = [r["system"] for r in recs]
        colors  = [color_for(s) for s in systems]

        base_rt, base_cost = float(recs[0][runtime_key]), float(recs[0][cost_key])
        rt_vals   = [float(r[runtime_key]) for r in recs]
        cost_vals = [float(r[cost_key]) for r in recs]
        rt_mult   = [v/base_rt for v in rt_vals]
        cost_mult = [v/base_cost for v in cost_vals]
        rt_raw    = [fmt_secs(v) for v in rt_vals]
        cost_raw  = [fmt_money(v) for v in cost_vals]

        max_rt   = max(max_rt, max(rt_mult))
        max_cost = max(max_cost, max(cost_mult))

        data.append(dict(scale=scale_label, labels=labels, systems=systems,
                         colors=colors, rt_mult=rt_mult, cost_mult=cost_mult,
                         rt_raw=rt_raw, cost_raw=cost_raw))
    if not data:
        raise SystemExit("No scales loaded.")

    fig = plt.figure(figsize=(18, 9), constrained_layout=False)
    gs  = fig.add_gridspec(2, 1, height_ratios=[1,1], hspace=0.55)
    ax_top = fig.add_subplot(gs[0,0])
    ax_bot = fig.add_subplot(gs[1,0])

    group_width = 0.8
    bar_gap     = 0.02
    max_bars    = max(len(s["labels"]) for s in data)
    bar_width   = (group_width - bar_gap*(max_bars-1)) / max_bars

    group_centers, xcenters_all, left_edges = [], [], []
    cursor = 0.0
    for s in data:
        n = len(s["labels"])
        centers = [cursor + (i*(bar_width + bar_gap) + bar_width/2.0) for i in range(n)]
        xcenters_all.extend(centers)
        lefts = [c - bar_width/2.0 for c in centers]
        left_edges.append(lefts)
        group_centers.append(0.5*(centers[0] + centers[-1]))
        cursor += group_width + group_spacing

    total_width = cursor - group_spacing
    for ax in (ax_top, ax_bot):
        ax.set_xlim(-0.02, total_width + 0.02)

    flat_labels  = [lbl for s in data for lbl in s["labels"]]
    scale_labels = [s["scale"] for s in data]

    # ----- PERF
    ax_top.set_ylim(0, max(max_rt*1.18, 1.25))
    ax_top.set_title(title_perf, color=TITLE, pad=10, fontsize=16, weight="bold")
    ax_top.yaxis.set_major_locator(MaxNLocator(nbins=5))
    ax_top.yaxis.set_major_formatter(FuncFormatter(ytick_formatter))
    ax_top.yaxis.grid(True)

    for s, lefts in zip(data, left_edges):
        bars = ax_top.bar(lefts, s["rt_mult"], width=bar_width,
                          color=s["colors"], edgecolor="none", zorder=3, align='edge')
        annotate_bars(ax_top, bars, s["rt_mult"], s["rt_raw"], s["colors"])

    ax_top.set_xticks(group_centers)
    ax_top.set_xticklabels([])
    draw_labels_at_x(ax_top, xcenters_all, flat_labels,  y_axes=MINOR_YAX, size=10)
    draw_labels_at_x(ax_top, group_centers, scale_labels, y_axes=MAJOR_YAX, size=14, weight='bold')
    add_left_rail(ax_top, "PERF")

    # ----- COST
    ax_bot.set_ylim(0, max(max_cost*1.18, 1.25))
    ax_bot.set_title(title_cost, color=TITLE, pad=10, fontsize=16, weight="bold")
    ax_bot.yaxis.set_major_locator(MaxNLocator(nbins=5))
    ax_bot.yaxis.set_major_formatter(FuncFormatter(ytick_formatter))
    ax_bot.yaxis.grid(True)

    for s, lefts in zip(data, left_edges):
        bars = ax_bot.bar(lefts, s["cost_mult"], width=bar_width,
                          color=s["colors"], edgecolor="none", zorder=3, align='edge')
        annotate_bars(ax_bot, bars, s["cost_mult"], s["cost_raw"], s["colors"])

    ax_bot.set_xticks(group_centers)
    ax_bot.set_xticklabels([])
    draw_labels_at_x(ax_bot, xcenters_all, flat_labels,  y_axes=MINOR_YAX, size=10)
    draw_labels_at_x(ax_bot, group_centers, scale_labels, y_axes=MAJOR_YAX, size=14, weight='bold')
    add_left_rail(ax_bot, "COST")

    # Legend
    order = ["ClickHouse", "BigQuery", "Redshift"]
    present = [s for s in order if any(s == sys for d in data for sys in d["systems"])]
    handles = [Patch(label=s, facecolor=color_for(s)) for s in present]
    fig.legend(handles=handles, loc="upper right", frameon=True)

    # --- Hide ALL y-axis spines and tick marks, keep only numeric labels
    for ax in (ax_top, ax_bot):
        ax.spines['top'].set_visible(False)
        ax.spines['right'].set_visible(False)
        ax.spines['bottom'].set_visible(False)
        ax.spines['left'].set_visible(False)         # <— no left spine
        ax.tick_params(axis='y', which='both', length=0)   # <— no tick marks
        ax.tick_params(axis='x', which='major', length=0)
        ax.tick_params(axis='y', labelsize=11)

    fig.subplots_adjust(bottom=0.20)

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(out_path, dpi=220, bbox_inches="tight")
    plt.close(fig)

def main():
    ap = argparse.ArgumentParser(description="PERF+COST chart (two-level x axis, no y-axis lines/ticks)")
    ap.add_argument("--scale", action="append", required=True,
                    help='Repeatable. Format: "LABEL=PATH". Example: --scale "100M=./cb_100m.jsonl"')
    ap.add_argument("--out", default="clickbench_hot_multi.png", help="Output PNG")
    ap.add_argument("--runtime_key", default="rt_hot")
    ap.add_argument("--cost_key", default="cost_hot")
    ap.add_argument("--group_spacing", type=float, default=0.8,
                    help="Horizontal gap between scale groups")
    args = ap.parse_args()

    scales = parse_scales(args.scale)
    render_multi(out_path=args.out, scale_specs=scales,
                 runtime_key=args.runtime_key, cost_key=args.cost_key,
                 group_spacing=args.group_spacing)

if __name__ == "__main__":
    main()
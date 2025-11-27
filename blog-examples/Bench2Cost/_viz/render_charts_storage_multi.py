#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re, json, argparse
from pathlib import Path
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from matplotlib.ticker import FuncFormatter, MaxNLocator


# ---------- THEME ----------
DARK_BG  = "#222425"
DARK_AX  = "#2A2C2D"
FG_TEXT  = "#FFFFFF"
GRID     = "#8E9396"
TICK     = "#D8DBDD"
TITLE    = "#FFFFFF"

COLOR_BY_SYSTEM = {
    "ClickHouse": "#FFF59D",  # soft yellow
    "BigQuery":   "#4E79A7",  # blue
    "Redshift":   "#E15759",  # red
}

def apply_dark_theme():
    plt.rcParams.update({
        "figure.facecolor": DARK_BG,
        "axes.facecolor": DARK_AX,
        "savefig.facecolor": DARK_BG,
        "axes.edgecolor": TICK,
        "axes.labelcolor": FG_TEXT,
        "xtick.color": TICK,
        "ytick.color": TICK,
        "text.color": FG_TEXT,
        "grid.color": GRID,
        "grid.alpha": 0.25,
        "axes.grid": True,
        "font.size": 12,
        "font.family": "Inter",
    })

# ---------- UTIL ----------
SIZE_RE = re.compile(r"^\s*([0-9]*\.?[0-9]+)\s*([KMGT]i?B)?\s*$", re.I)

def parse_size_to_gib(s):
    """Accepts '41.48 GiB', '0.94 TiB', numeric GiB, etc., returns GiB (float).”
    """
    if isinstance(s, (int, float)):
        return float(s)
    if not isinstance(s, str):
        return float(s)
    m = SIZE_RE.match(s)
    if not m:
        # best-effort: strip non-numerics
        return float(re.sub(r"[^\d.]", "", s))
    val = float(m.group(1))
    unit = (m.group(2) or "GiB").lower()
    if unit in ("gib","gb"):  return val
    if unit in ("tib","tb"):  return val * 1024.0
    if unit in ("mib","mb"):  return val / 1024.0
    if unit in ("kib","kb"):  return val / (1024.0 * 1024.0)
    return val

def fmt_money(v):     return f"${v:0.2f}"
def fmt_size_gib(v):  return f"{v/1024.0:0.2f} TiB" if v >= 1024 else f"{v:0.2f} GiB"
def ytick_formatter(v, _): return f"{v:.0f}×" if v >= 1 else f"{v:.2f}×"

def rel_luminance(hex_color):
    h = hex_color.lstrip('#')
    r, g, b = [int(h[i:i+2], 16)/255.0 for i in (0,2,4)]
    return 0.2126*r + 0.7152*g + 0.0722*b

def color_for(system):
    return COLOR_BY_SYSTEM.get(system,
        plt.rcParams['axes.prop_cycle'].by_key()['color'][0])

def add_left_rail(ax, text):
    ax.text(-0.10, 0.5, text, transform=ax.transAxes,
            va='center', ha='center', rotation=90,
            fontsize=56, weight='bold', color=FG_TEXT, alpha=0.95)

def annotate_bars(ax, bars, multipliers, raw_texts, bar_colors, inside_threshold=0.22):
    """Draw multiplier + raw value. Keeps order consistent even when outside."""
    ymax = ax.get_ylim()[1]
    for rect, mult, raw, color in zip(bars, multipliers, raw_texts, bar_colors):
        h = rect.get_height()
        x = rect.get_x() + rect.get_width()/2.0
        label1 = f"{mult:0.2f}×"     # multiplier first
        label2 = f"({raw})"          # raw second
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
    recs = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                recs.append(json.loads(line))
    return recs

def parse_scales(scale_args):
    # each string like "100M=./path.jsonl"
    out = []
    for item in scale_args:
        if "=" not in item:
            raise SystemExit(f'Invalid --scale "{item}". Use LABEL=PATH.')
        label, path = item.split("=", 1)
        label, path = label.strip(), path.strip()
        if not label or not path:
            raise SystemExit(f'Invalid --scale "{item}". Use LABEL=PATH.')
        out.append((label, path))
    return out

# ---------- RENDER ----------
def render_multi(out_path, scale_specs, group_spacing=0.8, hspace=0.55):
    apply_dark_theme()

    data = []
    systems_present = []
    max_size = max_cost = 1.0

    for scale_label, path in scale_specs:
        recs = read_jsonl(path)
        if not recs:
            continue

        labels  = [r["bar_label"] for r in recs]
        systems = [r["system"] for r in recs]
        colors  = [color_for(s) for s in systems]
        for s in systems:
            if s not in systems_present:
                systems_present.append(s)

        size_vals = [parse_size_to_gib(r["data_sz"]) for r in recs]
        cost_vals = [float(r["cost_data"]) for r in recs]
        base_size, base_cost = size_vals[0], cost_vals[0]

        size_mult = [v / base_size for v in size_vals]
        cost_mult = [v / base_cost for v in cost_vals]
        size_raw  = [fmt_size_gib(v) for v in size_vals]
        cost_raw  = [fmt_money(v) for v in cost_vals]

        max_size = max(max_size, max(size_mult))
        max_cost = max(max_cost, max(cost_mult))

        data.append(dict(
            scale=scale_label, labels=labels, systems=systems, colors=colors,
            size_mult=size_mult, cost_mult=cost_mult, size_raw=size_raw, cost_raw=cost_raw
        ))

    if not data:
        raise SystemExit("No scales loaded.")

    # Figure & grid
    fig = plt.figure(figsize=(18, 9), constrained_layout=False)
    gs  = fig.add_gridspec(2, 1, height_ratios=[1,1], hspace=hspace)
    ax_top = fig.add_subplot(gs[0,0])
    ax_bot = fig.add_subplot(gs[1,0])

    # Group layout (same as perf_multi)
    group_width = 0.8
    bar_gap = 0.02
    max_bars = max(len(s["labels"]) for s in data)
    bar_width = (group_width - bar_gap * (max_bars - 1)) / max_bars

    group_centers = []
    left_edges_by_group = []
    cursor = 0.0
    for s in data:
        n = len(s["labels"])
        centers = [cursor + (i*(bar_width + bar_gap) + bar_width/2.0) for i in range(n)]
        lefts   = [c - bar_width/2.0 for c in centers]
        left_edges_by_group.append(lefts)
        group_centers.append(0.5*(centers[0] + centers[-1]))  # true midpoint
        cursor += group_width + group_spacing

    total_width = cursor - group_spacing
    for ax in (ax_top, ax_bot):
        ax.set_xlim(-0.02, total_width + 0.02)

    # ----- SIZE (top)
    ax_top.set_ylim(0, max(max_size*1.18, 1.25))
    ax_top.set_title("Storage Size (Lower is Better)", color=TITLE, pad=10,
                     fontsize=16, weight="bold")
    ax_top.yaxis.set_major_locator(MaxNLocator(nbins=5))
    ax_top.yaxis.set_major_formatter(FuncFormatter(ytick_formatter))
    for s, lefts in zip(data, left_edges_by_group):
        bars = ax_top.bar(lefts, s["size_mult"], width=bar_width,
                          color=s["colors"], edgecolor="none", zorder=3, align='edge')
        annotate_bars(ax_top, bars, s["size_mult"], s["size_raw"], s["colors"])
    # Only major x labels = scale labels (bold, centered)
    ax_top.set_xticks(group_centers, [s["scale"] for s in data])
    for t in ax_top.get_xticklabels():
        t.set_fontweight("bold")
        t.set_horizontalalignment("center")
        t.set_fontsize(14)   #  ← add this
    ax_top.tick_params(axis='x', which='major', pad=30, length=0)  # extra gap, no vertical lines
    add_left_rail(ax_top, "SIZE")

    # ----- COST (bottom)
    ax_bot.set_ylim(0, max(max_cost*1.18, 1.25))
    ax_bot.set_title("Storage Cost (Lower is Better)", color=TITLE, pad=10,
                     fontsize=16, weight="bold")
    ax_bot.yaxis.set_major_locator(MaxNLocator(nbins=5))
    ax_bot.yaxis.set_major_formatter(FuncFormatter(ytick_formatter))
    for s, lefts in zip(data, left_edges_by_group):
        bars = ax_bot.bar(lefts, s["cost_mult"], width=bar_width,
                          color=s["colors"], edgecolor="none", zorder=3, align='edge')
        annotate_bars(ax_bot, bars, s["cost_mult"], s["cost_raw"], s["colors"])
    ax_bot.set_xticks(group_centers, [s["scale"] for s in data])
    for t in ax_bot.get_xticklabels():
        t.set_fontweight("bold")
        t.set_horizontalalignment("center")
        t.set_fontsize(14)   #  ← add this
    ax_bot.tick_params(axis='x', which='major', pad=30, length=0)
    add_left_rail(ax_bot, "COST")

    # Legend (systems only)
    order = ["ClickHouse", "BigQuery", "Redshift"]
    present = [s for s in order if s in systems_present]
    handles = [Patch(label=s, facecolor=color_for(s)) for s in present]
    fig.legend(handles=handles, loc="upper right", frameon=True)

    # Clean spines & ticks:
    # - hide top/right spines
    # - hide bottom spine (no base line under ticks)
    # - hide left spine (no y-axis line) + remove tick marks, keep labels
    for ax in (ax_top, ax_bot):
        ax.spines['top'].set_visible(False)
        ax.spines['right'].set_visible(False)
        ax.spines['bottom'].set_visible(False)
        ax.spines['left'].set_visible(False)
        ax.tick_params(axis='y', length=0)  # no tick marks
        ax.tick_params(axis='y', labelsize=11)

    # a bit of extra bottom space for the bold scale labels
    fig.subplots_adjust(bottom=0.12)

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(out_path, dpi=220, bbox_inches="tight")
    plt.close(fig)

# ---------- CLI ----------
def main():
    ap = argparse.ArgumentParser(
        description="Composite Storage Size + Storage Cost grouped by data scale (multi-scale)"
    )
    ap.add_argument("--scale", action="append", required=True,
                    help='Repeatable. Format: "LABEL=PATH". Example: --scale "100M=./cb_storage_100m.jsonl"')
    ap.add_argument("--out", default="storage_multi.png", help="Output PNG")
    ap.add_argument("--group_spacing", type=float, default=0.8,
                    help="Horizontal gap between scale groups (default 0.8). Lower = closer.")
    ap.add_argument("--hspace", type=float, default=0.55,
                    help="Vertical space between the two charts (default 0.55).")
    args = ap.parse_args()

    specs = parse_scales(args.scale)
    render_multi(out_path=args.out, scale_specs=specs,
                 group_spacing=args.group_spacing, hspace=args.hspace)

if __name__ == "__main__":
    main()
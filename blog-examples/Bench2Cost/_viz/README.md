# ClickBench Multi‑Scale Chart Renderers

These two Python scripts render **two‑panel**, **dark‑theme** comparison charts from
ClickBench‑style result files. You can compare **multiple data scales** (e.g. `100M` vs `1B` rows)
side‑by‑side on a single figure.

- `render_charts_perf_multi.py` → **PERF (Elapsed Time)** on top and **COST** on bottom  
- `render_charts_storage_multi.py` → **SIZE (Storage)** on top and **COST** on bottom

Each panel shows **multipliers normalized to the first record** in each scale’s file
(the first row in the `.jsonl` is the baseline and is shown as `1×`).

---

## Requirements

- Python 3.9+
- matplotlib

Install:
```bash
pip install matplotlib
```

No other packages are required.

---

## Input format

Each input is a **JSON Lines** (`.jsonl`) file — **one JSON object per bar** in the order you want
the bars to appear. The **first row is the baseline** for that scale.

### Performance chart (`render_charts_perf_multi.py`)
Required fields per row: `system`, `bar_label`, `rt_hot` (seconds), `cost_hot` (USD).

```json
{"system":"ClickHouse","bar_label":"CH Ent 2×236GiB","rt_hot":7.63,"cost_hot":0.25}
{"system":"BigQuery","bar_label":"BQ Ent+","rt_hot":19.70,"cost_hot":0.39}
{"system":"Redshift","bar_label":"RS Serverless","rt_hot":9.36,"cost_hot":0.73}
```

### Storage chart (`render_charts_storage_multi.py`)
Required fields per row: `system`, `bar_label`, `data_sz` (GiB/TiB string or numeric GiB), `cost_data` (USD).

```json
{"system":"ClickHouse","bar_label":"CH Ent 2×236GiB","data_sz":"41.48 GiB","cost_data":1.13}
{"system":"BigQuery","bar_label":"BQ Ent+","data_sz":"96.41 GiB","cost_data":17.98}
{"system":"Redshift","bar_label":"RS Serverless","data_sz":"296.29 GiB","cost_data":0.78}
```

Notes on `data_sz`:
- Accepts strings like "41.48 GiB", "0.94 TiB", "9260" (interpreted as GiB).
- Units supported: KiB/MiB/GiB/TiB (and KB/MB/GB/TB).

---

## Usage

You can pass **one or more scales** using repeated `--scale` flags:

```
--scale "LABEL=path/to/results.jsonl"
```

Where `LABEL` becomes the **major x‑axis label** for that group (e.g. `ClickBench 100M`).

### A) Performance (runtime + cost)

```bash
python3 render_charts_perf_multi.py   --out ./_out/clickbench_hot_multi.png   --scale "ClickBench 100M=./_test/results_100M_hot.jsonl"   --scale "ClickBench XL 1B=./_test/results_1B_hot.jsonl"   --group_spacing 0.4
```

### B) Storage (size + cost)

```bash
python3 render_charts_storage_multi.py   --out ./_out/clickbench_storage_multi.png   --scale "ClickBench 100M=./_test/results_100M_storage.jsonl"   --scale "ClickBench XL 1B=./_test/results_1B_storage.jsonl"   --group_spacing 0.4
```

### C) Single‑scale run

```bash
python3 render_charts_perf_multi.py   --out ./_out/clickbench_hot_single.png   --scale "ClickBench XL 1B=./_test/test1.jsonl"   --group_spacing 0.4
```

---

## Options

| Flag | Applies to | Default | Description |
| --- | --- | --- | --- |
| `--out PATH` | both | `clickbench_hot_multi.png` / `storage_multi.png` | Output PNG path |
| `--scale "LABEL=FILE"` | both | (required) | Repeatable. LABEL is used as the group label on x‑axis. |
| `--group_spacing FLOAT` | both | `0.8` | Horizontal gap between scale groups. **Lower = closer.** |

Implementation details that match the final design you approved:
- Dark theme, subtle grid, large vertical "PERF" / "COST" rails.
- **Centered per‑bar labels** (performance script) placed directly under each bar.
- **Bold major x‑axis labels** (scale labels) with extra vertical spacing from minor labels.
- Minimal y‑axis chrome (no spine/ticks on y; only labels for readability).
- For the storage script, only **major** x‑axis labels are shown (no per‑bar labels).

---

## Output

Both scripts produce a single **high‑resolution PNG** with two stacked panels:

- **Top**: `PERF` (elapsed time multipliers) **or** `SIZE` (storage multipliers)
- **Bottom**: `COST` (cost multipliers)

The legend shows systems with consistent colors:
- ClickHouse: soft yellow `#FFF59D`
- BigQuery: blue `#4E79A7`
- Redshift: red `#E15759`

---

## Customization

### Colors
Edit the `COLOR_BY_SYSTEM` map at the top of each script:
```python
COLOR_BY_SYSTEM = {
    "ClickHouse": "#FFF59D",
    "BigQuery":   "#4E79A7",
    "Redshift":   "#E15759",
}
```

### Fonts (use Inter everywhere)
1) Install the Inter font (TTF).
2) Add this near the top of the scripts (after imports) to force Inter:
```python
import matplotlib.font_manager as fm, matplotlib.pyplot as plt
fm.fontManager.addfont("/path/to/Inter-Variable.ttf")  # or Inter-Regular.ttf
plt.rcParams["font.family"] = "Inter"
```
If it doesn’t take effect, clear the Matplotlib font cache:
```bash
rm -rf ~/.cache/matplotlib
```

---

## Tips

- **Baseline is the first row** in each `.jsonl`. Put your reference system first.
- Bars render in **file order**.
- If groups feel too far apart, lower `--group_spacing` (e.g. `0.4`).
- Very long bar labels can be shortened in your jsonl; the chart centers them correctly.

---

## Troubleshooting

**KeyError for a field**  
A required field is missing in some row. Check the “Input format” section above.

**Storage size parsing fails**  
Make sure `data_sz` is numeric GiB or a string with units (GiB/TiB/etc.).

**Inter font doesn’t show**  
Verify the font path, add it via `font_manager`, and clear the Matplotlib cache.

---

## License

MIT (or your project’s license).

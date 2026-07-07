#!/usr/bin/env python3
"""Render the published benchmark stats (evals/published.json) into the SVG charts
embedded in the README. Stdlib only; charts are generated, never hand-drawn, so the
visuals always match the published numbers. Theme-aware via prefers-color-scheme.

Palette: validated two-series categorical (blue=baseline/control, aqua=fable-mode);
aqua sits below 3:1 on light surfaces, so every bar carries a visible direct label.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "assets"

STYLE = """<style>
    .t1 { font: 700 16px ui-sans-serif,system-ui,sans-serif; fill: #0b0b0b; }
    .t2 { font: 12px ui-sans-serif,system-ui,sans-serif; fill: #52514e; }
    .lbl { font: 13px ui-sans-serif,system-ui,sans-serif; fill: #0b0b0b; }
    .val { font: 700 13px ui-sans-serif,system-ui,sans-serif; fill: #0b0b0b; }
    .onbar { font: 700 12px ui-sans-serif,system-ui,sans-serif; fill: #ffffff; }
    .s1 { fill: #2a78d6; } .s2 { fill: #1baf7a; }
    .grid { stroke: #52514e; stroke-opacity: .35; stroke-dasharray: 3 3; }
    .bg { fill: #fcfcfb; }
    @media (prefers-color-scheme: dark) {
      .t1, .lbl, .val { fill: #ffffff; }
      .t2 { fill: #c3c2b7; }
      .s1 { fill: #3987e5; } .s2 { fill: #199e70; }
      .grid { stroke: #c3c2b7; }
      .bg { fill: #1a1a19; }
    }
  </style>"""


def svg(width, height, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}" role="img">\n  {STYLE}\n'
            f'  <rect class="bg" width="{width}" height="{height}" rx="8"/>\n{body}</svg>\n')


def legend(x, y):
    return (f'<rect class="s1" x="{x}" y="{y}" width="10" height="10" rx="2"/>'
            f'<text class="t2" x="{x + 15}" y="{y + 9}">baseline / unassisted</text>'
            f'<rect class="s2" x="{x + 165}" y="{y}" width="10" height="10" rx="2"/>'
            f'<text class="t2" x="{x + 180}" y="{y + 9}">+ fable-mode</text>')


def cost_chart(d):
    w, bar_max, x0 = 760, 560, 16
    top = max(r["cost_usd"] for r in d["rows"])
    body, y = [f'<text class="t1" x="16" y="28">{d["title"]}</text>',
               f'<text class="t2" x="16" y="47">{d["subtitle"]}</text>',
               legend(360, 18)][:2], 74
    body.append(legend(430, 20))
    for r in d["rows"]:
        bw = max(46, round(bar_max * r["cost_usd"] / top))
        cls = "s1" if r["series"] == 1 else "s2"
        body.append(f'<text class="lbl" x="{x0}" y="{y - 6}">{r["label"]}</text>')
        body.append(f'<rect class="{cls}" x="{x0}" y="{y}" width="{bw}" height="20" rx="4"/>')
        body.append(f'<text class="onbar" x="{x0 + 8}" y="{y + 14}">{r["pass"]} outcomes</text>')
        body.append(f'<text class="val" x="{x0 + bw + 10}" y="{y + 15}">${r["cost_usd"]:.2f}</text>')
        y += 58
    body.append(f'<text class="t2" x="16" y="{y + 2}">{d["footnote"]}</text>')
    return svg(w, y + 16, "\n".join(f"  {b}" for b in body) + "\n")


def indexed_chart(d):
    w, x0, bar_max = 760, 150, 470
    body = [f'<text class="t1" x="16" y="28">{d["title"]}</text>',
            f'<text class="t2" x="16" y="47">{d["subtitle"]}</text>',
            legend(16, 58)]
    y = 92
    ref_x = x0 + bar_max  # control = 100%
    y_end = y + len(d["rows"]) * 52 - 18
    body.append(f'<line class="grid" x1="{ref_x}" y1="{y - 10}" x2="{ref_x}" y2="{y_end + 6}"/>')
    body.append(f'<text class="t2" x="{ref_x - 42}" y="{y_end + 20}">control = 100%</text>')
    for r in d["rows"]:
        body.append(f'<text class="lbl" x="16" y="{y + 14}">{r["metric"]}</text>')
        body.append(f'<rect class="s1" x="{x0}" y="{y}" width="{bar_max}" height="14" rx="4"/>')
        body.append(f'<text class="val" x="{ref_x + 10}" y="{y + 12}">{r["control_abs"]}</text>')
        fw = round(bar_max * r["fable_pct"] / 100)
        y2 = y + 16  # 2px surface gap between the pair
        body.append(f'<rect class="s2" x="{x0}" y="{y2}" width="{fw}" height="14" rx="4"/>')
        body.append(f'<text class="val" x="{x0 + fw + 10}" y="{y2 + 12}">{r["fable_abs"]} '
                    f'(−{100 - r["fable_pct"]}%)</text>')
        y += 52
    body.append(f'<text class="t2" x="16" y="{y + 24}">{d["footnote"]}</text>')
    return svg(w, y + 38, "\n".join(f"  {b}" for b in body) + "\n")


def main():
    d = json.loads((ROOT / "published.json").read_text())
    OUT.mkdir(exist_ok=True)
    (OUT / "benchmark.svg").write_text(cost_chart(d["cost_threeway"]))
    (OUT / "chart-marathon.svg").write_text(indexed_chart(d["marathon_sonnet"]))
    (OUT / "chart-haiku.svg").write_text(indexed_chart(d["haiku_easy"]))
    print("rendered: benchmark.svg chart-marathon.svg chart-haiku.svg")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Convert a truecolor-ANSI ASCII art file into lua/dashboard_art.lua.

    python scripts/ansi_to_dashboard_art.py <ansi_file> [colors]

Expects each character to be wrapped as ESC[38;2;R;G;Bm<char>ESC[0m, which is
what most `image -> colored ascii` tools emit. Use gen_dashboard_art.py instead
if you are starting from an image.

Emits the same module shape img2art's --alpha produces, so dashboard.lua can
consume `.val` (the art lines) and `.opts.hl` (per-row highlight segments)
without any changes:

  * Source art usually colors every character individually -- this file had 1164
    distinct colors -- so colors are quantized to `colors` groups. Each group
    becomes one nvim_set_hl call.
  * Spaces carry no visible foreground, so they get no highlight at all. Runs of
    adjacent same-color characters are merged into one segment, which keeps the
    extmark count low.
  * Columns are byte offsets, matching what dashboard.lua expects.

Stdlib only: no numpy, no opencv, no img2art.
"""
import re
import sys
from collections import Counter
from pathlib import Path

CELL = re.compile(r"\x1b\[38;2;(\d+);(\d+);(\d+)m(.)\x1b\[0m")
ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "lua" / "dashboard_art.lua"

TEMPLATE = """
local header = {{
    type='text',
    opts={{
        position='center',
        hl = {{
{hl}
        }},
    }},
    val = {{
{val}
    }},
}}
return header
"""


def luma(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def kmeans(colors, weights, k, iters=40):
    """Deterministic weighted k-means over RGB triples."""
    uniq = sorted(colors, key=luma)
    k = min(k, len(uniq))
    # seed evenly along the luminance ramp rather than randomly, so reruns match
    centroids = [uniq[round(i * (len(uniq) - 1) / max(k - 1, 1))] for i in range(k)]

    for _ in range(iters):
        buckets = [[0.0, 0.0, 0.0, 0] for _ in range(k)]
        for c in colors:
            w = weights[c]
            j = min(range(k), key=lambda i: sum((a - b) ** 2 for a, b in zip(c, centroids[i])))
            b = buckets[j]
            b[0] += c[0] * w
            b[1] += c[1] * w
            b[2] += c[2] * w
            b[3] += w
        moved = False
        for i, b in enumerate(buckets):
            if b[3]:
                new = (round(b[0] / b[3]), round(b[1] / b[3]), round(b[2] / b[3]))
                if new != centroids[i]:
                    centroids[i] = new
                    moved = True
        if not moved:
            break

    assign = {c: min(range(k), key=lambda i: sum((a - b) ** 2 for a, b in zip(c, centroids[i])))
              for c in colors}
    return centroids, assign


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = Path(sys.argv[1])
    k = int(sys.argv[2]) if len(sys.argv) > 2 else 24

    grid = []
    for line in src.read_text(encoding="utf-8").split("\n"):
        cells = [(ch, (int(r), int(g), int(b))) for r, g, b, ch in CELL.findall(line)]
        if cells:
            grid.append(cells)
    if not grid:
        raise SystemExit("no ESC[38;2;R;G;Bm<char> cells found -- is this truecolor ANSI?")

    width = max(len(r) for r in grid)
    grid = [r + [(" ", (0, 0, 0))] * (width - len(r)) for r in grid]

    # trim the all-blank border
    rows = [i for i, r in enumerate(grid) if any(ch != " " for ch, _ in r)]
    cols = [j for j in range(width) if any(grid[i][j][0] != " " for i in rows)]
    grid = [r[cols[0]:cols[-1] + 1] for r in grid[rows[0]:rows[-1] + 1]]

    counts = Counter(col for r in grid for ch, col in r if ch != " ")
    centroids, assign = kmeans(list(counts), counts, k)

    # one hl group per centroid actually used, deduped by hex
    used, groups = {}, []
    for i in sorted({assign[c] for c in counts}):
        hexs = "%02x%02x%02x" % centroids[i]
        if hexs not in used:
            used[hexs] = f"I2A{len(used)}"
            groups.append(f'vim.api.nvim_set_hl(0,"{used[hexs]}",{{fg="#{hexs}"}})')

    val_lines, hl_lines = [], []
    for row in grid:
        text = "".join(ch for ch, _ in row)
        if "]]" in text:
            raise SystemExit("art contains ']]' -- long-bracket quoting would break")
        val_lines.append(f"[[{text}]],")

        segs, run = [], None  # merge adjacent cells sharing a group
        for j, (ch, col) in enumerate(row):
            g = None if ch == " " else used["%02x%02x%02x" % centroids[assign[col]]]
            start = len(text[:j].encode("utf-8"))
            end = start + len(ch.encode("utf-8"))
            if run and g == run[0] and start == run[2]:
                run[2] = end
            else:
                if run:
                    segs.append(run)
                run = [g, start, end] if g else None
        if run:
            segs.append(run)
        body = " ".join(f'{{"{g}",{s},{e}}},' for g, s, e in segs)
        hl_lines.append("{%s}," % body)

    banner = (
        f"-- Generated from {src.name} by scripts/{Path(__file__).name}. Do not edit by hand.\n"
        f"-- {len(grid)} rows x {len(grid[0])} cols, {len(counts)} source colors "
        f"quantized to {len(used)} groups.\n"
        "-- Shaped like img2art's --alpha output; dashboard.lua reads .val and .opts.hl.\n\n"
    )
    body = TEMPLATE.format(
        hl="\n".join(" " * 12 + h for h in hl_lines),
        val="\n".join(" " * 8 + v for v in val_lines),
    )
    DEST.write_text(banner + "\n".join(groups) + "\n" + body, encoding="utf-8")

    marks = sum(h.count("{\"") for h in hl_lines)
    print(f"wrote {DEST}")
    print(f"  {len(grid)} rows x {len(grid[0])} cols")
    print(f"  {len(counts)} colors -> {len(used)} hl groups, {marks} highlight segments")


if __name__ == "__main__":
    main()

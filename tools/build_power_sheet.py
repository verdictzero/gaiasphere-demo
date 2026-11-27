#!/usr/bin/env python3
"""The power kit's rows (tests/RENDER_power_kit.gd) stacked into one sheet,
renders/power_kit.png: a part to a row, its levels left to right, its impostor last."""
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
rows = []
for piece in json.loads((ROOT / "assets/power/manifest.json").read_text()):
    im = Image.open(ROOT / "renders/power_bake" / ("row_%s.png" % piece["name"])).convert("RGB")
    # The band the row is in: whatever of the picture is not its background.
    bg = im.getpixel((2, 2))
    diff = ImageChops.difference(im, Image.new("RGB", im.size, bg)).convert("L").point(lambda v: 255 if v > 12 else 0)
    box = diff.getbbox() or (0, 0, im.width, im.height)
    top = max(box[1] - 46, 0)
    band = im.crop((0, top, im.width, min(box[3] + 24, im.height)))
    if band.height > 330:
        band = band.resize((int(band.width * 330 / band.height), 330), Image.LANCZOS)
        wide = Image.new("RGB", (im.width, 330), bg)
        wide.paste(band, ((im.width - band.width) // 2, 0))
        band = wide
    draw = ImageDraw.Draw(band)
    draw.text((12, 8), "%s   %s triangles, then the impostor" % (piece["name"], "  ".join(str(t) for t in piece["triangles"])), fill=(255, 255, 255))
    rows.append(band)
sheet = Image.new("RGB", (rows[0].width, sum(r.height for r in rows) + 4 * (len(rows) - 1)), (20, 24, 30))
y = 0
for r in rows:
    sheet.paste(r, (0, y))
    y += r.height + 4
sheet.save(ROOT / "renders/power_kit.png")
print(sheet.size)

#!/usr/bin/env python3
"""Top-down wireframe of the island's edge and the rock masses set into it.

    godot --headless --path . --script res://tests/DUMP_edge.gd -- --out=/tmp/edge.json
    python3 tools/plot_edge.py /tmp/edge.json /tmp/edge.png

Left: the whole island. Right: four stretches of coast, enlarged. Drawn are the
walkable coast (green), the shoulder that flares out below it (grey), the wall's
rings by depth (blue, darker = deeper), and each rock's footprint (red), with a
tick on the side that faces out.
"""
import json
import math
import sys

from PIL import Image, ImageDraw

d = json.load(open(sys.argv[1]))
W = 1100
img = Image.new("RGB", (W * 2, W), (16, 18, 22))
dr = ImageDraw.Draw(img)
HALF_W = {"cliff_buttress_a": 8, "cliff_buttress_b": 11, "cliff_pillar_a": 4, "cliff_pillar_b": 5,
          "cliff_slab_a": 7, "cliff_shelf_a": 9, "cliff_fang_a": 4.5, "cliff_fang_b": 6.5}


def panel(ox, oy, size, cx, cz, span, label):
    k = size / span

    def P(x, z):
        return ox + (x - cx + span / 2) * k, oy + (z - cz + span / 2) * k

    def inside(x, z):
        return abs(x - cx) < span / 2 and abs(z - cz) < span / 2
    r = 1 if span > 600 else 2
    for x, y, z in d["top"]:
        if inside(x, z) and y < -0.6:                       # the shoulder
            px, pz = P(x, z)
            dr.point((px, pz), fill=(110, 110, 110))
    for x, y, z in d["wall"]:
        if inside(x, z):
            px, pz = P(x, z)
            shade = max(70, 255 + int(y * 1.4))
            dr.ellipse((px - r, pz - r, px + r, pz + r), fill=(40, shade // 2 + 40, shade))
    for rk in d["rocks"]:
        if not inside(rk["x"], rk["z"]):
            continue
        hw, hd = HALF_W[rk["name"]] * rk["sx"], rk["half_depth"]
        c, s = math.cos(rk["yaw"]), math.sin(rk["yaw"])
        pts = [P(rk["x"] + a * hw * c + b * hd * s, rk["z"] - a * hw * s + b * hd * c)
               for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        dr.polygon(pts, outline=(255, 70, 60))
        dr.line([P(rk["x"], rk["z"]), P(rk["x"] + rk["nx"] * hd, rk["z"] + rk["nz"] * hd)], fill=(255, 200, 60))
        cx0, cz0 = P(rk["dx"] * rk["coast"], rk["dz"] * rk["coast"])
        dr.ellipse((cx0 - 2, cz0 - 2, cx0 + 2, cz0 + 2), fill=(60, 255, 90))    # the walkable coast here
    dr.rectangle((ox, oy, ox + size - 1, oy + size - 1), outline=(70, 70, 80))
    dr.text((ox + 6, oy + 4), label, fill=(230, 230, 230))


panel(0, 0, W, 0, 0, 3000, "whole island, 3 km across")
rocks = d["rocks"]
for i, rk in enumerate([rocks[0], rocks[len(rocks) // 4], rocks[len(rocks) // 2], rocks[3 * len(rocks) // 4]]):
    panel(W + (i % 2) * W // 2, (i // 2) * W // 2, W // 2, rk["x"], rk["z"], 160,
          "160 m across: green coast, grey shoulder, blue wall, red rock")
img.save(sys.argv[2])
print("wrote", sys.argv[2])

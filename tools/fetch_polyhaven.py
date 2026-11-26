#!/usr/bin/env python3
"""Fetch Poly Haven texture sets (CC0) into textures/polyhaven/ as the rest are
kept: <name>_basecolor.jpg, <name>_normal.jpg (OpenGL, Godot's way up) and
<name>_orm.jpg (occlusion, roughness, metal), at 2K.

    python3 tools/fetch_polyhaven.py leafy_grass sparse_grass ...
"""
import json
import sys
import urllib.request
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "textures" / "polyhaven"
MAPS = {"Diffuse": "basecolor", "nor_gl": "normal", "arm": "orm"}


def _get(url, timeout):
    # (Poly Haven refuses Python's default client name.)
    req = urllib.request.Request(url, headers={"User-Agent": "texture-fetch/1.0"})
    return urllib.request.urlopen(req, timeout=timeout).read()


def fetch(name, res="2k"):
    files = json.loads(_get("https://api.polyhaven.com/files/" + name, 60))
    for key, suffix in MAPS.items():
        url = files[key][res]["jpg"]["url"]
        dst = OUT / ("%s_%s.jpg" % (name, suffix))
        if dst.exists():
            continue
        dst.write_bytes(_get(url, 120))
        print("  ", dst.name, dst.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    for n in sys.argv[1:]:
        print(n)
        fetch(n)

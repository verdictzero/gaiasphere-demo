#!/usr/bin/env python3
"""Make the 3D textures import as 3D textures: mipmaps, VRAM compression, and the
normal-map flag on normal maps.

    godot --headless --path . --import      # writes the .import files
    python3 tools/set_texture_imports.py
    godot --headless --path . --import      # re-imports the changed ones

Godot only detects "this image is used in 3D" from inside the editor; a texture
added from the command line imports as a 2D image with no mipmaps, which shimmers
at any distance. This sets the same values the editor's detection would.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GLOBS = ["textures/polyhaven/*.jpg", "assets/*/textures/*.png", "assets/*/textures/*.jpg",
         "assets/*/textures/impostors/*.png",
         "assets/chips/*.png", "assets/leaves/*.png", "assets/berry_bush/*.png",
         "assets/build/*/*.png", "assets/build/*/*.jpg", "assets/fx/*.webp",
         "assets/truck/*.jpg"]
changed = 0
for g in GLOBS:
    for tex in sorted(ROOT.glob(g)):
        imp = tex.with_name(tex.name + ".import")
        if not imp.exists():
            print("no .import yet:", tex.relative_to(ROOT))
            continue
        s = old = imp.read_text()
        normal = tex.stem.endswith("_normal")
        # Alpha-tested cut-outs stay lossless: block compression of their colour under a
        # hard alpha edge came out black on a software Vulkan driver, and they are few.
        cutout = tex.suffix == ".png" and not normal
        # The effects' flipbooks are many, big, and loaded only when one is played:
        # kept as lossy pictures (a tenth of the size on disk that block compression
        # for every platform comes to), at the price of more memory while in use.
        effects = "assets/fx" in tex.as_posix()
        want = {"compress/mode": "1" if effects else ("0" if cutout else "2"), "mipmaps/generate": "true",
                "detect_3d/compress_to": "0",
                "compress/normal_map": "1" if normal else "0",
                # alpha-tested foliage: keep coverage from thinning out in the mipmaps
                "process/fix_alpha_border": "true"}
        if effects:
            want["compress/lossy_quality"] = "0.85"
        for k, v in want.items():
            s, n = re.subn(r"(?m)^%s=.*$" % re.escape(k), "%s=%s" % (k, v), s)
            if not n:
                s = s.rstrip("\n") + "\n%s=%s\n" % (k, v)
        if s != old:
            imp.write_text(s)
            changed += 1
print("updated %d .import files" % changed)

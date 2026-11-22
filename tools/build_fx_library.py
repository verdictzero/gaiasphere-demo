#!/usr/bin/env python3
"""The effects library's textures and its catalogue.

    python3 tools/build_fx_library.py <folder of source sheets> assets/fx

Every sheet of fire, smoke and explosion in the source folder that is of use is
brought to one form and written to assets/fx under a plain name that says what
it is (flame_loop_03, blast_07, smoke_roll_02 ...):

    RGBA, colour not multiplied by alpha. A sheet drawn on black gets its alpha
    from its brightness (and its colour divided back up), so one material can
    draw it blended or added. Packed sheets (shade in red, glow in blue, cover
    in alpha) are unpacked into a picture. Nothing wider than 2048 (3072 for the
    big blasts), which keeps a 64-frame book at 256 px a frame.

and assets/fx/fx_catalogue.json is written beside them: for each texture its
grid, frame count and kind, and then THE EFFECTS, each a list of layers
(particles and lights) that scripts/fx/SCRIPT_fx.gd knows how to build. One
plain effect is made for every texture by its kind; the composites (campfire,
torch, explosion_large ...) are written out by hand in COMPOSITES below.
docs/FX_CATALOGUE.md is the same thing for people to read.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

# source file (its name within the folder, wherever it lies) -> name, columns, rows, kind, how it is read
#   read: "alpha" as it is; "black" drawn on black; "white" dark on white; "packed" shade/glow/cover in R/B/A
SHEETS = [
    ("Fire Tileable.jpg", "noise_fire_01", 1, 1, "tile", "rgb"),
    ("Burningtexture.png", "noise_cloud_01", 1, 1, "tile", "rgb"),
    ("Firetext.png", "noise_cloud_02", 1, 1, "tile", "rgb"),
    ("T_smoke_02.TGA", "puff_soft_01", 1, 1, "puff", "black"),
    ("Smoke.png", "puff_soft_02", 1, 1, "puff", "black"),
    ("Smoke12.png", "puff_soft_03", 1, 1, "puff", "black"),
    ("Smoke24.png", "puff_soft_04", 1, 1, "puff", "alpha"),
    ("Smoke27.png", "puff_soft_05", 1, 1, "puff", "alpha"),
    ("Smoke3.png", "puff_soft_06", 1, 1, "puff", "black"),
    ("Smoke5.png", "puff_soft_07", 1, 1, "puff", "black"),
    ("glow.png", "glow_soft_01", 1, 1, "glow", "alpha"),
    ("glow_colored.png", "glow_warm_01", 1, 1, "glow", "alpha"),
    ("glow_colored_sharp.png", "glow_warm_02", 1, 1, "glow", "alpha"),
    ("glow_colored_fast.png", "glow_streak_01", 1, 1, "glow", "alpha"),
    ("shockwave.png", "ring_01", 1, 1, "ring", "alpha"),
    ("shockwave.tif", "ring_02", 1, 1, "ring", "black"),
    ("shockwave2.png", "ring_cloud_01", 1, 1, "ring", "alpha"),
    ("Fire.tga", "flame_still_01", 1, 1, "still", "black"),
    ("candlefire.tga", "candle_still_01", 1, 1, "still", "black"),
    # loose pieces, one picked at random to a particle
    ("Fire3.png", "wisp_flame_01", 2, 2, "bits_fire", "black"),
    ("FlameSheet_2x2.png", "wisp_flame_02", 2, 2, "bits_fire", "alpha"),
    ("FlameTextureAtlasWild.png", "wisp_flame_03", 4, 4, "bits_fire", "alpha"),
    ("StylizedFlame.png", "wisp_flame_04", 2, 2, "bits_fire", "alpha"),
    ("T_fire_embers_01.png", "ember_bits_01", 2, 2, "bits_ember", "black"),
    ("Debris.png", "debris_bits_01", 2, 2, "bits_debris", "alpha"),
    ("DustPuffSmallParticleSheet.png", "dust_bits_01", 2, 2, "bits_dust", "alpha"),
    # fire that burns on and on
    ("T_fire_flipbook_big_01.png", "flame_loop_01", 8, 8, "flame_loop", "black"),
    ("T_fire_flipbook_small_01.png", "flame_loop_02", 16, 8, "flame_loop", "black"),
    ("LargeFlame01.tif", "flame_loop_03", 8, 8, "flame_loop", "black"),
    ("LargeFlame02.tif", "flame_loop_04", 8, 8, "flame_loop_grey", "black"),
    ("MediumFlame03.tif", "flame_loop_05", 12, 6, "flame_loop_grey", "black"),
    ("MedumFlame02.tif", "flame_loop_06", 8, 8, "flame_loop", "black"),
    ("CandleFlame.tif", "candle_loop_01", 16, 8, "flame_loop", "black"),
    # fire that catches, or goes up once
    ("MediumFlame01.tif", "flame_ignite_01", 10, 10, "flame_once", "black"),
    ("TinyFlame.tif", "flame_ignite_02", 11, 11, "flame_once", "black"),
    ("Flame01.tif", "flame_puff_01", 7, 7, "flame_once", "black"),
    ("Flame02.tif", "flame_puff_02", 6, 6, "flame_once", "black"),
    ("Flame03.tif", "flame_puff_03", 10, 5, "flame_once", "black"),
    ("Flame04.tif", "flame_puff_04", 6, 6, "flame_once", "black"),
    ("Fireball1.png", "fireball_trail_01", 4, 16, "fireball", "alpha"),
    # bursts of fire
    ("fire6x6_alternate.png", "fire_burst_01", 6, 6, "fire_burst", "alpha"),
    ("fire8x8_hires1.png", "fire_burst_02", 8, 8, "fire_burst", "alpha"),
    ("fire8x8_hires2.png", "fire_burst_03", 8, 8, "fire_burst", "alpha"),
    ("fire8x8_hires3.png", "fire_burst_04", 8, 8, "fire_burst", "alpha"),
    ("FireExplosion.tif", "fire_burst_05", 6, 6, "fire_burst", "black"),
    ("Fireball.tif", "fire_burst_06", 7, 7, "fire_burst", "black"),
    ("Fire1.png", "burst_white_01", 6, 6, "fire_burst_grey", "alpha"),
    ("SparkExolosion2.png", "spark_burst_01", 3, 3, "spark", "black"),
    # whole explosions: flash, fireball and the smoke after, in one book
    ("Explosion1.png", "blast_01", 12, 8, "blast", "alpha"),
    ("Explosion2.png", "blast_02", 12, 8, "blast", "alpha"),
    ("Explosion3.png", "blast_03", 12, 7, "blast", "alpha"),
    ("Explosion4.png", "blast_04", 8, 8, "blast", "alpha"),
    ("Explosion5.png", "blast_05", 12, 7, "blast", "alpha"),
    ("Explosion6.png", "blast_06", 12, 7, "blast", "alpha"),
    ("Explosion7.png", "blast_07", 12, 7, "blast", "alpha"),
    ("Explosion8.png", "blast_08", 12, 7, "blast", "alpha"),
    ("Explosion9.png", "blast_09", 12, 7, "blast", "alpha"),
    ("Explosion10.png", "blast_10", 12, 7, "blast", "alpha"),
    ("Explosion11.png", "blast_11", 12, 7, "blast", "alpha"),
    ("Explosion12.png", "blast_12", 12, 7, "blast", "alpha"),
    ("Explosion13.png", "blast_13", 12, 7, "blast_smoke", "alpha"),
    ("Explosion14.png", "blast_14", 12, 7, "blast", "alpha"),
    ("Explosion15.png", "blast_15", 12, 7, "blast_smoke", "alpha"),
    ("Explosion18.png", "blast_16", 12, 7, "blast", "alpha"),
    ("T_explosion_01_BC_E_M.png", "blast_17", 8, 8, "blast", "packed"),
    ("EmberExpl3.png", "blast_18", 8, 8, "blast", "alpha"),
    ("Explosion17.png", "dust_streak_01", 6, 12, "streak", "alpha"),
    # smoke
    ("T_smoke_01_BC_E_M.png", "smoke_roll_01", 8, 8, "smoke_loop", "packed"),
    ("T_smoke_02_BC_E_M.png", "smoke_roll_02", 8, 8, "smoke_loop", "packed"),
    ("T_smoke_03_BC_E_M.png", "smoke_roll_03", 8, 8, "smoke_loop", "packed"),
    ("T_smoke_04_BC_E_M.png", "smoke_roll_04", 8, 8, "smoke_loop", "packed"),
    ("T_smoke_05_BC_E_M.png", "smoke_roll_05", 8, 8, "smoke_loop", "packed"),
    ("T_smoke_06_BC_E_M.png", "smoke_roll_06", 8, 8, "smoke_loop", "packed"),
    ("T_smoke_07_BC_E_M.png", "smoke_roll_07", 8, 8, "smoke_loop", "packed"),
    ("T_smoke_08_BC_E_M.png", "smoke_roll_08", 8, 8, "smoke_loop", "packed"),
    ("T_smoke_09_BC_E_M.png", "smoke_roll_09", 8, 8, "smoke_loop", "packed"),
    ("SmokeAnim2.png", "smoke_dark_01", 8, 8, "smoke_loop", "alpha"),
    ("SmokeLoop.tif", "smoke_dark_02", 6, 6, "smoke_loop", "alpha"),
    ("SmokeLoop02.tif", "smoke_dark_03", 6, 6, "smoke_loop", "white"),
    ("DiscSmoke01_16x4.tga", "smoke_disc_01", 16, 4, "smoke_loop", "alpha"),
    ("SmokeySteam.tif", "steam_loop_01", 8, 8, "steam", "black"),
    ("Smoke21.png", "wisp_smoke_01", 8, 8, "smoke_once", "alpha"),
    ("WispySmoke03b_8x8.png", "wisp_smoke_02", 8, 8, "smoke_loop", "alpha"),
    ("smokewispy8x8.png", "wisp_smoke_03", 8, 8, "smoke_loop", "alpha"),
    ("wispySmoke.tif", "wisp_smoke_04", 8, 8, "smoke_loop", "black"),
    ("smoke5x5.png", "smoke_burst_01", 5, 5, "smoke_once", "alpha"),
    ("Explosion.tif", "smoke_burst_02", 6, 6, "smoke_once", "black"),
    ("SmokePuff.png", "smoke_burst_03", 6, 6, "smoke_once", "alpha"),
    ("SmokePuff01.tif", "smoke_burst_04", 5, 5, "smoke_once", "black"),
    ("SmokePuff02.png", "smoke_burst_05", 5, 5, "smoke_once", "alpha"),
    ("SmokePuff04.png", "smoke_burst_06", 5, 5, "smoke_once", "alpha"),
]

FIRE = [1.0, 0.62, 0.28]
SMOKE = [0.34, 0.33, 0.32]


def convert(path, read, limit):
    im = Image.open(path)
    if im.mode == "I;16":
        im = Image.fromarray((np.asarray(im) / 257).astype(np.uint8))
    im = im.convert("RGBA")
    if max(im.size) > limit:
        k = limit / max(im.size)
        im = im.resize((round(im.size[0] * k), round(im.size[1] * k)), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]
    if read == "rgb":
        return Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB")
    if read == "black":
        alpha = rgb.max(axis=2)
        rgb = rgb / np.maximum(alpha, 1e-3)[..., None]
        alpha = np.clip((alpha - 0.012) / 0.988, 0, 1)             # the scan's own black is not quite black
    elif read == "white":
        lum = rgb.mean(axis=2)
        alpha = np.clip((1.0 - lum) * 1.6, 0, 1)
        rgb = np.full_like(rgb, 0.22)
    elif read == "packed":
        shade, glow = rgb[..., 0], rgb[..., 2]
        fire = np.stack([np.clip(glow * 2.4, 0, 1), np.clip(glow * 1.5 - 0.1, 0, 1), np.clip(glow * 1.2 - 0.55, 0, 1)], axis=2)
        rgb = np.clip(shade[..., None] * 0.9 * (1.0 - glow[..., None] * 0.8) + fire, 0, 1)
    rgb = np.where(alpha[..., None] > 0.002, rgb, 0.0)
    out = np.dstack([rgb, alpha])
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


# ------------------------------------------------------------------ the effects

def book(tex, **kw):
    """One picture played through its frames, standing where it is put."""
    return dict(dict(type="particles", texture=tex, amount=1, play="through"), **kw)


def basic(name, t):
    """The plain effect a texture gets by its kind."""
    kind, frames = t["kind"], t["cols"] * t["rows"]
    if kind == "blast" or kind == "blast_smoke":
        seconds = round(frames / 34.0, 2)
        layers = [book(name, lifetime=seconds, size=6.0, lift=1.6)]
        if kind == "blast":
            layers.append(dict(type="light", color=[1.0, 0.7, 0.35], energy=14.0, range=18.0, flash=0.55))
        return dict(loop=False, seconds=seconds, about="A whole explosion from one book: flash, fireball, smoke.", layers=layers)
    if kind in ("fire_burst", "fire_burst_grey"):
        seconds = round(frames / 36.0, 2)
        return dict(loop=False, seconds=seconds, about="A burst of fire that swells and breaks up.", layers=[
            book(name, lifetime=seconds, size=3.2, lift=0.8, blend="add", color=FIRE if kind.endswith("grey") else [1, 1, 1]),
            dict(type="light", color=[1.0, 0.65, 0.3], energy=8.0, range=10.0, flash=0.4)])
    if kind == "spark":
        return dict(loop=False, seconds=0.6, about="A burst of sparks.", layers=[
            book(name, lifetime=0.6, size=2.4, blend="add", color=[1.0, 0.8, 0.5])])
    if kind == "flame_loop" or kind == "flame_loop_grey":
        tall = t["cell_h"] / t["cell_w"]
        return dict(loop=True, about="Fire burning on the spot.", layers=[
            book(name, lifetime=round(frames / 30.0, 2), size=1.6, lift=0.8 * tall, blend="add",
                 color=FIRE if kind.endswith("grey") else [1, 1, 1]),
            dict(type="light", color=[1.0, 0.6, 0.28], energy=2.2, range=7.0, flicker=0.35)])
    if kind == "flame_once":
        seconds = round(frames / 30.0, 2)
        return dict(loop=False, seconds=seconds, about="Fire that catches or goes up once.", layers=[
            book(name, lifetime=seconds, size=1.8, lift=0.9, blend="add"),
            dict(type="light", color=[1.0, 0.6, 0.28], energy=3.0, range=7.0, flash=seconds)])
    if kind == "fireball":
        return dict(loop=True, about="A fireball with its tail, lying along x: turn the node to aim it.", layers=[
            book(name, lifetime=round(frames / 30.0, 2), size=3.0, align="x"),
            dict(type="light", color=[1.0, 0.55, 0.2], energy=4.0, range=8.0, flicker=0.2)])
    if kind == "smoke_loop":
        return dict(loop=True, about="A column of rolling smoke.", layers=[
            dict(type="particles", texture=name, amount=14, lifetime=5.0, play="through", size=1.2, grow=2.6, rise=1.1,
                 spread=0.25, drift=0.3, fade="in_out", lit=True, turn=20.0)])
    if kind == "steam":
        return dict(loop=True, about="Steam or pale smoke lifting off.", layers=[
            dict(type="particles", texture=name, amount=12, lifetime=3.5, play="through", size=0.8, grow=2.2, rise=1.3,
                 spread=0.2, drift=0.3, fade="in_out", color=[1, 1, 1, 0.55], lit=True)])
    if kind == "smoke_once":
        seconds = round(frames / 24.0, 2)
        return dict(loop=False, seconds=seconds, about="A puff of smoke that billows and thins.", layers=[
            book(name, lifetime=seconds, size=3.0, lift=0.6, lit=True, color=[0.75, 0.74, 0.72, 0.9])])
    if kind == "streak":
        return dict(loop=False, seconds=1.6, about="A low streak of dust thrown along the ground.", layers=[
            book(name, lifetime=1.6, size=5.0, lift=0.4, lit=True)])
    if kind == "puff":
        return dict(loop=True, about="Soft drifting smoke from a single puff picture.", layers=[
            dict(type="particles", texture=name, amount=12, lifetime=4.5, play="one", size=0.9, grow=2.4, rise=0.9,
                 spread=0.25, drift=0.3, fade="in_out", color=SMOKE + [0.6], lit=True, turn=25.0)])
    if kind == "glow":
        return dict(loop=True, about="A glow that hangs and pulses.", layers=[
            dict(type="particles", texture=name, amount=1, lifetime=2.0, play="one", size=2.0, blend="add", fade="in_out")])
    if kind == "ring":
        return dict(loop=False, seconds=0.7, about="A shock ring that spreads and fades.", layers=[
            dict(type="particles", texture=name, amount=1, lifetime=0.7, play="one", size=1.0, grow=9.0, blend="add",
                 fade="out", flat=True, lift=0.15, color=[1.0, 0.9, 0.75, 0.5])])
    if kind == "still":
        return dict(loop=True, about="A single picture of flame, flickering in size.", layers=[
            dict(type="particles", texture=name, amount=3, lifetime=0.5, play="one", size=1.0, grow=1.15, blend="add",
                 fade="in_out", lift=0.5),
            dict(type="light", color=[1.0, 0.62, 0.3], energy=1.2, range=5.0, flicker=0.3)])
    if kind == "bits_fire":
        return dict(loop=True, about="Loose licks of flame rising, each a different piece.", layers=[
            dict(type="particles", texture=name, amount=18, lifetime=0.9, play="pick", size=0.7, grow=0.4, rise=1.7,
                 spread=0.3, blend="add", fade="in_out", color=FIRE, turn=40.0),
            dict(type="light", color=[1.0, 0.6, 0.28], energy=1.8, range=6.0, flicker=0.35)])
    if kind == "bits_ember":
        return dict(loop=True, about="Embers lifting and winking out.", layers=[
            dict(type="particles", texture=name, amount=24, lifetime=2.4, play="pick", size=0.09, rise=1.3, spread=0.5,
                 drift=0.8, blend="add", fade="out", color=[1.0, 0.55, 0.2], turn=180.0)])
    if kind == "bits_debris":
        return dict(loop=False, seconds=2.2, about="Chunks thrown out and falling.", layers=[
            dict(type="particles", texture=name, amount=22, lifetime=2.2, play="pick", size=0.22, burst=6.5, gravity=9.8,
                 one_shot=True, lit=True, turn=400.0, color=[0.5, 0.48, 0.45])])
    if kind == "bits_dust":
        return dict(loop=False, seconds=1.4, about="A scuff of dust.", layers=[
            dict(type="particles", texture=name, amount=10, lifetime=1.4, play="pick", size=0.8, grow=2.0, burst=1.2,
                 one_shot=True, fade="out", lit=True, color=[0.62, 0.56, 0.48, 0.6])])
    return None


def smoke(tex, amount=16, life=6.0, size=1.0, grow=3.0, rise=1.2, color=None, lift=0.0, spread=0.2):
    return dict(type="particles", texture=tex, amount=amount, lifetime=life, play="through", size=size, grow=grow, rise=rise,
                spread=spread, drift=0.35, fade="in_out", lit=True, turn=20.0, lift=lift, color=color or [1, 1, 1, 0.85])


def embers(amount=20, spread=0.4, rise=1.4, lift=0.2):
    return dict(type="particles", texture="ember_bits_01", amount=amount, lifetime=2.6, play="pick", size=0.07, rise=rise,
                spread=spread, drift=0.9, blend="add", fade="out", color=[1.0, 0.55, 0.2], turn=200.0, lift=lift)


def light(energy, reach, flicker=0.35, color=None):
    return dict(type="light", color=color or [1.0, 0.6, 0.28], energy=energy, range=reach, flicker=flicker)


def flash(energy, reach, seconds=0.5):
    return dict(type="light", color=[1.0, 0.72, 0.4], energy=energy, range=reach, flash=seconds)


def ring(size=9.0, seconds=0.6, tex="ring_02"):
    return dict(type="particles", texture=tex, amount=1, lifetime=seconds, play="one", size=1.0, grow=size, blend="add",
                fade="out", flat=True, lift=0.15, color=[1.0, 0.88, 0.7, 0.45])


def debris(amount=24, throw=7.0):
    return dict(type="particles", texture="debris_bits_01", amount=amount, lifetime=2.4, play="pick", size=0.2, burst=throw,
                gravity=9.8, one_shot=True, lit=True, turn=420.0, color=[0.45, 0.43, 0.4])


def sparks(amount=40, throw=9.0):
    return dict(type="particles", texture="glow_warm_02", amount=amount, lifetime=1.1, play="one", size=0.07, burst=throw,
                gravity=6.0, one_shot=True, blend="add", fade="out", color=[1.0, 0.75, 0.4])


COMPOSITES = {
    # ---- fire you stand beside
    "campfire": dict(loop=True, about="A campfire: flames, embers going up, thin smoke, and its light.", layers=[
        book("flame_loop_03", lifetime=2.1, size=1.5, lift=0.6, blend="add"),
        book("flame_loop_01", lifetime=2.1, size=1.1, lift=0.5, blend="add", color=[1, 0.9, 0.8, 0.8]),
        embers(18, 0.3), smoke("smoke_roll_04", 10, 6.0, 0.6, 2.4, 1.3, [1, 1, 1, 0.35], lift=1.2), light(3.2, 9.0)]),
    "campfire_small": dict(loop=True, about="A small cooking fire, hardly any smoke.", layers=[
        book("flame_loop_06", lifetime=2.1, size=0.9, lift=0.38, blend="add"), embers(8, 0.2, 1.0), light(1.8, 6.0)]),
    "bonfire": dict(loop=True, about="A big fire: tall flames, a lot of embers, a heavy column of smoke.", layers=[
        book("flame_loop_04", lifetime=2.1, size=3.4, lift=3.2, blend="add", color=FIRE),
        book("flame_loop_03", lifetime=2.1, size=3.6, lift=1.5, blend="add"),
        book("flame_loop_06", lifetime=1.7, size=2.6, lift=1.1, blend="add"),
        embers(50, 1.0, 2.2, 0.6), smoke("smoke_roll_07", 22, 9.0, 2.0, 3.4, 1.9, [1, 1, 1, 0.75], lift=3.5, spread=0.6),
        light(7.0, 20.0)]),
    "torch": dict(loop=True, about="A torch flame: narrow, restless, a little smoke off the tip.", layers=[
        book("flame_loop_02", lifetime=4.2, size=0.5, lift=0.26, blend="add"), embers(5, 0.06, 0.8, 0.3),
        smoke("wisp_smoke_02", 6, 2.5, 0.2, 2.5, 0.8, [1, 1, 1, 0.3], lift=0.5, spread=0.03), light(1.6, 7.0, 0.4)]),
    "candle": dict(loop=True, about="A candle flame.", layers=[
        book("candle_loop_01", lifetime=4.2, size=0.09, lift=0.05, blend="add"), light(0.5, 3.0, 0.15, [1.0, 0.72, 0.42])]),
    "brazier": dict(loop=True, about="A bowl of fire: broad low flames and sparks.", layers=[
        book("flame_loop_06", lifetime=2.1, size=1.4, lift=0.55, blend="add"),
        book("flame_loop_05", lifetime=2.4, size=1.2, lift=0.9, blend="add", color=FIRE), embers(14, 0.35), light(2.6, 9.0)]),
    "wall_of_fire": dict(loop=True, about="A line of fire 6 m long (along x). Scale it for more.", layers=[
        dict(type="particles", texture="flame_loop_03", amount=9, lifetime=2.1, play="through", size=2.0, lift=0.8,
             blend="add", line=6.0),
        dict(type="particles", texture="flame_loop_04", amount=7, lifetime=2.1, play="through", size=2.0, lift=1.8,
             blend="add", line=6.0, color=FIRE),
        dict(embers(40, 0.3, 1.8), line=6.0), light(5.0, 14.0)]),
    "ground_fire": dict(loop=True, about="Low fire licking over a patch of ground 3 m across.", layers=[
        dict(type="particles", texture="wisp_flame_03", amount=40, lifetime=0.8, play="pick", size=0.6, grow=0.5, rise=1.4,
             spread=1.5, blend="add", fade="in_out", color=FIRE, turn=30.0),
        dict(type="particles", texture="flame_loop_02", amount=10, lifetime=4.2, play="through", size=0.6, lift=0.3,
             blend="add", spread=1.4),
        smoke("smoke_roll_08", 8, 5.0, 0.8, 2.6, 1.0, [1, 1, 1, 0.3], lift=0.6, spread=1.2), light(2.4, 9.0)]),
    "burning_tree": dict(loop=True, about="Fire up something tall (8 m): flames along its height, smoke off the top.", layers=[
        dict(type="particles", texture="flame_loop_03", amount=10, lifetime=2.1, play="through", size=2.2, blend="add",
             column=8.0),
        dict(type="particles", texture="flame_loop_04", amount=6, lifetime=2.1, play="through", size=2.4, blend="add",
             column=8.0, color=FIRE),
        dict(embers(50, 0.8, 2.4), column=8.0), smoke("smoke_dark_01", 20, 9.0, 2.2, 3.2, 2.2, [1, 1, 1, 0.8], lift=8.0, spread=0.7),
        light(6.0, 18.0)]),
    "ignite": dict(loop=False, seconds=3.3, about="Something catching fire: a line of flame that grows up.", layers=[
        book("flame_ignite_01", lifetime=3.3, size=1.6, lift=0.7, blend="add"), flash(3.0, 7.0, 3.3)]),
    "flare_up": dict(loop=False, seconds=1.6, about="A sudden gout of flame, as when fat hits a fire.", layers=[
        book("flame_puff_01", lifetime=1.6, size=2.2, lift=1.2, blend="add"), embers(20, 0.3, 2.4), flash(4.0, 8.0, 1.0)]),
    "magic_flame": dict(loop=True, about="Cold blue-white fire.", layers=[
        book("flame_loop_05", lifetime=2.4, size=1.3, lift=0.9, blend="add", color=[0.45, 0.75, 1.0]),
        dict(type="particles", texture="wisp_flame_04", amount=10, lifetime=1.1, play="pick", size=0.5, grow=0.5, rise=1.3,
             spread=0.25, blend="add", fade="in_out", color=[0.5, 0.8, 1.0], turn=30.0),
        light(2.4, 8.0, 0.3, [0.5, 0.75, 1.0])]),
    "fireball": dict(loop=True, about="A thrown fireball: move the node; it leaves fire and smoke behind it.", layers=[
        book("fire_burst_06", lifetime=1.3, size=1.3, blend="add"),
        dict(type="particles", texture="wisp_flame_03", amount=24, lifetime=0.5, play="pick", size=0.7, grow=0.3,
             blend="add", fade="out", color=FIRE, world=True, turn=60.0),
        dict(type="particles", texture="puff_soft_02", amount=16, lifetime=1.6, play="one", size=0.5, grow=2.6, fade="out",
             color=SMOKE + [0.5], lit=True, world=True),
        light(4.0, 9.0, 0.2)]),
    "embers": dict(loop=True, about="Embers alone, drifting up from a hot bed.", layers=[embers(30, 0.6, 1.2)]),
    # ---- smoke
    "smoke_column": dict(loop=True, about="A tall column of grey smoke, as off a chimney or a wreck.", layers=[
        smoke("smoke_roll_02", 22, 10.0, 1.2, 3.6, 1.8)]),
    "smoke_column_black": dict(loop=True, about="Thick black smoke, as off burning oil.", layers=[
        smoke("smoke_dark_01", 24, 10.0, 1.4, 3.4, 1.9, [0.55, 0.55, 0.55, 0.95])]),
    "smoke_thin": dict(loop=True, about="A thin thread of smoke off something smouldering.", layers=[
        smoke("wisp_smoke_03", 10, 5.0, 0.25, 3.0, 0.9, [1, 1, 1, 0.45], spread=0.04)]),
    "chimney_smoke": dict(loop=True, about="Pale smoke leaning with the wind (along +x).", layers=[
        dict(smoke("smoke_roll_05", 16, 7.0, 0.6, 3.2, 1.0, [1, 1, 1, 0.5]), wind=[0.9, 0.0, 0.0])]),
    "smoulder": dict(loop=True, about="What is left of a fire: faint smoke and a few embers.", layers=[
        smoke("wisp_smoke_02", 8, 5.0, 0.4, 2.8, 0.7, [1, 1, 1, 0.4], spread=0.3), embers(5, 0.3, 0.6),
        light(0.5, 3.0, 0.5, [1.0, 0.4, 0.15])]),
    "steam_vent": dict(loop=True, about="Steam forced up out of the ground.", layers=[
        dict(type="particles", texture="steam_loop_01", amount=18, lifetime=2.4, play="through", size=0.5, grow=3.0, rise=3.2,
             spread=0.1, drift=0.4, fade="in_out", color=[1, 1, 1, 0.5], lit=True)]),
    "ground_fog": dict(loop=True, about="Low smoke or mist lying over a patch 8 m across.", layers=[
        dict(type="particles", texture="puff_soft_07", amount=30, lifetime=8.0, play="one", size=2.5, grow=1.6, rise=0.05,
             spread=4.0, drift=0.25, fade="in_out", color=[0.8, 0.82, 0.85, 0.3], lit=True, turn=6.0, lift=0.5)]),
    "dust_cloud": dict(loop=False, seconds=3.0, about="A cloud of dust thrown up and settling.", layers=[
        dict(type="particles", texture="smoke_burst_05", amount=10, lifetime=3.0, play="through", size=1.4, grow=2.2,
             burst=1.6, one_shot=True, fade="out", lit=True, color=[0.66, 0.6, 0.5, 0.7], lift=0.5)]),
    "footfall_dust": dict(loop=False, seconds=0.9, about="The scuff a foot or a dropped thing kicks up.", layers=[
        dict(type="particles", texture="dust_bits_01", amount=6, lifetime=0.9, play="pick", size=0.35, grow=2.0, burst=0.7,
             one_shot=True, fade="out", lit=True, color=[0.62, 0.56, 0.48, 0.5], lift=0.1)]),
    "smoke_puff": dict(loop=False, seconds=1.5, about="One puff of smoke, as from a snuffed flame or a shot.", layers=[
        book("smoke_burst_03", lifetime=1.5, size=1.6, lift=0.4, lit=True, color=[0.8, 0.8, 0.8, 0.8])]),
    "smoke_ring_burst": dict(loop=False, seconds=2.4, about="Smoke thrown outward in a ring.", layers=[
        dict(type="particles", texture="puff_soft_03", amount=1, lifetime=2.4, play="one", size=2.0, grow=4.0, fade="out",
             flat=True, lift=0.4, color=SMOKE + [0.7], lit=True),
        ring(7.0, 0.5, "ring_cloud_01")]),
    # ---- explosions
    "explosion_small": dict(loop=False, seconds=2.2, about="A small explosion: a grenade, a pot of powder.", layers=[
        book("blast_05", lifetime=2.2, size=4.0, lift=1.1), ring(6.0, 0.45), sparks(30, 7.0), debris(12, 5.0),
        flash(12.0, 14.0, 0.45)]),
    "explosion_medium": dict(loop=False, seconds=2.6, about="A barrel going up.", layers=[
        book("blast_07", lifetime=2.5, size=7.0, lift=2.0), book("fire_burst_03", lifetime=1.2, size=4.5, lift=1.4, blend="add"),
        ring(10.0, 0.55), sparks(50, 10.0), debris(26, 8.0), flash(20.0, 24.0, 0.6)]),
    "explosion_large": dict(loop=False, seconds=4.0, about="A big one, with a column of smoke left standing after it.", layers=[
        book("blast_02", lifetime=2.9, size=12.0, lift=3.6), book("fire_burst_04", lifetime=1.6, size=8.0, lift=2.6, blend="add"),
        ring(18.0, 0.7), ring(12.0, 1.1, "ring_cloud_01"), sparks(80, 14.0), debris(44, 12.0),
        dict(smoke("smoke_dark_01", 14, 4.0, 3.0, 2.4, 2.2, [0.6, 0.6, 0.6, 0.9], lift=3.0, spread=1.5), one_shot=True),
        flash(34.0, 40.0, 0.8)]),
    "explosion_fiery": dict(loop=False, seconds=2.2, about="Mostly fire: fuel, a firebomb.", layers=[
        book("blast_14", lifetime=2.2, size=8.0, lift=2.2), book("fire_burst_01", lifetime=1.0, size=5.0, lift=1.6, blend="add"),
        dict(embers(60, 1.5, 3.0), one_shot=True), flash(22.0, 24.0, 0.7)]),
    "explosion_smoky": dict(loop=False, seconds=3.0, about="Mostly smoke and dirt: a charge under earth.", layers=[
        book("blast_18", lifetime=2.4, size=7.0, lift=2.0), book("blast_15", lifetime=2.6, size=8.0, lift=2.4),
        book("dust_streak_01", lifetime=1.6, size=9.0, lift=0.5, lit=True), debris(40, 9.0), flash(8.0, 14.0, 0.3)]),
    "explosion_sparks": dict(loop=False, seconds=1.4, about="A crack and a shower of sparks, no fireball.", layers=[
        book("spark_burst_01", lifetime=0.6, size=3.4, blend="add", color=[1.0, 0.85, 0.6]), sparks(90, 12.0),
        ring(5.0, 0.3), flash(10.0, 12.0, 0.25)]),
    "explosion_magic": dict(loop=False, seconds=1.4, about="A blue-white burst, for something unnatural going off.", layers=[
        book("burst_white_01", lifetime=1.0, size=5.0, lift=1.2, blend="add", color=[0.5, 0.8, 1.0]),
        ring(11.0, 0.6), dict(type="light", color=[0.5, 0.75, 1.0], energy=18.0, range=20.0, flash=0.6)]),
    "airburst": dict(loop=False, seconds=2.4, about="An explosion in the air: no ring on the ground, no debris.", layers=[
        book("blast_11", lifetime=2.4, size=7.0), book("fire_burst_02", lifetime=1.2, size=4.0, blend="add"), sparks(40, 9.0),
        flash(18.0, 26.0, 0.5)]),
    "impact_fire": dict(loop=False, seconds=1.0, about="A fireball landing: a splash of flame and sparks.", layers=[
        book("fire_burst_05", lifetime=1.0, size=3.0, lift=0.8, blend="add"), sparks(24, 6.0), ring(4.0, 0.3),
        flash(8.0, 10.0, 0.35)]),
    "shockwave": dict(loop=False, seconds=0.8, about="The ring alone: a blast felt, not seen.", layers=[
        ring(16.0, 0.8), ring(9.0, 0.5, "ring_01")]),
    "muzzle_flash": dict(loop=False, seconds=0.35, about="A short hard flash with a lick of smoke, along x.", layers=[
        dict(type="particles", texture="glow_streak_01", amount=1, lifetime=0.12, play="one", size=1.2, blend="add",
             fade="out", align="x"),
        book("smoke_burst_06", lifetime=0.9, size=0.8, lit=True, color=[0.8, 0.8, 0.8, 0.5]), flash(6.0, 8.0, 0.1)]),
    "debris_burst": dict(loop=False, seconds=2.4, about="Chunks and dust thrown out, no fire: something breaking.", layers=[
        debris(34, 7.0),
        dict(type="particles", texture="smoke_burst_05", amount=6, lifetime=2.0, play="through", size=1.0, grow=2.2,
             burst=1.2, one_shot=True, fade="out", lit=True, color=[0.62, 0.58, 0.52, 0.7], lift=0.4)]),
}


def main(src_dir, out_dir):
    src, out = Path(src_dir), Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    found = {p.name: p for p in src.rglob("*") if p.is_file()}
    textures = {}
    for file, name, cols, rows, kind, read in SHEETS:
        if file not in found:
            print("missing:", file)
            continue
        limit = 3072 if kind.startswith("blast") and cols == 12 else 2048
        im = convert(found[file], read, limit)
        target = out / (name + ".webp")
        im.save(target, "WEBP", quality=88, method=4, exact=True)
        textures[name] = dict(file=name + ".webp", cols=cols, rows=rows, kind=kind, width=im.size[0], height=im.size[1],
                              cell_w=round(im.size[0] / cols), cell_h=round(im.size[1] / rows),
                              bytes=target.stat().st_size)
    effects = {}
    for name, t in textures.items():
        made = basic(name, t)
        if made is not None:
            effects[name] = made
    for name, made in COMPOSITES.items():
        effects[name] = made
    for name, e in effects.items():
        for layer in e["layers"]:
            if layer["type"] == "particles" and layer["texture"] not in textures:
                raise SystemExit("%s wants %s, which is not there" % (name, layer["texture"]))
    (out / "fx_catalogue.json").write_text(json.dumps(dict(textures=textures, effects=effects), indent=1))
    # ---- the catalogue for people
    group_of = lambda n, e: ("Fire" if any(k in n for k in ("fire", "flame", "torch", "candle", "brazier", "ignite", "flare",
                                                             "bonfire", "ember", "wisp_flame", "glow", "burning"))
                             else "Explosions" if any(k in n for k in ("blast", "explosion", "burst", "shock", "ring", "impact",
                                                                       "muzzle", "airburst", "debris", "spark"))
                             else "Smoke and dust")
    lines = ["# Effects catalogue", "",
             "Every effect in `assets/fx/fx_catalogue.json`. Spawn one by name:", "",
             "```gdscript", "Fx.spawn(self, \"campfire\", Vector3(10, 0, 4))          # stays until freed",
             "Fx.spawn(self, \"explosion_large\", hit_point, 1.5)     # plays once and frees itself; 1.5 = half as big again",
             "```", "",
             "Looping effects stay until you free the node they return (or call `Fx.stop(node)`, which lets the smoke",
             "already in the air drift away first). One-shots free themselves. Sizes are in metres at scale 1.",
             "Pictures of all of them: `docs/fx/` (made by `tests/RENDER_fx_gallery.gd`).", "",
             "This file and the JSON are written by `tools/build_fx_library.py`; edit the effects there.", ""]
    for group in ("Fire", "Smoke and dust", "Explosions"):
        for made_by, title in ((True, "composed effects"), (False, "one per texture")):
            rows_ = [(n, e) for n, e in effects.items() if group_of(n, e) == group and (n in COMPOSITES) == made_by]
            if not rows_:
                continue
            lines += ["## %s: %s" % (group, title), "", "| Effect | Kind | Lasts | What it is | Textures |", "|---|---|---|---|---|"]
            for n, e in sorted(rows_):
                used = sorted({l["texture"] for l in e["layers"] if l["type"] == "particles"})
                lines.append("| `%s` | %s | %s | %s | %s |" % (n, "loops" if e["loop"] else "one-shot",
                             "until freed" if e["loop"] else "%.1f s" % e["seconds"], e["about"], ", ".join(used)))
            lines.append("")
    lines += ["## Textures", "", "| Texture | Grid | Frames | Size | Kind |", "|---|---|---|---|---|"]
    for n, t in sorted(textures.items()):
        lines.append("| `%s` | %d x %d | %d | %d x %d | %s |" % (n, t["cols"], t["rows"], t["cols"] * t["rows"], t["width"],
                                                               t["height"], t["kind"]))
    Path("docs").mkdir(exist_ok=True)
    Path("docs/FX_CATALOGUE.md").write_text("\n".join(lines) + "\n")
    total = sum(t["bytes"] for t in textures.values())
    print("%d textures (%.1f MB), %d effects (%d composed)" % (len(textures), total / 1e6, len(effects), len(COMPOSITES)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

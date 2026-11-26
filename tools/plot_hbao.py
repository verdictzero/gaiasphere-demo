"""A drawing of how the game's HBAO works (shaders/SHADER_ambient_occlusion.gdshader, method 3).

    python3 tools/plot_hbao.py renders/hbao_explained.png
"""
import sys, numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Arc, FancyArrowPatch

INK, MUTED, GROUND, EDGE = "#1f2328", "#6b7280", "#e9e1d3", "#8a7a63"
BLUE, ORANGE, RED = "#2563eb", "#c2410c", "#b91c1c"
fig = plt.figure(figsize=(13, 9.6))
fig.patch.set_facecolor("white")
gs = fig.add_gridspec(2, 2, height_ratios=[1.25, 1], width_ratios=[1, 1.55], hspace=0.28, wspace=0.12)
a = fig.add_subplot(gs[0, 0]); b = fig.add_subplot(gs[0, 1]); c = fig.add_subplot(gs[1, :])


def bare(ax):
    ax.set_xticks([]); ax.set_yticks([])
    for s in ax.spines.values(): s.set_visible(False)


# ---------------------------------------------------------------- 1: on the screen
bare(a); a.set_aspect("equal"); a.set_xlim(-1.5, 1.6); a.set_ylim(-1.55, 1.75)
a.set_title("1  On the screen: where it looks", loc="left", fontsize=13, color=INK)
a.add_patch(Circle((0, 0), 1.0, fc="#f3f6fb", ec=BLUE, lw=1.2, ls=(0, (4, 3))))
DIRS, STEPS, spin = 6, 4, 0.35
for d in range(DIRS):
    ang = spin + d * 2 * np.pi / DIRS
    u = np.array([np.cos(ang), np.sin(ang)])
    a.plot([0, u[0]], [0, u[1]], color=MUTED, lw=0.8)
    for k in range(1, STEPS + 1):
        p = u * (k - 0.35) / STEPS
        hot = d == 0
        a.plot(*p, "o", ms=7 if hot else 5.5, mfc=ORANGE if hot else "white", mec=ORANGE if hot else MUTED, mew=1.3, zorder=4)
a.plot(0, 0, "o", ms=10, mfc=INK, mec="white", mew=1.5, zorder=5)
a.annotate("the pixel", (0, 0), (-1.2, -1.32), fontsize=9.5, color=INK, ha="center", arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))
a.annotate("the radius, as it comes out\non screen at this distance", (0.5, -0.87), (0.35, -1.38), fontsize=9.5, color=BLUE, ha="center",
           arrowprops=dict(arrowstyle="-", color=BLUE, lw=0.8))
u0 = np.array([np.cos(spin), np.sin(spin)])
a.annotate("one direction:\nits 4 steps are\ndrawn in section\non the right", u0 * 0.9, (1.3, 1.25), fontsize=9.5, color=ORANGE, ha="center",
           arrowprops=dict(arrowstyle="-", color=ORANGE, lw=0.8))
a.text(-1.45, 1.72, "6 directions x 4 steps = 24 depth reads.\nThe fan is turned a different way at\nevery pixel, so the gaps do not show\nas a pattern.", fontsize=9.5, color=INK, va="top")

# ---------------------------------------------------------------- 2: in section
bare(b); b.set_aspect("equal"); b.set_xlim(-1.2, 6.6); b.set_ylim(-2.1, 3.75)
b.set_title("2  In section, along that direction: how high the horizon stands", loc="left", fontsize=13, color=INK)
x = np.linspace(-1.2, 6.6, 800)
h = np.where(x < 1.6, 0.0, 0.0) + 2.3 / (1 + np.exp(-(x - 2.7) * 3.2)) + 0.25 * np.exp(-((x - 5.2) / 0.5) ** 2)
b.fill_between(x, h, -2.1, color=GROUND, lw=0)
b.plot(x, h, color=EDGE, lw=2)
P = np.array([0.0, 0.0])
taps = [np.array([t, np.interp(t, x, h)]) for t in (0.75, 1.9, 3.05, 4.2)]
b.plot([-1.1, 1.3], [0, 0], color=MUTED, lw=1, ls=(0, (2, 3)))
b.annotate("the surface's own plane\nat the pixel (dotted)", (0.9, 0.0), (0.2, 2.9), fontsize=9, color=MUTED, ha="center", arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.6))
b.add_patch(FancyArrowPatch(P, P + [0, 1.25], arrowstyle="-|>", mutation_scale=13, color=INK, lw=1.4))
b.text(-0.12, 1.3, "its normal", fontsize=9.5, color=INK, ha="right")
top = 0.1
for i, t in enumerate(taps):
    v = t - P
    rise = v[1] / np.hypot(*v)
    raised = rise > top
    b.plot([P[0], t[0]], [P[1], t[1]], color=RED if raised else MUTED, lw=1.6 if raised else 0.9, ls="-" if raised else (0, (3, 3)), zorder=3)
    b.plot(*t, "o", ms=8, mfc=ORANGE, mec="white", mew=1.2, zorder=5)
    off = [(0.0, -0.36), (0.0, -0.36), (0.42, -0.1), (0.0, 0.2)][i]
    b.text(t[0] + off[0], t[1] + off[1], f"step {i + 1}", fontsize=9, color=ORANGE, ha="center")
    if raised:
        top = rise
b.plot(*P, "o", ms=10, mfc=INK, mec="white", mew=1.5, zorder=6)
b.text(-0.15, -0.36, "the pixel's point", fontsize=9.5, color=INK, ha="right")
best = taps[2] - P
ang = np.degrees(np.arctan2(best[1], best[0]))
b.add_patch(Arc(P, 2.4, 2.4, theta1=0, theta2=ang, color=RED, lw=1.6))
b.annotate("the horizon: this much\nsky is shut off", (1.16, 0.3), (3.55, 0.55), fontsize=9.5, color=RED, va="center", arrowprops=dict(arrowstyle="-", color=RED, lw=0.8))
b.add_patch(Arc(P, 2.4, 2.4, theta1=ang, theta2=90, color=BLUE, lw=1.6))
b.text(0.5, 1.45, "this much\nis open", fontsize=9.5, color=BLUE)
b.add_patch(Circle(P, 3.4, fc="none", ec=BLUE, lw=1, ls=(0, (4, 3))))
b.text(-1.1, -0.75, "Each step reads the depth there and asks how far its point stands over the\npixel's plane, as an angle. Only a step that RAISES the horizon adds shade\n(steps 2 and 3 here); step 4 is lower than the horizon already found, and adds none.",
       fontsize=9.5, color=INK, va="top")
b.annotate("the radius: past it a point counts\nfor less, then for nothing", (3.4 * np.cos(1.25), 3.4 * np.sin(1.25)), (2.6, 3.45), fontsize=9, color=BLUE, ha="left", va="center",
           arrowprops=dict(arrowstyle="-", color=BLUE, lw=0.8))

# ---------------------------------------------------------------- 3: the sum
bare(c); c.set_xlim(0, 13); c.set_ylim(0, 4)
c.set_title("3  What is done with it", loc="left", fontsize=13, color=INK)
boxes = [
    (0.1, "Rebuild the surface", "The Mobile renderer keeps no normals,\nso the pixel's point and its normal are\nworked out from the depth buffer and\nits slope to the neighbouring pixels."),
    (3.35, "March each direction", "For every step: height over the plane\n(as a sine). If it beats the horizon so\nfar, add the gain, weighted by how\nnear it is. A tap off screen ends the\nmarch: it is no evidence of anything."),
    (6.6, "Average and shape", "Mean over the directions, times the\nintensity; raised to the contrast;\nfaded out toward the far limit; never\ndarker than the floor."),
    (9.85, "Darken the frame", "One pass over the finished picture,\nmultiplied in before the water and\nthe particles: creases, the feet of\nthings and cracks go darker."),
]
for i, (x0, head, body) in enumerate(boxes):
    c.add_patch(plt.Rectangle((x0, 0.9), 3.0, 2.75, fc="#f6f7f9", ec="#d1d5db", lw=1))
    c.text(x0 + 0.15, 3.35, head, fontsize=11, color=INK, weight="bold", va="center")
    c.text(x0 + 0.15, 3.0, body, fontsize=9.3, color=INK, va="top", linespacing=1.45)
    if i < 3:
        c.add_patch(FancyArrowPatch((x0 + 3.02, 2.25), (x0 + 3.33, 2.25), arrowstyle="-|>", mutation_scale=12, color=MUTED, lw=1.2))
c.text(0.1, 0.5, "The settings, in the graphics menu:  AO radius (the circle)   HBAO directions and steps (the fan)   AO bias (how far over the plane a point must stand to count)\n"
       "AO depth falloff (how soon past the radius it stops counting)   AO intensity and contrast   AO reaches (the far limit)   AO darkest allowed (the floor)",
       fontsize=9.3, color=MUTED, va="center", linespacing=1.5)
fig.suptitle("Horizon-based ambient occlusion (HBAO), as this game does it", x=0.012, ha="left", fontsize=15, color=INK, y=0.985)
fig.savefig(sys.argv[1], dpi=150, bbox_inches="tight", pad_inches=0.25)

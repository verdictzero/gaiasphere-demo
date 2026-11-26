"""Draws the shuttle's crash in section from tests/DUMP_crash_section.gd's output.

    godot --headless --path . --script res://tests/DUMP_crash_section.gd | grep "^META\\|^ROW" > section.txt
    python3 tools/plot_crash_section.py section.txt renders/crash_section.png
"""
import sys, numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

meta, rows = {}, []
for line in open(sys.argv[1]):
    if line.startswith("META"):
        meta = {k: float(v) for k, v in (kv.split("=") for kv in line.split()[1:])}
    elif line.startswith("ROW"):
        rows.append([float(v) for v in line[4:].split(",")])
d, skid, beside = np.array(rows).T
L = meta["level"]
skid, beside = skid - L, beside - L          # metres over the water
shore = d[np.argmax(skid > 0)]               # where the skid's ground leaves the water
INK, MUTED, WATER, EARTH, CHURN, GRASS, HULL = "#1f2328", "#6b7280", "#8ec5e8", "#e9e1d3", "#8a5a33", "#5b8c3a", "#c2410c"
SIZE = 1.25                                  # the wreck's scale
# The bed's fall under it, as SCRIPT_crashed_shuttle.gd takes it: off its two ends.
PITCH = np.degrees(np.arctan2(np.interp(4.4 * SIZE, d, skid) - np.interp(-4.4 * SIZE, d, skid), 8.8 * SIZE))
LEN, TALL = 8.8 * SIZE, 3.3 * SIZE           # the hull, about: it is drawn as a box


def panel(ax, lo, hi, zoom):
    m = (d >= lo) & (d <= hi)
    ax.fill_between(d[m], np.minimum(skid[m], 0), 0, color=WATER, alpha=0.55, lw=0, zorder=1)
    ax.fill_between(d[m], skid[m], -40, color=EARTH, lw=0, zorder=2)
    ax.plot(d[m], beside[m], color=MUTED, lw=1.3, ls=(0, (4, 3)), zorder=3)
    g = m & (d > 0) & (d < meta["gouge"])
    ax.plot(d[m], skid[m], color=GRASS, lw=2.2, zorder=4)
    ax.plot(d[g], skid[g], color=CHURN, lw=3.2, zorder=5)
    ax.plot(d[m & (d <= shore)], skid[m & (d <= shore)], color="#b9a888", lw=2.2, zorder=4)
    ax.axhline(0, color="#2f7fb5", lw=1.2, zorder=3, xmax=(shore - lo) / (hi - lo))
    # the wreck: its tail up the shelf, its nose out and down
    rest = max((np.interp(4.4 * SIZE, d, skid) + np.interp(-4.4 * SIZE, d, skid)) / 2, np.interp(0.0, d, skid) - 0.4)
    c = np.array([0.0, rest - 0.4 + TALL * 0.5])
    t = np.radians(PITCH)
    ux, uy = np.array([-np.cos(t), -np.sin(t)]), np.array([-np.sin(t), np.cos(t)])
    box = [c + ux * a * LEN / 2 + uy * b * TALL / 2 for a, b in [(-1, -1), (1, -1), (1, 1), (-1, 1)]]
    ax.add_patch(Polygon(box, closed=True, fc=HULL, ec=INK, lw=1, zorder=6, joinstyle="round"))
    top = max(p[1] for p in box)
    ax.set_xlim(lo, hi)
    for s in ("top", "right"): ax.spines[s].set_visible(False)
    for s in ("left", "bottom"): ax.spines[s].set_color("#d1d5db")
    ax.tick_params(colors=MUTED, labelsize=9)
    ax.set_ylabel("metres over the water", color=MUTED)
    return top


fig, (a, b) = plt.subplots(2, 1, figsize=(13, 9.5), gridspec_kw={"height_ratios": [1, 1.25]})
fig.patch.set_facecolor("white")

top = panel(a, -70, 330, False)
a.set_ylim(-16, max(skid.max(), beside.max()) + 12)
a.set_aspect(2.0)
a.set_title("The crash, in section along the skid (heights drawn at twice their scale)", loc="left", fontsize=13, color=INK, pad=10)
mc, mr = meta["meadow_up"], meta["meadow_r"]
ytop = np.interp(mc, d, skid)
a.annotate("", (mc - mr, ytop + 6), (mc + mr, ytop + 6), arrowprops=dict(arrowstyle="<->", color=GRASS, lw=1.3))
a.text(mc, ytop + 7.5, f"the meadow: {2 * mr:.0f} m across, its top {ytop:.1f} m over the water", ha="center", color=GRASS, fontsize=9.5)
a.annotate(f"the skid begins\n{meta['gouge']:.0f} m from the wreck", (meta["gouge"], np.interp(meta["gouge"], d, skid)), (meta["gouge"] + 30, np.interp(meta["gouge"], d, skid) - 13),
           fontsize=9.5, color=INK, ha="center", arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))
a.annotate(f"the shore\n{shore:.0f} m from the wreck", (shore, 0), (shore - 22, 16), fontsize=9.5, color=INK, ha="center", arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))
a.annotate("the wreck", (0, top), (-18, 12), fontsize=9.5, color=INK, ha="center", arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))
slope = np.degrees(np.arctan(np.gradient(skid, d)))
land = (d > shore) & (d < mc - mr * 0.45)
a.text((shore + mc - mr * 0.45) / 2 + 12, np.interp((shore + mc) / 2, d, skid) - 14,
       f"the climb: {slope[land].mean():.0f}° on average,\n{slope[land].max():.0f}° at its steepest", ha="center", color=INK, fontsize=9.5)
a.text(322, np.interp(322, d, beside) + 2.5, "the ground 25 m\nbeside the skid", color=MUTED, fontsize=9, ha="right")
a.text(120, np.interp(120, d, skid) - 5, "the skid: churned earth", color=CHURN, fontsize=9.5)

top = panel(b, -40, 90, True)
b.set_ylim(-19, 13)
b.set_aspect("equal")
b.set_title("Where it lies (to scale)", loc="left", fontsize=13, color=INK, pad=8)
b.set_xlabel("metres back along the skid from the wreck (the mere's middle is to the left)", color=MUTED)
bed = np.interp(0.0, d, skid)
b.annotate("", (-26, 0), (-26, np.interp(-26, d, skid)), arrowprops=dict(arrowstyle="<->", color="#2f7fb5", lw=1.2))
b.text(-25, np.interp(-26, d, skid) / 2, f"{-np.interp(-26, d, skid):.1f} m of water\nover the bed", color="#2f7fb5", fontsize=9.5, va="center")
b.annotate("", (0, 0), (0, top), arrowprops=dict(arrowstyle="<->", color=INK, lw=1.2))
b.text(1, top / 2, f"about {-top:.1f} m of water\nover its highest point", color=INK, fontsize=9.5, va="center")
b.text(0, bed - 1.6, f"the wreck, about {LEN:.0f} m long,\non the bed {-bed:.1f} m down,\nin its divot", ha="center", va="top", color=INK, fontsize=9.5)
b.annotate("the shelf", (shore - 8, np.interp(shore - 8, d, skid)), (shore - 4, -13), fontsize=9.5, color=INK, ha="center", arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))
b.annotate("the skid comes out of the water\nand on up the shore", (shore + 12, np.interp(shore + 12, d, skid)), (shore + 6, 9), fontsize=9.5, color=CHURN, ha="center",
           arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))
b.text(-39, 0.6, "the mere's surface", color="#2f7fb5", fontsize=9.5)
fig.tight_layout()
fig.savefig(sys.argv[2], dpi=150)
print("shore %.0f  bed %.1f  hull top %.1f  climb mean %.1f max %.1f  meadow top %.1f" % (shore, bed, top, slope[land].mean(), slope[land].max(), ytop))

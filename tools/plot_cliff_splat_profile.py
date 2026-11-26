import numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection

def ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

# --- the rules, as the code has them
def face(deg):            # terrain shader: rock by angle (cliff_face 0.875 -> 0.845)
    return 1 - ss(0.845, 0.875, np.cos(np.radians(deg)))
def splat_rock(deg):      # field's vertex splat: slope 0.42 -> 0.60
    return ss(0.42, 0.60, np.tan(np.radians(deg)))
def strata_model(deg):    # models: sides only (normal.y 0.8 -> 0.45)
    return 1 - ss(0.45, 0.8, np.cos(np.radians(deg)))
A = lambda s: np.degrees(np.arctan(s))
TREES, GRASS, MODELS = A(0.40), A(0.52), A(0.63)
F0, F1 = np.degrees(np.arccos(0.875)), np.degrees(np.arccos(0.845))

GRASS_C, ROCK_C, INK, MUTED = "#5b8c3a", "#4a4f57", "#1f2328", "#6b7280"
fig, (ax, bx) = plt.subplots(2, 1, figsize=(11, 10.5), gridspec_kw={"height_ratios": [1.7, 1]})
fig.patch.set_facecolor("white")

# --- top: a hillside in section, its steepness rising to a wall and easing off
x = np.linspace(0, 96, 4000)
ang = np.interp(x, [0, 8, 62, 74, 84, 96], [3, 12, 58, 58, 6, 3])
y = np.cumsum(np.tan(np.radians(ang))) * (x[1] - x[0])
f = face(ang)
cols = [tuple(np.array(matplotlib.colors.to_rgb(GRASS_C)) * (1 - k) + np.array(matplotlib.colors.to_rgb(ROCK_C)) * k) for k in f]
pts = np.column_stack([x, y]).reshape(-1, 1, 2)
ax.fill_between(x, y, -3, color="#efe9df", zorder=0)
ax.add_collection(LineCollection(np.concatenate([pts[:-1], pts[1:]], axis=1), colors=cols[:-1], linewidths=7, capstyle="round"))
# strata beds, where the terrain draws them (side weight = max(model's, face))
side = np.maximum(strata_model(ang), f)
for h in np.arange(1.5, y.max(), 2.6):
    i = np.argmin(np.abs(y - h))
    if side[i] > 0.5:
        ax.plot([x[i] - 2.6, x[i] - 0.4], [h, h + 0.05], color=ROCK_C, lw=1, alpha=0.55)
def mark(deg, rising, text, dy, dx=0.0):
    idx = np.where((ang[:-1] < deg) & (ang[1:] >= deg))[0] if rising else np.where((ang[:-1] > deg) & (ang[1:] <= deg))[0]
    i = idx[0]
    ax.plot(x[i], y[i], "o", ms=7, mfc="white", mec=INK, mew=1.5, zorder=5)
    ax.annotate(text, (x[i], y[i]), (x[i] + dx, y[i] + dy), fontsize=9.5, color=INK, ha="center",
                arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))
mark(TREES, True, f"trees stop\n{TREES:.0f}°", 12, -6)
mark(GRASS, True, f"grass and ferns stop\n{GRASS:.0f}°", 19, -4)
mark(F0, True, f"rock begins\n{F0:.0f}°", -9, 5)
mark(F1, True, f"all rock; cliff models\nfrom here, {F1:.0f}°", -9, 17)
mark(F1, False, f"rock ends at the brow\nas it began, {F1:.0f}° to {F0:.0f}°", 9, -14)
i = np.argmin(np.abs(x - 60))
ax.text(x[i] + 2, y[i] - 4, "the face: rock laid on from\nthe side, with its beds", fontsize=9.5, color=INK, va="center")
ax.text(1, y[100] + 9, "easy ground:\ngrass, ferns, trees", fontsize=9.5, color=GRASS_C)
ax.text(87, y[-1] + 2.5, "the top:\ngrass again", fontsize=9.5, color=GRASS_C)
ax.set_xlim(0, 96); ax.set_ylim(-3, y.max() + 9); ax.set_aspect("equal")
ax.set_title("A hillside in section: what the ground is drawn as, by how steep it is", loc="left", fontsize=13, color=INK, pad=10)
ax.set_xlabel("metres across", color=MUTED); ax.set_ylabel("metres up", color=MUTED)

# --- bottom: the weights against the angle
d = np.linspace(0, 70, 1400)
bx.axvspan(F0, F1, color=ROCK_C, alpha=0.10, lw=0)
bx.plot(d, face(d), color=ROCK_C, lw=6, alpha=0.85, solid_capstyle="butt")
bx.plot(d, splat_rock(d), color="#b45309", lw=2, ls=(0, (5, 3)))
bx.plot(d, np.maximum(strata_model(d), face(d)), color="#7fb0ff", lw=1.6)
bx.plot(d, strata_model(d), color="#2563eb", lw=2, ls=(0, (1.5, 2.5)))
bx.text(33.3, 1.05, "cliff rock by angle, per pixel (thick): this decides.\nStrata on the terrain follow it exactly (thin, inside)", color=ROCK_C, fontsize=9.5, va="bottom")
bx.text(21.5, 0.56, "the field's own rock\nsplat (per vertex,\nunderneath)", color="#b45309", fontsize=9.5, ha="right")
bx.text(52.5, 0.42, "strata on a cliff model\n(its own sides only)", color="#2563eb", fontsize=9.5)
for deg, name in [(TREES, "trees stop"), (GRASS, "grass, ferns stop"), (MODELS, "cliff models from")]:
    bx.axvline(deg, color=MUTED, lw=1, ls=(0, (2, 3)))
for deg, name, yy in [(TREES, "trees stop", 0.16), (GRASS, "grass, ferns stop", 0.04), (MODELS, "cliff models from", 0.16)]:
    bx.text(deg + (0.5 if deg > 30 else -0.5), yy, f"{name} {deg:.0f}°", color=INK, fontsize=9, ha="left" if deg > 30 else "right")
bx.set_xlim(0, 70); bx.set_ylim(0, 1.25); bx.set_xticks(range(0, 71, 10)); bx.set_yticks([0, 0.5, 1])
bx.set_xlabel("steepness of the ground, degrees from level", color=MUTED); bx.set_ylabel("share (0 none, 1 all)", color=MUTED)
bx.set_title("The same rules, as weights", loc="left", fontsize=13, color=INK, pad=8)
for a in (ax, bx):
    for s in ("top", "right"): a.spines[s].set_visible(False)
    for s in ("left", "bottom"): a.spines[s].set_color("#d1d5db")
    a.tick_params(colors=MUTED, labelsize=9)
bx.grid(axis="y", color="#eceff3", lw=0.8)
fig.tight_layout()
fig.savefig("/home/user/west_virginia/renders/cliff_splat_profile.png", dpi=150)

"""Cut the RemZ crest (the shield with the zombie deer) out of godot/icon.png for the loading screen.

The icon is a 1024 px picture: the shield in front of a moonlit church and zombie silhouettes. The
loading screen wants the shield alone on its dark ink, so this traces the shield's outer rim, keeps
everything inside it at full resolution, drops the backdrop and lays a soft red glow around the rim
in place of the one the backdrop carried.

Rim tracing: the upper sides and the top edge are the lit metal border (bright, found by scanning in
from outside), the lower sides and the tip carry an orange glow line. Blood drips hang off the lower
rim; where they fool the scan (lower left around y 790-860 and the whole lower right) the outline comes
from points read off zoomed crops and from the mirrored left side (the shield is symmetric to 3-5 px).

    python tools/build_crest.py            -> godot/assets/ui/remz_crest.png
    python tools/build_crest.py --preview  also writes tools/out/crest_preview.png and crest_outline.png
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "godot" / "icon.png"
TARGET = ROOT / "godot" / "assets" / "ui" / "remz_crest.png"
OUT = ROOT / "tools" / "out"
INK = (0.043, 0.06, 0.08)            # Hud.INK, the loading screen's backdrop
GLOW = (0.80, 0.14, 0.05)
SUPER = 4                            # supersampling of the outline raster
EDGE_OFFSET = 1.0                    # the mask ends this many px outside the traced rim line...
FEATHER = 1.5                        # ...and fades out over this many px
GLOW_SIGMA = 9.0
GLOW_STRENGTH = 0.62
THRESHOLD = 0.45

TOP_LEFT = (109.0, 68.0)
TOP_RIGHT = (884.0, 72.0)
TIP = (499.0, 936.0)
AXIS_LOW = 503.0                     # mirror axis of the lower sides (perspective drifts it from 497)
# Lower left rim, read off a 3x crop with a 10 px grid: the drips below it fool the scan.
LOWER_LEFT = [(180.0, 715.0), (199.0, 737.0), (220.0, 757.0), (250.0, 787.0), (280.0, 813.0),
              (320.0, 837.0), (360.0, 860.0)]


def load():
    rgb = np.asarray(Image.open(SOURCE).convert("RGB")).astype(np.float64) / 255.0
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    # lit metal is bright, the glow line is strongly red with little blue
    score = np.maximum(lum, 0.8 * rgb[..., 0] * (rgb[..., 2] < 0.45))
    return rgb, score


def robust(values, window=9, limit=4.0):
    """Median-filter a scanned edge and drop samples that jump away from it (drips, cracks)."""
    values = np.asarray(values, dtype=np.float64)
    med = ndimage.median_filter(values, size=window, mode="nearest")
    keep = np.abs(values - med) <= limit
    return keep, med


def scan_top(score):
    xs = np.arange(int(TOP_LEFT[0]) + 4, 851, 2)
    guess = np.interp(xs, [TOP_LEFT[0], 520.0, TOP_RIGHT[0]], [TOP_LEFT[1], 24.0, TOP_RIGHT[1]])
    found = []
    for x, g in zip(xs, guess):
        ys = [y for y in range(int(g) - 12, int(g) + 13) if score[y, x] > THRESHOLD]
        found.append(min(ys) if ys else g)
    keep, med = robust(found)
    return [(float(x), float(y if k else m)) for x, y, k, m in zip(xs, found, keep, med)]


def scan_side(score, ys, guess_x, outermost):
    found = []
    for y, g in zip(ys, guess_x):
        xs = [x for x in range(int(g) - 20, int(g) + 21) if score[y, x] > THRESHOLD]
        found.append((min(xs) if outermost == "min" else max(xs)) if xs else g)
    keep, med = robust(found)
    return [float(x if k else m) for x, k, m in zip(found, keep, med)]


def scan_bottom(score, xs, guess_y):
    found = []
    for x, g in zip(xs, guess_y):
        ys = [y for y in range(int(g) - 14, int(g) + 15) if score[y, x] > THRESHOLD]
        found.append(max(ys) if ys else g)
    keep, med = robust(found)
    return [float(y if k else m) for y, k, m in zip(found, keep, med)]


def outline(score):
    top = scan_top(score)
    # left side, straight metal edge then the start of the curve (scan), then the read-off lower arc
    ys = np.arange(72, 711, 2)
    guess = np.interp(ys, [68, 460, 500, 560, 600, 650, 700, 710], [109, 109, 111, 120, 129, 148, 174, 178])
    left_x = scan_side(score, ys, guess, "min")
    left = [(x, float(y)) for x, y in zip(left_x, ys)] + LOWER_LEFT
    # bottom left arm into the tip: the glow line is clean here, scan it from below
    # (the last 10 px before the tip are left to the straight run into TIP: a drip hangs there)
    bxs = np.arange(366, 490, 2)
    b_guess = np.interp(bxs, [360, 400, 450, 499], [860, 887, 913, 936])
    bottom_left = [(float(x), y) for x, y in zip(bxs, scan_bottom(score, bxs, b_guess))]
    # right side: the moon sits behind the top corner, so the straight part starts below it
    ys = np.arange(200, 731, 2)
    guess = np.interp(ys, [200, 480, 520, 560, 600, 650, 700, 730], [883, 882, 879, 875, 866, 849, 831, 813])
    right_x = scan_side(score, ys, guess, "max")
    right = [(TOP_RIGHT[0], TOP_RIGHT[1]), (883.5, 140.0)] + [(x, float(y)) for x, y in zip(right_x, ys)]
    # lower right: drips everywhere, mirror the lower left arc and scan only the clean arm near the tip
    right += [(2.0 * AXIS_LOW - x, y) for x, y in LOWER_LEFT if y > 735.0]
    bxs = np.arange(510, 641, 2)
    b_guess = np.interp(bxs, [499, 550, 610, 640], [936, 910, 876, 858])
    bottom_right = [(float(x), y) for x, y in zip(bxs, scan_bottom(score, bxs, b_guess))]

    ring = [TOP_LEFT] + top + [TOP_RIGHT] + right[1:] + bottom_right[::-1] + [TIP] + bottom_left[::-1] + left[::-1]
    return smooth_ring(ring)


def smooth_ring(points, passes=2):
    """Light moving average along the ring; the corners and the tip stay where they are."""
    pts = np.asarray(points, dtype=np.float64)
    fixed = {0}
    for i, p in enumerate(pts):
        if np.allclose(p, TOP_RIGHT) or np.allclose(p, TIP): fixed.add(i)
    for _ in range(passes):
        out = pts.copy()
        for i in range(len(pts)):
            if i in fixed: continue
            out[i] = (pts[i - 1] + 2.0 * pts[i] + pts[(i + 1) % len(pts)]) / 4.0
        pts = out
    return pts


def build(preview=False):
    rgb, score = load()
    ring = outline(score)
    h, w = score.shape
    big = Image.new("L", (w * SUPER, h * SUPER), 0)
    ImageDraw.Draw(big).polygon([(x * SUPER, y * SUPER) for x, y in ring], fill=255)
    inside = np.asarray(big) > 127
    # distance (in source px) from the traced rim outwards; the mask reaches EDGE_OFFSET and feathers
    dist = ndimage.distance_transform_edt(~inside) / SUPER
    alpha_big = np.clip((EDGE_OFFSET + FEATHER - dist) / FEATHER, 0.0, 1.0)
    alpha = alpha_big.reshape(h, SUPER, w, SUPER).mean(axis=(1, 3))

    glow = ndimage.gaussian_filter(alpha, GLOW_SIGMA)
    glow = np.clip(glow / max(glow.max(), 1e-6), 0.0, 1.0) * GLOW_STRENGTH
    out_a = alpha + glow * (1.0 - alpha)
    colour = np.empty_like(rgb)
    for c in range(3):
        colour[..., c] = (rgb[..., c] * alpha + GLOW[c] * glow * (1.0 - alpha)) / np.maximum(out_a, 1e-6)

    if preview:
        OUT.mkdir(parents=True, exist_ok=True)
        full = colour * out_a[..., None] + np.array(INK) * (1.0 - out_a[..., None])
        Image.fromarray(np.round(full * 255.0).astype(np.uint8), "RGB").save(OUT / "crest_preview_full.png")
    ys, xs = np.nonzero(out_a > 1.5 / 255.0)
    y0, y1 = max(ys.min() - 2, 0), min(ys.max() + 3, h)
    x0, x1 = max(xs.min() - 2, 0), min(xs.max() + 3, w)
    rgba = np.dstack([colour, out_a])[y0:y1, x0:x1]
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.round(rgba * 255.0).astype(np.uint8), "RGBA").save(TARGET, optimize=True)
    print(f"{TARGET.relative_to(ROOT)}: {x1 - x0} x {y1 - y0} px, shield {ring[:, 0].min():.0f}..{ring[:, 0].max():.0f} x "
          f"{ring[:, 1].min():.0f}..{ring[:, 1].max():.0f} in the icon, {len(ring)} outline points")

    if preview:
        OUT.mkdir(parents=True, exist_ok=True)
        cut = rgba[..., :3] * rgba[..., 3:4] + np.array(INK) * (1.0 - rgba[..., 3:4])
        Image.fromarray(np.round(cut * 255.0).astype(np.uint8), "RGB").save(OUT / "crest_preview.png")
        debug = Image.open(SOURCE).convert("RGB")
        ImageDraw.Draw(debug).line([tuple(p) for p in ring] + [tuple(ring[0])], fill=(0, 255, 255), width=1)
        debug.save(OUT / "crest_outline.png")


if __name__ == "__main__":
    build("--preview" in sys.argv)

"""Cuts tileable PBR-ish textures out of the user's site photos (Fotos for map creation with annotation/).
Regions are given in the 1000 px wide thumbnail frame (photos are 2576 px wide, EXIF-rotated);
ground regions are trapezoids (perspective) warped to squares. The map inset (bottom right) is never touched.
Outputs godot/assets/textures/ph_<name>_albedo.jpg, _normal.jpg, _rough.jpg (1024 px, seamless).
Also generates leaf/needle card sprites for the procedural trees (godot/assets/sprites/leaf_*.png).
Usage: python tools/photo_textures.py
"""
import os, math
import numpy as np
from PIL import Image, ImageOps, ImageFilter, ImageDraw
from scipy import ndimage
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PH = os.path.join(ROOT, "Fotos for map creation with annotation")
TEX = os.path.join(ROOT, "godot", "assets", "textures")
SPR = os.path.join(ROOT, "godot", "assets", "sprites")
S = 2576 / 1000.0
rng = np.random.default_rng(3)

def photo(n):
    f = [x for x in os.listdir(PH) if x.startswith("%02d_" % n)][0]
    return ImageOps.exif_transpose(Image.open(os.path.join(PH, f))).convert("RGB")

def quad(im, tl, tr, br, bl, size=1024, height=0):
    # PIL QUAD transform takes the source quad for the destination rectangle
    q = [c * S for c in (*tl, *bl, *br, *tr)]
    return im.transform((size, height if height else size), Image.QUAD, q, Image.BICUBIC)

def rect(im, x0, y0, x1, y1, size=1024):
    return im.crop((int(x0 * S), int(y0 * S), int(x1 * S), int(y1 * S))).resize((size, size), Image.LANCZOS)

def seamless(im, border=0.22):
    """offset by half and blend with a centre-weighted mask so all four edges tile"""
    a = np.asarray(im).astype(np.float32)
    h, w = a.shape[:2]
    off = np.roll(np.roll(a, h // 2, 0), w // 2, 1)
    y = np.linspace(0, 1, h)[:, None]; x = np.linspace(0, 1, w)[None, :]
    def ramp(t):
        return np.clip(np.minimum(t, 1 - t) / border, 0, 1)
    m = (ramp(y) * ramp(x))[:, :, None]
    m = m * m * (3 - 2 * m)
    return Image.fromarray(np.clip(off * (1 - m) + a * m, 0, 255).astype(np.uint8))

def equalize_light(im, sigma=90):
    """remove large-scale lighting gradients (shadows of branches on the ground)"""
    a = np.asarray(im).astype(np.float32)
    lum = a.mean(axis=2)
    low = ndimage.gaussian_filter(lum, sigma)
    gain = (low.mean() / np.maximum(low, 1))[:, :, None]
    gain = np.clip(gain, 0.6, 1.6)
    return Image.fromarray(np.clip(a * gain, 0, 255).astype(np.uint8))

def normal_from(im, strength=2.5, blur=1.2):
    lum = ndimage.gaussian_filter(np.asarray(im.convert("L")).astype(np.float32) / 255.0, blur)
    gx = np.roll(lum, -1, 1) - np.roll(lum, 1, 1)
    gy = np.roll(lum, -1, 0) - np.roll(lum, 1, 0)
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(lum)   # OpenGL convention (+Y up), matches Godot
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / l, ny / l, nz / l], axis=2)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))

def rough_from(im, base=0.85, amount=0.15):
    lum = np.asarray(im.convert("L")).astype(np.float32) / 255.0
    r = np.clip(base - (lum - lum.mean()) * amount, 0.3, 1.0)
    return Image.fromarray((r * 255).astype(np.uint8)).convert("RGB")

def save_set(name, im, strength=2.5, rough=0.85, tile=True, light=True):
    if light:
        im = equalize_light(im)
    if tile:
        im = seamless(im)
    im.save(os.path.join(TEX, f"ph_{name}_albedo.jpg"), quality=92)
    normal_from(im, strength).save(os.path.join(TEX, f"ph_{name}_normal.jpg"), quality=92)
    rough_from(im, rough).save(os.path.join(TEX, f"ph_{name}_rough.jpg"), quality=85)
    print("texture", name)

# ---- ground surfaces (trapezoids: top edge is farther away)
p20 = photo(20)
save_set("gravel", quad(p20, (200, 590), (640, 590), (700, 745), (60, 745)), 3.0, 0.9)
p1 = photo(1)
save_set("asphalt", quad(p1, (330, 660), (600, 660), (700, 748), (200, 748)), 1.6, 0.8)
p14 = photo(14)
save_set("forestfloor", quad(p14, (120, 560), (600, 560), (700, 748), (0, 748)), 3.0, 0.92)
p5 = photo(5)
save_set("meadow", quad(p5, (60, 600), (330, 600), (330, 690), (0, 690)), 2.0, 0.9)
# ---- bark: vertical strips, tiled vertically (trunk UV wraps around: width = circumference)
p14b = quad(p14, (196, 120), (262, 120), (246, 390), (158, 390), 512, 1024)     # leaning trunk: parallelogram
save_set("bark_beech", p14b, 3.5, 0.9)
p16 = photo(16)
p16b = quad(p16, (155, 100), (238, 100), (248, 420), (140, 420), 512, 1024)
save_set("bark_ivy", p16b, 3.5, 0.9)
p24 = photo(24)
p24b = quad(p24, (392, 340), (440, 340), (452, 500), (383, 500), 512, 1024)
save_set("bark_oak", p24b, 3.5, 0.9)
p13 = photo(13)
p13b = quad(p13, (514, 110), (560, 110), (568, 400), (505, 400), 512, 1024)
save_set("bark_beech2", p13b, 3.5, 0.9)
# ---- buildings
p17 = photo(17)
save_set("cladding", ImageOps.autocontrast(quad(p17, (350, 325), (560, 335), (560, 410), (350, 405), 1024), cutoff=1), 1.8, 0.7)      # red-brown boards, Waldhütte
save_set("concrete", quad(p14, (420, 398), (570, 398), (570, 475), (420, 475), 1024), 1.5, 0.85)      # concrete base (photo 14, south face)
p12 = photo(12)
save_set("corrugated", quad(p12, (135, 262), (280, 250), (280, 395), (135, 400), 512).filter(ImageFilter.GaussianBlur(0.8)), 1.5, 0.55)     # brown sheet metal, Holzlager
# ---- foliage colour samples for the leaf cards (photo 19 undergrowth, 24 oak crown, 01 spruce)
def sample_colors(im, box, n=6):
    a = np.asarray(im.crop((int(box[0] * S), int(box[1] * S), int(box[2] * S), int(box[3] * S)))).reshape(-1, 3)
    a = a[(a[:, 1] > a[:, 0]) & (a[:, 1] > a[:, 2] * 1.1) & (a[:, 1] > 45) & (a[:, 1] < 150)]
    return a[rng.choice(len(a), n)]
beech_cols = sample_colors(photo(19), (150, 250, 600, 500), 12)
oak_cols = sample_colors(p24, (400, 60, 800, 300), 12)
spruce_cols = sample_colors(p1, (560, 60, 980, 300), 12)

def leaf_card(name, cols, n_leaves, leaf_w, leaf_h, needle=False, size=512):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = size / 2, size / 2
    for i in range(n_leaves):
        # denser towards the middle, thinning to the border so cards blend
        r = size * 0.5 * math.sqrt(rng.random()) * 0.98
        a = rng.random() * math.tau
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        c = cols[rng.integers(len(cols))].astype(float) * rng.uniform(0.75, 1.2)
        c = tuple(int(v) for v in np.clip(c, 0, 255)) + (255,)
        rot = rng.random() * math.tau
        if needle:
            # a twig: short line with needles
            L = leaf_w * rng.uniform(0.7, 1.3)
            dx, dy = math.cos(rot) * L, math.sin(rot) * L
            d.line([(x - dx, y - dy), (x + dx, y + dy)], fill=(70, 50, 30, 255), width=2)
            for k in range(14):
                t = rng.uniform(-1, 1)
                px, py = x + dx * t, y + dy * t
                na = rot + math.pi / 2 * (1 if k % 2 else -1) + rng.uniform(-0.6, 0.6)
                nl = leaf_h * rng.uniform(0.6, 1.0)
                d.line([(px, py), (px + math.cos(na) * nl, py + math.sin(na) * nl)], fill=c, width=3)
        else:
            w, h = leaf_w * rng.uniform(0.7, 1.2), leaf_h * rng.uniform(0.7, 1.2)
            pts = []
            for k in range(10):
                t = k / 10 * math.tau
                # leaf outline: pointed ellipse
                ex, ey = math.cos(t) * h / 2, math.sin(t) * w / 2 * (1 - 0.35 * abs(math.cos(t)))
                pts.append((x + ex * math.cos(rot) - ey * math.sin(rot), y + ex * math.sin(rot) + ey * math.cos(rot)))
            d.polygon(pts, fill=c)
            d.line([pts[0], pts[5]], fill=tuple(int(v * 0.7) for v in c[:3]) + (255,), width=1)
    # soft shading: darker towards the lower part of the card
    a = np.asarray(im).astype(np.float32)
    grad = np.linspace(1.12, 0.78, size)[:, None, None]
    a[:, :, :3] = np.clip(a[:, :, :3] * grad, 0, 255)
    # bleed colour into transparent pixels so mip-mapped edges do not go dark
    alpha = a[:, :, 3] > 0
    for c in range(3):
        ch = a[:, :, c]
        filled = ndimage.gaussian_filter(ch * alpha, 3) / np.maximum(ndimage.gaussian_filter(alpha.astype(np.float32), 3), 1e-3)
        a[:, :, c] = np.where(alpha, ch, filled)
    Image.fromarray(a.astype(np.uint8)).save(os.path.join(SPR, f"leaf_{name}.png"))
    print("leaf card", name)

leaf_card("beech", beech_cols, 420, 26, 40)
leaf_card("oak", oak_cols, 380, 30, 44)
leaf_card("spruce", spruce_cols, 420, 30, 15, needle=True)

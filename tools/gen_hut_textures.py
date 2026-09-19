"""Procedural PBR sets for the Waldhütte look (photos 14, 17): horizontal red-brown tongue-and-groove boards
(ph_boards_*), plus higher-resolution leaf card sprites for beech and oak crowns (leaf_beech / leaf_oak: twig
clusters with veined ovate leaves, September colours with a few yellowing leaves).
Usage: python tools/gen_hut_textures.py   then   Godot.exe --headless --path godot --import
"""
import os, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "godot", "assets", "textures")
SPR = os.path.join(ROOT, "godot", "assets", "sprites")
rng = np.random.default_rng(19)

def normal_from_height(h, strength=2.0):
    gy, gx = np.gradient(h)
    n = np.dstack([-gx * strength, -gy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8), "RGB")

def boards():
    S = 2048
    # 9 boards per tile (~11 cm each on a 1 m tile), each with its own grain phase and slight colour shift
    nb = 9
    x = np.linspace(0, 1, S, endpoint=False)
    yy, xx = np.mgrid[0:S, 0:S] / S
    board = np.floor(yy * nb)
    fy = yy * nb - board                                  # 0..1 inside the board
    # grain: long streaks along x, low-frequency wobble in y
    grain = np.zeros((S, S))
    for k in range(6):
        f = rng.uniform(40, 140); ph = rng.uniform(0, 6.28); amp = rng.uniform(0.3, 1.0) / (k + 1)
        grain += amp * np.sin(xx * f * 2 * math.pi + ph + np.sin(yy * rng.uniform(20, 60)) * 1.5 + board * 2.1)
    grain += 0.35 * rng.standard_normal((S, S))
    grain = (grain - grain.min()) / (grain.max() - grain.min())
    per_board = rng.uniform(-0.06, 0.06, nb)[board.astype(int)]
    base = np.array([0.40, 0.185, 0.125])                # red-brown paint, sRGB target of photo 14
    albedo = np.empty((S, S, 3))
    for c in range(3):
        albedo[:, :, c] = base[c] * (0.85 + 0.3 * grain) * (1.0 + per_board)
    # groove: dark line at the top of every board, light bevel just below it
    groove = np.exp(-((fy - 0.02) ** 2) / (2 * 0.008 ** 2))
    bevel = np.exp(-((fy - 0.07) ** 2) / (2 * 0.012 ** 2))
    albedo *= (1.0 - 0.55 * groove)[:, :, None]
    albedo *= (1.0 + 0.12 * bevel)[:, :, None]
    # weathering: slightly greyer streaks running down from the grooves
    streak = np.clip(np.sin(xx * 97.0 + board * 3.0) * 0.5 + 0.5, 0, 1) ** 6 * (1 - fy) * 0.12
    albedo = albedo * (1 - streak[:, :, None]) + streak[:, :, None] * 0.35
    albedo = np.clip(albedo, 0, 1)
    Image.fromarray((albedo * 255).astype(np.uint8), "RGB").save(os.path.join(TEX, "ph_boards_albedo.jpg"), quality=92)
    height = 0.02 * grain - 0.6 * groove + 0.15 * bevel
    normal_from_height(height * 40.0, 1.0).save(os.path.join(TEX, "ph_boards_normal.jpg"), quality=92)
    rough = np.clip(0.62 + 0.15 * grain + 0.25 * groove, 0, 1)
    Image.fromarray((rough * 255).astype(np.uint8), "L").convert("RGB").save(os.path.join(TEX, "ph_boards_rough.jpg"), quality=90)
    print("boards ok")

def leaf_shape(w, h, kind):
    """polygon of an ovate (beech) or lobed (oak) leaf in a w x h box, tip up"""
    pts = []
    n = 48
    for i in range(n + 1):
        t = i / n                                         # 0 base .. 1 tip
        if kind == "beech":
            r = math.sin(t * math.pi) ** 0.75
            if t > 0.85:
                r *= max(0.0, 1 - (t - 0.85) / 0.15) ** 0.6 + 0.05
        else:
            r = math.sin(t * math.pi) ** 0.9 * (0.72 + 0.28 * abs(math.sin(t * math.pi * 4.5)))
        pts.append((r * w / 2, t * h))
    left = [(-x, y) for x, y in reversed(pts[1:-1])]
    return pts + left

def leaves(kind, name, palette, autumn):
    S = 1024
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hgt = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(img)
    dh = ImageDraw.Draw(hgt)
    random.seed(7 if kind == "beech" else 11)
    cx, cy = S / 2, S / 2
    # twig clusters: a few main twigs radiating from the centre with leaves along them
    for tw in range(34):
        a = random.uniform(0, 2 * math.pi)
        L = random.uniform(0.16, 0.44) * S
        r0 = random.uniform(0.0, 0.16) * S
        sx, sy = cx + math.cos(a + random.uniform(-1.0, 1.0)) * r0, cy + math.sin(a + random.uniform(-1.0, 1.0)) * r0
        ex, ey = sx + math.cos(a) * L, sy + math.sin(a) * L
        d.line([(float(sx), float(sy)), (float(ex), float(ey))], fill=(70, 52, 34, 255), width=random.randint(3, 6))
        nl = random.randint(8, 13)
        for k in range(nl):
            t = (k + 0.5) / nl
            px, py = sx + (ex - sx) * t, sy + (ey - sy) * t
            side = 1 if k % 2 == 0 else -1
            ang = a + side * random.uniform(0.7, 1.25) + random.uniform(-0.2, 0.2)
            size = random.uniform(0.06, 0.105) * S * (1.15 - 0.35 * t)
            lw, lh = size * (0.62 if kind == "beech" else 0.7), size
            col = random.choice(palette)
            if random.random() < autumn:
                col = (random.randint(170, 215), random.randint(140, 175), random.randint(40, 70))
            shade = random.uniform(0.75, 1.1)
            col = tuple(int(min(255, c * shade)) for c in col)
            poly = leaf_shape(lw, lh, kind)
            rot = ang - math.pi / 2
            pts = [(float(px + x * math.cos(rot) - y * math.sin(rot)), float(py + x * math.sin(rot) + y * math.cos(rot))) for x, y in poly]
            d.polygon(pts, fill=col + (255,))
            dh.polygon(pts, fill=int(140 + 100 * random.random()))
            # midrib and veins
            tip = (float(px - lh * math.sin(rot)), float(py + lh * math.cos(rot)))
            mid = (float(px), float(py))
            dark = tuple(int(c * 0.72) for c in col) + (255,)
            d.line([mid, tip], fill=dark, width=1)
            nv = 5 if kind == "beech" else 4
            for v in range(1, nv + 1):
                tv = v / (nv + 1)
                bx, by = px + (tip[0] - px) * tv, py + (tip[1] - py) * tv
                vl = lw * 0.48 * math.sin(tv * math.pi) ** 0.5
                for sgn in (-1, 1):
                    vx = bx + sgn * vl * math.cos(rot) - vl * 0.55 * (-math.sin(rot))
                    vy = by + sgn * vl * math.sin(rot) - vl * 0.55 * math.cos(rot)
                    d.line([(float(bx), float(by)), (float(vx), float(vy))], fill=dark, width=1)
    # soft edge: slight blur of alpha only, keep colour crisp
    a = img.split()[3].filter(ImageFilter.GaussianBlur(0.8))
    img.putalpha(a)
    img.save(os.path.join(SPR, name + ".png"))
    print(name, "ok")

if __name__ == "__main__":
    boards()
    leaves("beech", "leaf_beech", [(96, 138, 52), (88, 126, 46), (112, 150, 62), (76, 112, 40), (104, 142, 58)], 0.08)
    leaves("oak", "leaf_oak", [(84, 118, 46), (72, 104, 40), (96, 128, 56), (66, 96, 38)], 0.06)

"""Recolours the green leaf textures of the Poly Haven trees into autumn tones (in place, keeps *_green originals)."""
import os, sys, glob
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PH = os.path.join(ROOT, "godot", "assets", "ph")
# tree -> (hue target in degrees, saturation mult, value mult)
PLAN = {"island_tree_01": (24, 1.9, 1.45), "island_tree_02": (8, 1.8, 1.3), "island_tree_03": (42, 1.8, 1.55), "jacaranda_tree": (34, 1.9, 1.5), "tree_small_02": (16, 1.9, 1.4)}
def recolor(path, hue, smul, vmul):
    orig = path.replace(".jpg", "_green.jpg")
    if not os.path.exists(orig):
        os.replace(path, orig)
    img = Image.open(orig).convert("RGB")
    h, s, v = img.convert("HSV").split()
    hp = h.load(); sp = s.load(); vp = v.load()
    w, hgt = img.size
    target = int(hue / 360 * 255)
    for y in range(hgt):
        for x in range(w):
            hv = hp[x, y]
            if 20 <= hv <= 120 and sp[x, y] > 25:  # greenish pixels
                # keep some variation: hue offset relative to green centre
                hp[x, y] = max(0, min(255, target + (hv - 70) // 4))
                sp[x, y] = min(255, int(sp[x, y] * smul))
                vp[x, y] = min(255, int(vp[x, y] * vmul))
    Image.merge("HSV", (h, s, v)).convert("RGB").save(path, quality=92)
for tree, (hue, smul, vmul) in PLAN.items():
    for p in glob.glob(os.path.join(PH, tree, "textures", "*leaves*diff*.jpg")):
        if p.endswith("_green.jpg"): continue
        recolor(p, hue, smul, vmul); print("autumn", os.path.basename(p))
    if tree == "jacaranda_tree":
        for p in glob.glob(os.path.join(PH, tree, "textures", "*diff*.jpg")):
            if "leaves" in p or p.endswith("_green.jpg"): continue
            print("skip", os.path.basename(p))

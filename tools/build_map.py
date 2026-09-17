"""Builds the Waldhütte Remetschwil map data for the game from input/geo (see geo_fetch.py).
Outputs (committed, loaded by godot/scripts/map.gd):
  godot/assets/map/heightmap.f32   float32 LE, rows = z (south), cols = x (east), 1 m grid, metres above origin
  godot/assets/map/ground.png      R = forest floor, G = meadow, B = gravel (0..255), same grid
  godot/assets/map/map.json        extent, roads, buildings, campsite objects, fence, spawns, barricades, trees
  tools/out/map_preview.png        aerial + overlays for checking
  tools/out/terrain_viewer.html    standalone 3D viewer of the terrain (three.js)
Coordinates: x east, z south, origin = Feuerstelle (OSM node 427671292), heights relative to the origin.
Usage: python tools/build_map.py
"""
import os, json, math, base64, io, struct
import numpy as np, tifffile
from PIL import Image, ImageDraw
from scipy import ndimage
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEO = os.path.join(ROOT, "input", "geo")
OUT = os.path.join(ROOT, "godot", "assets", "map")
TOUT = os.path.join(ROOT, "tools", "out")
os.makedirs(OUT, exist_ok=True); os.makedirs(TOUT, exist_ok=True)
E0, N0 = 2668013.58, 1251408.66          # LV95 of the origin
X0, X1, Z0, Z1 = -300, 150, -260, 160    # local extent (m)
W, H = X1 - X0, Z1 - Z0
rng = np.random.default_rng(7)

# ------------------------------------------------------------------ layout (true north up; x east, z south)
ROADS = [
    {"name": "Sennhofstrasse", "surface": "asphalt", "width": 4.2,
     "pts": [[56, -316], [81, -221], [106, -67], [124, 21], [137, 114], [146, 150], [160, 195]]},
    {"name": "Weg zur Hütte", "surface": "gravel", "width": 3.4,
     "pts": [[124, 21], [100, 32], [70, 41], [53, 47.5], [30, 54.5], [7, 61]]},
    {"name": "Waldweg zwischen Hütten", "surface": "gravel", "width": 4.5,
     "pts": [[7, 61], [6, 44], [6.5, 30], [5, 18], [3, 12]]},
    {"name": "Waldweg nach Hütte (Oberer Sorchen)", "surface": "gravel", "width": 3.2,
     "pts": [[1, -22], [-8, -34], [-29, -49], [-33, -56], [-57, -112], [-69, -141], [-73, -152], [-80, -173], [-97, -207], [-115, -247], [-125, -275]]},
    {"name": "Weg Richtung Dorf", "surface": "gravel", "width": 3.2,
     "pts": [[7, 61], [-7.5, 65], [-45, 71], [-62, 72], [-67, 75], [-190, 132], [-275, 171]]},
    {"name": "Feldweg West", "surface": "dirt", "width": 2.8,
     "pts": [[-62, 72], [-66, 60], [-76, 45], [-88, 25], [-114, -18], [-134, -60], [-161, -96], [-166, -108], [-194, -181]]},
    {"name": "Wiesenweg", "surface": "dirt", "width": 2.8,
     "pts": [[7, 61], [8, 76], [11, 85], [22, 118], [40, 165]]},
    {"name": "Fussweg Nord", "surface": "dirt", "width": 1.6,
     "pts": [[-73, -152], [-66, -154], [-47, -168], [-20, -176]]},
]
# gravel clearing around the fire, the aprons of both huts
# Kiesplatz: fire plaza north-west of the Waldhütte (photos 13, 14, 15, 20), the track between the huts, both aprons
CLEARING = [[-14, -24], [0, -28], [10, -24], [15, -14], [14, -0.8], [6.2, 0.2], [5.6, 8.5], [7, 18], [13, 40], [11, 58], [3, 63], [0, 44], [-1, 20], [-6, 10], [-14, 2], [-18, -10]]
MEADOW_FORCE = [[-70, 78], [-8, 68], [12, 64], [30, 58], [55, 51], [90, 36], [125, 29], [150, 29], [150, 160], [-70, 160]]
# Waldhütte (OSM way 36785519): garage door in the west face, outside stair along the north face rising east to the
# upper door, east side buried in the slope (photos 14, 17, 19)
WALDHUETTE = {"pos": [9.1, 4.6], "size": [6.6, 7.4], "yaw_deg": -8.0, "base_h": 2.4, "wall_h": 2.5, "roof_h": 1.9}
HOLZLAGER = {"pos": [-2.5, 27.0], "size": [7.9, 14.6], "yaw_deg": -23.0, "base_h": 0.6, "wall_h": 3.6, "roof_h": 1.6}
# fire plaza ~7 m north of the hut's north face; table west of the fire, fountain / bin / signpost at the north
# track entrance (photos 15, 16, 18, 20, 21). Origin stays the OSM picnic node.
FIRE = [4.0, -7.0]
BENCHES = [[4.0, -3.7, 0.0], [4.0, -10.3, 0.0], [0.7, -7.0, 90.0], [7.3, -7.0, 90.0]]   # x, z, yaw (length axis)
TABLE = [-3.0, -9.0, 20.0]
FOUNTAIN = [-4.5, -16.0, 75.0]
BIN = [-1.5, -19.0]
SIGNPOST = [3.0, -21.0]
LOG_SEAT = [-9.0, -12.0, 60.0]
LANDMARK_OAK = [66.0, 34.0]
BIG_TREES = [[1.5, 0.8, "beech", 1.35], [-8.0, -21.0, "beech", 1.25], [12.0, -12.0, "beech", 1.2], [-10.0, 6.0, "beech", 1.15],
             [-20.5, -9.0, "oak", 1.2], [14.5, 63.5, "oak", 1.25], [0.5, 66.5, "beech", 1.2], [-9.0, 14.0, "beech", 1.1],
             [14.0, -3.0, "spruce", 1.2], [-8.0, 42.0, "beech", 1.1], [12.5, 30.0, "beech", 1.15]]
# pasture fence on the meadow side of the tracks (gap at the Wiesenweg gate)
FENCE = [[[121, 27], [100, 35], [70, 44], [53, 50.5], [30, 57.5], [13, 64]], [[1, 66], [-7.5, 68], [-45, 74], [-62, 75], [-67, 78], [-120, 100]],
         [[128, 30], [140, 112], [149, 150]]]
SPAWNS = {"north": [[112, 28], [118, 8], [104, 31]], "east": [[32, 100], [58, 96], [18, 112]],
          "south": [[-78, 80], [-96, 88], [-70, 77]], "west": [[-44, -86], [-56, -108], [-40, -72]]}
BARRICADES = [
    {"id": "ne", "name": "Weg zur Hütte", "pos": [28, 55], "yaw": -1.19, "segments": 2},
    {"id": "e", "name": "Wiesentor", "pos": [7, 66], "yaw": 0.0, "segments": 2},
    {"id": "s", "name": "Weg Richtung Dorf", "pos": [-16, 66.5], "yaw": -1.55, "segments": 2},
    {"id": "w", "name": "Waldweg Nord", "pos": [-7, -33], "yaw": 0.68, "segments": 2},
]
PLAYER_START = [1.0, -4.0]
BOUNDS = [-250, -230, 390, 370]   # x, z, w, d playable

# ------------------------------------------------------------------ helpers
def poly_mask(pts, grow=0.0):
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    d.polygon([(x - X0, z - Z0) for x, z in pts], fill=255)
    m = np.array(im) > 0
    if grow > 0:
        m = ndimage.binary_dilation(m, iterations=int(grow))
    return m

def line_dist(pts):
    """distance field (m) to a polyline on the 1 m grid"""
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    d.line([(x - X0, z - Z0) for x, z in pts], fill=255, width=1)
    return ndimage.distance_transform_edt(np.array(im) == 0)

def rect_pts(b, grow=0.0):
    cx, cz = b["pos"]; sx, sz = b["size"]; a = math.radians(b["yaw_deg"])
    out = []
    for ux, uz in [(-1, -1), (1, -1), (1, 1), (-1, 1)]:
        lx, lz = ux * (sx / 2 + grow), uz * (sz / 2 + grow)
        out.append([cx + lx * math.cos(a) - lz * math.sin(a), cz + lx * math.sin(a) + lz * math.cos(a)])
    return out

# ------------------------------------------------------------------ 1. heightmap
tiles = np.concatenate([tifffile.imread(os.path.join(GEO, "alti_2667-1251.tif")), tifffile.imread(os.path.join(GEO, "alti_2668-1251.tif"))], axis=1)
def dem_at(x, z):
    c = (E0 + x - 2667000) / 0.5; r = (1252000 - (N0 - z)) / 0.5
    return tiles[int(r), int(c)]
h = np.empty((H, W), np.float32)
for j in range(H):
    for i in range(W):
        h[j, i] = dem_at(X0 + i, Z0 + j)
h0 = float(dem_at(0, 0))
h -= h0
h = ndimage.gaussian_filter(h, 0.8)

# road beds: remove the cross slope, smooth along the road
for r in ROADS:
    d = line_dist(r["pts"])
    im = Image.new("L", (W, H), 0)
    ImageDraw.Draw(im).line([(x - X0, z - Z0) for x, z in r["pts"]], fill=255, width=1)
    on = np.array(im) > 0
    hc = np.where(on, h, 0.0)
    hs = ndimage.gaussian_filter(hc, 4.0) / np.maximum(ndimage.gaussian_filter(on.astype(np.float32), 4.0), 1e-3)
    idx = ndimage.distance_transform_edt(~on, return_distances=False, return_indices=True)
    near = hs[idx[0], idx[1]]
    wr = r["width"] / 2 + 1.5
    k = np.clip((d - (wr - 1.5)) / 1.5, 0, 1)
    h = np.where(d < wr, near * (1 - k) + h * k, h)
# gravel clearing: gentle
cm = poly_mask(CLEARING)
cd = ndimage.distance_transform_edt(~cm)
hs = ndimage.gaussian_filter(h, 3.0)
k = np.clip(cd / 4.0, 0, 1)
h = hs * (1 - k) + h * k
# Waldhütte terrace: ground north of the hut sits at the upper floor, the concrete base stands free on the south and west
hb = WALDHUETTE
a = math.radians(hb["yaw_deg"])
cx, cz = hb["pos"]
base_level = float(h[int(cz - Z0), int(cx - 4.5 - X0)])   # ground at the west face (gravel side)
jj, ii = np.mgrid[0:H, 0:W]
px, pz = ii + X0 - cx, jj + Z0 - cz
lx = px * math.cos(a) + pz * math.sin(a); lz = -px * math.sin(a) + pz * math.cos(a)
upper = base_level + hb["base_h"]
# terrace region: behind the east face within a fan, blending out over 9 m (the slope rises east anyway)
tz = lx - (hb["size"][0] / 2 - 1.4)                  # metres east of the terrace edge
side = np.abs(lz) - hb["size"][1] / 2                # metres outside the north/south faces
t_in = np.clip(tz / 1.0, 0, 1) * np.clip(1.0 - np.maximum(side, 0) / 3.0, 0, 1)
fade = np.clip(1.0 - np.maximum(tz - 3.0, 0) / 9.0, 0, 1) * np.clip(1.0 - np.maximum(side - 3.0, 0) / 6.0, 0, 1)
target = np.maximum(h, upper - 0.05)
h = h * (1 - t_in * fade) + target * (t_in * fade)
# keep the footprint itself flat at the upper level (the hut model closes the gap)
inside = (np.abs(lx) < hb["size"][0] / 2 + 0.3) & (np.abs(lz) < hb["size"][1] / 2 + 0.3)
h = np.where(inside & (lx > -0.5), np.maximum(h, upper - 0.05), h)
# Holzlager stands on a flat gravel pad
hl = HOLZLAGER
m = poly_mask(rect_pts(hl, 2.5))
lvl = float(np.mean(h[m]))
dl = ndimage.distance_transform_edt(~m)
k = np.clip(dl / 4.0, 0, 1)
h = lvl * (1 - k) + h * k
h[:, :] = h.astype(np.float32)

# ------------------------------------------------------------------ 2. ground cover from the aerial image
aer = Image.open(os.path.join(GEO, "aerial.jpg")).convert("RGB")
meta = json.load(open(os.path.join(GEO, "aerial.json")))
ppm = meta["ppm"]
aer = aer.resize((int(W * ppm), int(H * ppm)))
A = np.asarray(aer).astype(np.float32) / 255.0
n = int(ppm)
# block statistics per metre
def block(f, red):
    return red(f[:H * n, :W * n].reshape(H, n, W, n), axis=(1, 3))
lum = A.mean(axis=2)
mean_rgb = np.stack([block(A[:, :, c], np.mean) for c in range(3)], axis=2)
std = block(lum, np.std)
v = mean_rgb.max(axis=2)
mn = mean_rgb.min(axis=2)
sat = (v - mn) / np.maximum(v, 1e-3)
green = mean_rgb[:, :, 1] - np.maximum(mean_rgb[:, :, 0], mean_rgb[:, :, 2])
# forest: darker and textured crowns; meadow: bright, smooth; roads/bare: low saturation or bright
forest_raw = ((v < 0.42) | (std > 0.075)) & (green > -0.02) & ~((sat < 0.18) & (v > 0.45))
forest = ndimage.binary_opening(forest_raw, iterations=2)
forest = ndimage.binary_closing(forest, iterations=4)
forest = ndimage.binary_fill_holes(forest)
lab, nlab = ndimage.label(forest)
sizes = ndimage.sum(forest, lab, range(1, nlab + 1))
for i, s in enumerate(sizes):
    if s < 400:
        forest[lab == i + 1] = False
# clear zones
forest &= ~poly_mask(CLEARING, 1)
forest &= ~poly_mask(MEADOW_FORCE)
for b in (WALDHUETTE, HOLZLAGER):
    forest &= ~poly_mask(rect_pts(b, 2.0))
road_d = np.full((H, W), 1e9, np.float32)
gravel = np.zeros((H, W), np.float32)
asphalt = np.zeros((H, W), np.float32)
for r in ROADS:
    d = line_dist(r["pts"])
    road_d = np.minimum(road_d, d - r["width"] / 2)
    wgt = np.clip(1.0 - (d - r["width"] / 2) / 0.8, 0, 1)
    if r["surface"] == "asphalt":
        asphalt = np.maximum(asphalt, wgt)
    elif r["surface"] == "gravel":
        gravel = np.maximum(gravel, wgt)
    else:
        gravel = np.maximum(gravel, wgt * 0.6)
forest &= road_d > 2.0
gravel = np.maximum(gravel, np.clip(1.0 - cd / 1.5, 0, 1))
forest_f = ndimage.gaussian_filter(forest.astype(np.float32), 1.5)
leaf = np.clip(forest_f * 1.3, 0, 1)
# leaf litter also under the clearing's trees and around the huts (photos 14, 19)
leaf = np.maximum(leaf, np.clip(1.0 - (cd - 0.0) / 6.0, 0, 1) * (cd > 0))
leaf = np.maximum(leaf, np.clip(1.0 - np.hypot(jj + Z0 - 8, ii + X0 - 12) / 14.0, 0, 1))
leaf *= 1.0 - gravel
leaf *= 1.0 - asphalt
meadow = np.clip(1.0 - leaf - gravel - asphalt, 0, 1)
ground = np.stack([leaf, meadow, gravel], axis=2)
Image.fromarray((ground * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "ground.png"))
Image.fromarray((asphalt * 255).astype(np.uint8), "L").save(os.path.join(TOUT, "asphalt_mask.png"))

# ------------------------------------------------------------------ 3. trees from the forest mask + aerial colour
trees = []
dark = mean_rgb.mean(axis=2)
big_set = {(round(t[0]), round(t[1])) for t in BIG_TREES}
for x, z, kind, s in BIG_TREES:
    trees.append([round(x, 1), round(z, 1), kind, round(s, 2), int(rng.integers(0, 360))])
def tree_ok(x, z):
    i, j = int(x - X0), int(z - Z0)
    if not (0 <= i < W and 0 <= j < H) or not forest[j, i]:
        return False
    if road_d[j, i] < 1.6 or cm[j, i]:
        return False
    for b in (WALDHUETTE, HOLZLAGER):
        m = rect_pts(b, 2.5)
    if math.hypot(x - LANDMARK_OAK[0], z - LANDMARK_OAK[1]) < 9:
        return False
    for t in trees:
        if math.hypot(x - t[0], z - t[1]) < 2.6 * min(t[3], 1.2):
            return False
    return True
hut_masks = [poly_mask(rect_pts(b, 3.0)) for b in (WALDHUETTE, HOLZLAGER)]
spacing = 5.2
z = Z0 + 2.0
while z < Z1:
    x = X0 + 2.0
    while x < X1:
        px_, pz_ = x + rng.uniform(-2.2, 2.2), z + rng.uniform(-2.2, 2.2)
        i, j = int(px_ - X0), int(pz_ - Z0)
        if 0 <= i < W and 0 <= j < H and not any(hm[j, i] for hm in hut_masks) and rng.random() < 0.9 and tree_ok(px_, pz_):
            near = math.hypot(px_, pz_)
            d = dark[j, i]
            conifer = d < 0.20 or (d < 0.25 and rng.random() < 0.5)
            kind = "spruce" if conifer else ("oak" if rng.random() < 0.12 else "beech")
            sc = rng.uniform(0.85, 1.25) if near < 90 else rng.uniform(0.75, 1.15)
            # forest edge next to the tracks and the clearing: bigger old beeches (photos 13, 20)
            if road_d[j, i] < 6 and near < 70 and not conifer:
                sc += 0.15
            trees.append([round(px_, 1), round(pz_, 1), kind, round(sc, 2), int(rng.integers(0, 360))])
        x += spacing
    z += spacing
# undergrowth (young beeches, brambles) along forest edges facing open ground
edge = forest & ~ndimage.binary_erosion(forest, iterations=4)
ej, ei = np.nonzero(edge)
shrubs = []
for k in rng.choice(len(ej), size=min(1400, len(ej)), replace=False):
    x, z = ei[k] + X0 + rng.uniform(-0.5, 0.5), ej[k] + Z0 + rng.uniform(-0.5, 0.5)
    if road_d[int(z - Z0), int(x - X0)] > 1.2 and not cm[int(z - Z0), int(x - X0)]:
        shrubs.append([round(x, 1), round(z, 1), round(rng.uniform(0.7, 1.4), 2), int(rng.integers(0, 360))])
print("trees", len(trees), "shrubs", len(shrubs), "forest cells", int(forest.sum()))

# ------------------------------------------------------------------ 4. write
open(os.path.join(OUT, "heightmap.f32"), "wb").write(h.astype("<f4").tobytes())
data = {
    "origin_lv95": [E0, N0], "origin_wgs84": [47.4099806, 8.3397796], "origin_height": h0,
    "x0": X0, "z0": Z0, "w": W, "h": H, "cell": 1.0,
    "bounds": BOUNDS, "player_start": PLAYER_START,
    "roads": ROADS, "clearing": CLEARING,
    "buildings": {"waldhuette": WALDHUETTE, "holzlager": HOLZLAGER},
    "fire": FIRE, "benches": BENCHES, "table": TABLE, "fountain": FOUNTAIN, "bin": BIN, "signpost": SIGNPOST,
    "log_seat": LOG_SEAT, "landmark_oak": LANDMARK_OAK, "fence": FENCE,
    "spawns": SPAWNS, "barricades": BARRICADES,
    "trees": trees, "shrubs": shrubs,
}
json.dump(data, open(os.path.join(OUT, "map.json"), "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))

# ------------------------------------------------------------------ 5. preview + viewer
pv = aer.resize((W * 2, H * 2))
d = ImageDraw.Draw(pv)
def P(x, z):
    return ((x - X0) * 2, (z - Z0) * 2)
fm = Image.fromarray((forest * 90).astype(np.uint8)).resize((W * 2, H * 2))
pv = Image.composite(Image.new("RGB", pv.size, (0, 40, 120)), pv, fm.point(lambda p: min(p * 1, 70)))
d = ImageDraw.Draw(pv)
for r in ROADS:
    d.line([P(*p) for p in r["pts"]], fill=(255, 255, 0) if r["surface"] == "asphalt" else (255, 140, 0), width=max(2, int(r["width"] * 2)))
d.polygon([P(*p) for p in CLEARING], outline=(255, 255, 255))
for b in (WALDHUETTE, HOLZLAGER):
    d.polygon([P(*p) for p in rect_pts(b)], fill=(220, 40, 40))
for f in FENCE:
    d.line([P(*p) for p in f], fill=(255, 255, 255), width=1)
for k, pts in SPAWNS.items():
    for p in pts:
        d.ellipse([P(p[0] - 2, p[1] - 2), P(p[0] + 2, p[1] + 2)], fill=(255, 0, 255))
for b in BARRICADES:
    d.ellipse([P(b["pos"][0] - 2, b["pos"][1] - 2), P(b["pos"][0] + 2, b["pos"][1] + 2)], fill=(0, 255, 255))
d.ellipse([P(-1.5, -1.5), P(1.5, 1.5)], fill=(255, 0, 0))
d.ellipse([P(LANDMARK_OAK[0] - 2, LANDMARK_OAK[1] - 2), P(LANDMARK_OAK[0] + 2, LANDMARK_OAK[1] + 2)], outline=(0, 255, 0), width=2)
for t in trees:
    if abs(t[0]) < 60 and abs(t[1]) < 80:
        c = (40, 200, 40) if t[2] != "spruce" else (20, 90, 20)
        d.ellipse([P(t[0] - 0.8, t[1] - 0.8), P(t[0] + 0.8, t[1] + 0.8)], fill=c)
pv.save(os.path.join(TOUT, "map_preview.png"))
pv.crop((P(-60, -60)[0], P(-60, -60)[1], P(140, 100)[0], P(140, 100)[1])).save(os.path.join(TOUT, "map_preview_close.png"))

# viewer
small = aer.resize((W * 2, H * 2)); buf = io.BytesIO(); small.save(buf, "JPEG", quality=80)
tex = base64.b64encode(buf.getvalue()).decode()
hb64 = base64.b64encode(h.astype("<f4").tobytes()).decode()
ov = Image.new("RGBA", (W * 2, H * 2), (0, 0, 0, 0)); d = ImageDraw.Draw(ov)
for r in ROADS:
    d.line([P(*p) for p in r["pts"]], fill=(255, 255, 0, 255) if r["surface"] == "asphalt" else (255, 140, 0, 255), width=max(2, int(r["width"] * 2)))
for b in (WALDHUETTE, HOLZLAGER):
    d.polygon([P(*p) for p in rect_pts(b)], fill=(220, 40, 40, 255))
d.ellipse([P(-1.5, -1.5), P(1.5, 1.5)], fill=(255, 0, 0, 255))
buf = io.BytesIO(); ov.save(buf, "PNG"); ovb = base64.b64encode(buf.getvalue()).decode()
html = f"""<!doctype html><html><head><meta charset="utf-8"><title>Terrain Viewer Remetschwil</title>
<style>body{{margin:0;background:#222;color:#eee;font:13px sans-serif}}#i{{position:absolute;left:8px;top:8px;background:#0008;padding:6px}}</style></head><body>
<div id="i">Waldhütte Remetschwil, swissALTI3D 1 m, x∈[{X0},{X1}] z∈[{Z0},{Z1}]. Drag = orbit, wheel = zoom, right drag = pan. Rot = Hütten, gelb = Asphalt, orange = Kies, blau = Wald.</div>
<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
<script>
const W={W},H={H},X0={X0},Z0={Z0};
const hb=Uint8Array.from(atob("{hb64}"),c=>c.charCodeAt(0));const hf=new Float32Array(hb.buffer);
const scene=new THREE.Scene();scene.background=new THREE.Color(0x202830);
const cam=new THREE.PerspectiveCamera(50,innerWidth/innerHeight,1,3000);
const ren=new THREE.WebGLRenderer({{antialias:true}});ren.setSize(innerWidth,innerHeight);document.body.appendChild(ren.domElement);
const geo=new THREE.PlaneGeometry(W,H,W-1,H-1);geo.rotateX(-Math.PI/2);
const pos=geo.attributes.position;for(let j=0;j<H;j++)for(let i=0;i<W;i++){{const k=j*W+i;pos.setXYZ(k,X0+i,hf[k],Z0+j);}}
geo.computeVertexNormals();
const tex=new THREE.TextureLoader().load("data:image/jpeg;base64,{tex}");
const ovt=new THREE.TextureLoader().load("data:image/png;base64,{ovb}");
const mat=new THREE.MeshLambertMaterial({{map:tex}});
const mesh=new THREE.Mesh(geo,mat);scene.add(mesh);
const ovm=new THREE.Mesh(geo.clone(),new THREE.MeshBasicMaterial({{map:ovt,transparent:true,depthWrite:false}}));ovm.position.y=0.3;scene.add(ovm);
const forest=new THREE.Mesh(geo.clone(),new THREE.MeshBasicMaterial({{color:0x2040ff,transparent:true,opacity:0.0}}));
scene.add(new THREE.AmbientLight(0xffffff,0.5));const sun=new THREE.DirectionalLight(0xffffff,0.9);sun.position.set(-1,1,-0.5);scene.add(sun);
// contour lines every 2 m
const cg=new THREE.BufferGeometry();const cv=[];
for(let j=0;j<H-1;j++)for(let i=0;i<W-1;i++){{const a=hf[j*W+i],b=hf[j*W+i+1],c=hf[(j+1)*W+i];if(Math.floor(a/2)!=Math.floor(b/2)||Math.floor(a/2)!=Math.floor(c/2)){{cv.push(X0+i,a+0.4,Z0+j,X0+i+0.7,a+0.4,Z0+j+0.7);}}}}
cg.setAttribute("position",new THREE.Float32BufferAttribute(cv,3));scene.add(new THREE.LineSegments(cg,new THREE.LineBasicMaterial({{color:0xff4040}})));
let yaw=0.6,pitch=0.9,dist=420,tgt=new THREE.Vector3(0,0,0),drag=0,lx=0,ly=0;
function place(){{cam.position.set(tgt.x+dist*Math.cos(pitch)*Math.sin(yaw),tgt.y+dist*Math.sin(pitch),tgt.z+dist*Math.cos(pitch)*Math.cos(yaw));cam.lookAt(tgt);}}
addEventListener("mousedown",e=>{{drag=e.button+1;lx=e.clientX;ly=e.clientY;}});addEventListener("mouseup",()=>drag=0);addEventListener("contextmenu",e=>e.preventDefault());
addEventListener("mousemove",e=>{{if(!drag)return;const dx=e.clientX-lx,dy=e.clientY-ly;lx=e.clientX;ly=e.clientY;if(drag==1){{yaw-=dx*0.005;pitch=Math.min(1.5,Math.max(0.05,pitch+dy*0.005));}}else{{const r=new THREE.Vector3(Math.cos(yaw),0,-Math.sin(yaw));const f=new THREE.Vector3(-Math.sin(yaw),0,-Math.cos(yaw));tgt.addScaledVector(r,-dx*dist*0.0015).addScaledVector(f,dy*dist*0.0015);}}}});
addEventListener("wheel",e=>{{dist=Math.min(1500,Math.max(20,dist*(1+e.deltaY*0.001)));}});
function fit(){{if(ren.domElement.width!=innerWidth||ren.domElement.height!=innerHeight){{ren.setSize(innerWidth,innerHeight);cam.aspect=innerWidth/innerHeight;cam.updateProjectionMatrix();}}}}
addEventListener("resize",fit);
function loop(){{fit();place();ren.render(scene,cam);requestAnimationFrame(loop);}}loop();
</script></body></html>"""
open(os.path.join(TOUT, "terrain_viewer.html"), "w", encoding="utf-8").write(html)
print("heights: fire 0, hut", float(h[int(4.5 - Z0), int(9 - X0)]), "hut N", float(h[int(-2 - Z0), int(9 - X0)]), "Sennhofstr junction", float(h[int(21 - Z0), int(124 - X0)]), "fork", float(h[int(57 - Z0), int(5 - X0)]), "min", float(h.min()), "max", float(h.max()))

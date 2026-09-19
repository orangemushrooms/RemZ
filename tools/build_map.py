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
    {"name": "Waldweg nach Hütte (Oberer Sorchen)", "surface": "gravel", "width": 3.6,
     "pts": [[-4, -11], [-9, -21], [-18, -34], [-29, -49], [-33, -56], [-57, -112], [-69, -141], [-73, -152], [-80, -173], [-97, -207], [-115, -247], [-125, -275]]},
    {"name": "Weg Richtung Dorf", "surface": "gravel", "width": 3.2,
     "pts": [[7, 61], [-7.5, 65], [-45, 71], [-62, 72], [-67, 75], [-190, 132], [-275, 171]]},
    {"name": "Feldweg West", "surface": "dirt", "width": 2.8,
     "pts": [[-62, 72], [-66, 60], [-76, 45], [-88, 25], [-114, -18], [-134, -60], [-161, -96], [-166, -108], [-194, -181]]},
    {"name": "Wiesentor", "surface": "dirt", "width": 2.8,
     "pts": [[7, 61], [8, 70]]},
    {"name": "Fussweg Nord", "surface": "dirt", "width": 1.6,
     "pts": [[-73, -152], [-66, -154], [-47, -168], [-35.7, -171.7]]},  # ends at the pond's west bank
    {"name": "Feldweg Ost", "surface": "gravel", "width": 3.0,
     "pts": [[124, 21], [140, 17], [160, 12]]},
]
def smooth(pts, step=3.0):
    """Catmull-Rom resampling so the ribbons and road beds have no visible corners"""
    if len(pts) < 3:
        return pts
    P = [pts[0]] + pts + [pts[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = (np.array(P[k], float) for k in (i - 1, i, i + 1, i + 2))
        n = max(2, int(np.linalg.norm(p2 - p1) / step))
        for k in range(n):
            t = k / n
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)
            out.append([round(float(q[0]), 2), round(float(q[1]), 2)])
    out.append(list(pts[-1]))
    return out
for _r in ROADS:
    _r["pts"] = smooth(_r["pts"])
# gravel clearing around the fire, the aprons of both huts
# Kiesplatz: fire plaza north-west of the Waldhütte (photos 13, 14, 15, 20), the track between the huts, both aprons
CLEARING = [[-11, -16], [-4, -17], [3, -17], [9, -15], [13, -12], [13.5, -0.8], [6.2, 0.2], [5.6, 8.5], [7, 18], [12, 40], [11, 58], [3, 63], [0, 44], [-1, 20], [-5, 10], [-9, 2], [-11, -12]]
# the level fire plaza (terrain), see the height section
PLAZA = [[-10, -18], [-3, -20], [6, -19], [12, -16], [14.5, -10], [14, -1], [6, 1.5], [-3, 0], [-9, -3], [-12, -9]]
# Photos 15, 18, 20: the benches and the fire stand on fine grey gravel; only the north-west part of the plaza
# (picnic table, fountain, under the big beeches) is earth with leaf litter.
CAMP_FOREST_FLOOR = [[-13, -21], [-6, -23], [-1, -19.5], [-3.5, -14.5], [-6.5, -11], [-13, -9]]
# The dark crop south-west of Feldweg West is farmland, not tree crowns. Keep the
# whole downhill field open across Weg Richtung Dorf and out towards the village.
MEADOW_FORCE = [[-400, -120], [-190, -120], [-166, -100], [-138, -59], [-118, -16], [-92, 27], [-80, 47], [-70, 64], [-70, 78], [-8, 68], [12, 64], [30, 58], [55, 51], [90, 36], [125, 29], [150, 29], [150, 260], [-400, 260]]
FIELD_SE = [[113, 24], [128, 18], [150, 8], [150, 160], [113, 160]]   # fields east of the Sennhofstrasse south of the junction
# Waldhütte (OSM way 36785519): garage door in the west face, outside stair along the north face rising east to the
# upper door, east side buried in the slope (photos 14, 17, 19)
WALDHUETTE = {"pos": [9.1, 4.6], "size": [6.6, 7.4], "yaw_deg": -8.0, "base_h": 2.4, "wall_h": 2.5, "roof_h": 1.5}
HOLZLAGER = {"pos": [-3.0, 26.3], "size": [7.9, 13.6], "yaw_deg": -14.0, "base_h": 0.8, "wall_h": 3.6, "roof_h": 1.6}   # ridge and roof edges in the aerial run at 14 deg, not the 23 deg of the OSM outline
# Seat group 3 m east of the OSM picnic node. Photo 20 (from the south bench, looking north): picnic table behind
# the north bench to the left, the white bin straight behind the table, the log fountain at the far left at the
# plaza's west edge. Photo 15 (from the west edge, looking east): fountain in front, bin behind it, benches beyond,
# the hut's stair at the right. Photo 13 (from the track in the south): fountain and bin almost in line, left of the
# benches. All coordinates use true north; the annotated photo plans are schematic. Origin stays the OSM picnic node.
FIRE = [7.0, -7.0]
BENCHES = [[7.0, -4.2, 0.0], [7.0, -9.8, 0.0], [4.2, -7.0, 90.0], [9.8, -7.0, 90.0]]   # x, z, yaw (length axis)
TABLE = [1.2, -11.0, 5.0]           # north-west of the fire, 3 m west of the west bench, on leaf litter (photo 18)
FOUNTAIN = [-2.0, -13.0, 90.0]      # trough north-south with the post at the south end, beside the Waldweg entrance
BIN = [-0.5, -16.0]                 # white drum on a post, between table and track entrance (photos 15, 16, 20)
SIGNPOST = [-5.5, -21.0]            # info board and sign east of the Waldweg (photo 16)
LOG_SEAT = [-10.0, -4.0, 75.0]
LANDMARK_OAK = [66.0, 34.0]
BIG_TREES = [[1.5, 0.8, "beech", 1.35], [-13.5, -18.0, "beech", 1.25], [14.5, -12.0, "beech", 1.2], [-9.0, 6.0, "beech", 1.15],
             [-14.0, -8.0, "beech", 1.2], [2.0, -25.0, "beech", 1.15], [-6.0, -25.5, "oak", 1.1], [9.5, -23.0, "oak", 1.1], [15.0, -3.0, "beech", 1.1],
             [-20.5, -9.0, "oak", 1.2], [-9.0, 14.0, "beech", 1.1],
             [14.0, -3.0, "spruce", 1.2], [-8.0, 42.0, "beech", 1.1], [12.5, 30.0, "beech", 1.15]]
# Photos 9, 10, 11, 24: the Weg zur Huette and the fork have an open grass verge towards the field, no fence.
# The only fence is the wire fence on the east side of the Sennhofstrasse south of the junction (photos 4, 5).
FENCE = [[[128, 30], [140, 112], [149, 150]]]
SPAWNS = {"north": [[112, 28], [118, 8], [104, 31]], "east": [[32, 100], [58, 96], [18, 112]],
          "south": [[-78, 80], [-96, 88], [-70, 77]], "west": [[-44, -86], [-56, -108], [-40, -72]]}
BARRICADES = [
    {"id": "ne", "name": "Weg zur Hütte", "pos": [28, 55], "yaw": -1.19, "segments": 2},
    {"id": "e", "name": "Wiesentor", "pos": [7.5, 66], "yaw": 0.0, "segments": 2},
    {"id": "s", "name": "Weg Richtung Dorf", "pos": [-16, 66.5], "yaw": -1.55, "segments": 2},
    {"id": "w", "name": "Waldweg Nord", "pos": [-15, -30], "yaw": 0.59, "segments": 2},
]
# Forest pond at the eastern end of Fussweg Nord (player position in the reference screenshot).
POND = {"pos": [-28.0, -174.0], "r": 7.0, "depth": 0.9}
POND_TROUGH = [-31.5, -166.5]           # south-west bank, beside the approach; the mouth feeds the water
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
# fire plaza: the photos (15, 17, 20) show one level place from the hut's garage door and the foot of the outside stair
# across the benches to the Waldweg entrance; the raw DEM climbs 1.3 m towards the north-east there. Pull the plaza
# onto a plane anchored at the hut's west face with a 1.2 % rise to the north-east, blended out over 7 m.
_pj, _pi = np.mgrid[0:H, 0:W]
_px, _pz = _pi + X0, _pj + Z0
_anchor = float(h[int(WALDHUETTE["pos"][1] - Z0), int(WALDHUETTE["pos"][0] - 4.5 - X0)])
plaza_plane = _anchor + 0.012 * (_px - (WALDHUETTE["pos"][0] - 4.5)) - 0.012 * (_pz - WALDHUETTE["pos"][1])
pm = poly_mask(PLAZA)
pd_plaza = ndimage.distance_transform_edt(~pm)
k = np.clip(pd_plaza / 7.0, 0, 1)
h = plaza_plane * (1 - k) + h * k
# pond: a shallow dish, rim blended into the forest floor, flat enough to walk through
pj, pi = np.mgrid[0:H, 0:W]
pd = np.hypot(pi + X0 - POND["pos"][0], pj + Z0 - POND["pos"][1])
rim_ring = (pd > POND["r"]) & (pd < POND["r"] + 2.0)
pond_rim = float(h[rim_ring].mean())
dish = pond_rim - POND["depth"] * np.clip(1.0 - (pd / POND["r"]) ** 2, 0, 1)
# level bank 3 m wide all around (so the water never floats above the downhill side), then blend out over 8 m
blend = np.clip((pd - POND["r"] - 3.0) / 8.0, 0, 1)
h = np.where(pd < POND["r"] + 11.0, dish * (1 - blend) + h * blend, h)
POND["rim"] = pond_rim
POND["water_y"] = pond_rim - POND["depth"] * 0.35
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
tz = lx - hb["size"][0] / 2                          # metres east of the east face
side = np.abs(lz) - hb["size"][1] / 2                # metres outside the north/south faces
t_in = np.clip(tz / 1.0, 0, 1) * np.clip(1.0 - np.maximum(side, 0) / 3.0, 0, 1)
fade = np.clip(1.0 - np.maximum(tz - 3.0, 0) / 9.0, 0, 1) * np.clip(1.0 - np.maximum(side - 3.0, 0) / 6.0, 0, 1)
target = np.maximum(h, upper - 0.05)
h = h * (1 - t_in * fade) + target * (t_in * fade)
# keep the footprint itself flat at the upper level (the hut model closes the gap)
inside = (np.abs(lx) < hb["size"][0] / 2 + 0.6) & (np.abs(lz) < hb["size"][1] / 2 + 0.6)
h = np.where(inside, base_level, h)     # garage floor, the hut is walkable inside
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
forest &= ~poly_mask(FIELD_SE)
for b in (WALDHUETTE, HOLZLAGER):
    forest &= ~poly_mask(rect_pts(b, 2.0))
road_d = np.full((H, W), 1e9, np.float32)
gravel = np.zeros((H, W), np.float32)
asphalt = np.zeros((H, W), np.float32)
for r in ROADS:
    d = line_dist(r["pts"])
    road_d = np.minimum(road_d, d - r["width"] / 2)
    wgt = np.clip(1.0 - (d - r["width"] / 2 + 0.5) / 0.6, 0, 1)   # stays under the ribbon
    if r["surface"] == "asphalt":
        asphalt = np.maximum(asphalt, wgt)
    elif r["surface"] == "gravel":
        gravel = np.maximum(gravel, wgt)
    else:
        gravel = np.maximum(gravel, wgt * 0.6)
forest &= road_d > 2.0
road_gravel = gravel.copy()
gravel = np.maximum(gravel, np.clip(1.0 - cd / 1.5, 0, 1))
forest_f = ndimage.gaussian_filter(forest.astype(np.float32), 1.5)
leaf = np.clip(forest_f * 1.3, 0, 1)
# leaf litter also under the clearing's trees and around the huts (photos 14, 19)
leaf = np.maximum(leaf, np.clip(1.0 - (cd - 0.0) / 6.0, 0, 1) * (cd > 0))
leaf = np.maximum(leaf, np.clip(1.0 - np.hypot(jj + Z0 - 8, ii + X0 - 12) / 14.0, 0, 1))
pond_bed = np.clip(1.0 - (pd - POND["r"] + 1.0) / 1.5, 0, 1)      # sandy bed under the water
pond_grass = np.clip(1.0 - (pd - POND["r"] - 1.0) / 3.0, 0, 1)      # grassy bank around it
gravel = np.maximum(gravel, pond_bed)
# Blend the campsite into the surrounding forest floor without planting trees on the plaza.
camp_leaf = ndimage.gaussian_filter(poly_mask(CAMP_FOREST_FLOOR).astype(np.float32), 1.2)
camp_leaf *= 1.0 - road_gravel
gravel *= 1.0 - camp_leaf
leaf = np.maximum(leaf, camp_leaf)
leaf *= 1.0 - gravel
leaf *= 1.0 - asphalt
leaf *= 1.0 - pond_grass
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
WEG_HUETTE = ROADS[1]["pts"]
def meadow_side_of_weg(x, z):
    """south (meadow side) of the Weg zur Huette and within 30 m of it: the pasture must stay open"""
    pts = WEG_HUETTE
    for a, b in zip(pts, pts[1:]):
        if min(a[0], b[0]) <= x <= max(a[0], b[0]):
            rz = a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])
            return z > rz - 0.5 and z - rz < 30
    return False
def tree_ok(x, z):
    i, j = int(x - X0), int(z - Z0)
    if not (0 <= i < W and 0 <= j < H) or not forest[j, i]:
        return False
    if meadow_side_of_weg(x, z):
        return False
    if math.hypot(x - POND["pos"][0], z - POND["pos"][1]) < POND["r"] + 3.5:
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
    if road_d[int(z - Z0), int(x - X0)] > 1.2 and not cm[int(z - Z0), int(x - X0)] and math.hypot(x - POND["pos"][0], z - POND["pos"][1]) >= POND["r"] + 3.5:
        shrubs.append([round(x, 1), round(z, 1), round(rng.uniform(0.7, 1.4), 2), int(rng.integers(0, 360))])
# dense border forest outside the playable extent so no map edge is ever visible (no collision needed)
border = []
for z in np.arange(Z0 - 90, Z1 + 90, 6.0):
    for x in np.arange(X0 - 90, X1 + 90, 6.0):
        if X0 + 3 < x < X1 - 3 and Z0 + 3 < z < Z1 - 3:
            continue
        if x > X1 - 3 and z > -120:        # east: fields and the village, no forest
            continue
        if z > Z1 - 3:                     # south: open fields towards Remetschwil
            continue
        px_, pz_ = x + rng.uniform(-2.5, 2.5), z + rng.uniform(-2.5, 2.5)
        if px_ < X0 + 3 and pz_ > -120:    # west: the downhill fields continue beyond the fine terrain
            continue
        kind = "spruce" if rng.random() < 0.35 else "beech"
        border.append([round(float(px_), 1), round(float(pz_), 1), kind, round(float(rng.uniform(0.9, 1.3)), 2), int(rng.integers(0, 360))])
def lv95(lat, lon):
    p = (lat * 3600 - 169028.66) / 10000
    l = (lon * 3600 - 26782.5) / 10000
    e = 2600072.37 + 211455.93 * l - 10938.51 * l * p - 0.36 * l * p * p - 44.54 * l ** 3
    n = 1200147.07 + 308807.95 * p + 3745.25 * l * l + 76.63 * p * p - 194.56 * l * l * p + 119.79 * p ** 3
    return e, n
village = []
osm = json.load(open(os.path.join(GEO, "osm.json")))
for e in osm["elements"]:
    t = e.get("tags", {})
    if e["type"] != "way" or not t.get("building") or "geometry" not in e:
        continue
    poly = []
    for g in e["geometry"]:
        E, N = lv95(g["lat"], g["lon"])
        poly.append([round(E - E0, 1), round(-(N - N0), 1)])
    cx_, cz_ = float(np.mean([p[0] for p in poly])), float(np.mean([p[1] for p in poly]))
    if abs(cx_) < 600 and abs(cz_) < 600 and not (X0 < cx_ < X1 and Z0 < cz_ < Z1):
        village.append({"poly": poly[:-1], "h": 6.5 if t.get("building") in ("yes", "house", "residential") else 4.5})
# understory inside the forest near the camp: young beeches, ferns, dead branches
ferns = []
logs = []
fj, fi = np.nonzero(forest & (road_d > 2.0) & ~cm)
sel = rng.choice(len(fj), size=min(9000, len(fj)), replace=False)
for k in sel:
    x, z = fi[k] + X0 + rng.uniform(-0.5, 0.5), fj[k] + Z0 + rng.uniform(-0.5, 0.5)
    dist = math.hypot(x, z)
    if dist > 160:
        continue
    r = rng.random()
    if r < 0.42:
        ferns.append([round(x, 1), round(z, 1), round(rng.uniform(0.7, 1.3), 2), int(rng.integers(0, 360))])
    elif r < 0.62:
        shrubs.append([round(x, 1), round(z, 1), round(rng.uniform(0.5, 1.1), 2), int(rng.integers(0, 360))])
    elif r < 0.68:
        logs.append([round(x, 1), round(z, 1), round(rng.uniform(1.5, 4.0), 2), int(rng.integers(0, 360))])
print("trees", len(trees), "shrubs", len(shrubs), "ferns", len(ferns), "logs", len(logs), "border", len(border), "village", len(village), "forest cells", int(forest.sum()))

# ------------------------------------------------------------------ 4. write
open(os.path.join(OUT, "heightmap.f32"), "wb").write(h.astype("<f4").tobytes())
SK_X0, SK_Z0, SK_STEP = -1000, -590, 10
sk_w, sk_h = 199, 99
skirt = np.empty((sk_h, sk_w), np.float32)
for j in range(sk_h):
    for i in range(sk_w):
        skirt[j, i] = dem_at(SK_X0 + i * SK_STEP, SK_Z0 + j * SK_STEP) - h0
skirt = ndimage.gaussian_filter(skirt, 1.0)
open(os.path.join(OUT, "skirt.f32"), "wb").write(skirt.astype("<f4").tobytes())
data = {
    "origin_lv95": [E0, N0], "origin_wgs84": [47.4099806, 8.3397796], "origin_height": h0,
    "x0": X0, "z0": Z0, "w": W, "h": H, "cell": 1.0,
    "skirt": {"x0": SK_X0, "z0": SK_Z0, "w": sk_w, "h": sk_h, "cell": SK_STEP},
    "bounds": BOUNDS, "player_start": PLAYER_START,
    "roads": ROADS, "clearing": CLEARING,
    "buildings": {"waldhuette": WALDHUETTE, "holzlager": HOLZLAGER},
    "fire": FIRE, "benches": BENCHES, "table": TABLE, "fountain": FOUNTAIN, "pond": {"pos": POND["pos"], "r": POND["r"], "depth": POND["depth"], "water_y": POND["water_y"], "trough": POND_TROUGH}, "bin": BIN, "signpost": SIGNPOST,
    "log_seat": LOG_SEAT, "landmark_oak": LANDMARK_OAK, "fence": FENCE,
    "spawns": SPAWNS, "barricades": BARRICADES,
    "trees": trees, "shrubs": shrubs, "ferns": ferns, "logs": logs, "border_trees": border, "village": village,
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

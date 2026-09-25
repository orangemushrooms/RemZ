"""Conifer zones for godot/assets/map/map.json (25 Sep 2026): swaps the species of trees inside the map
extent so that the deep forest and the Oberer Schorchen carry the two Meshy conifers ("fir" = conifer_fir,
"spruce_hd" = conifer_spruce, see Trees.SPECIES) and the forest edge towards the fields gets a few scattered
ones. Run after tools/build_map.py, deterministic (seeded), idempotent (only beech / oak / spruce / fir /
spruce_hd are touched, positions and scales stay).

    python tools/conifer_zones.py            rewrite map.json, print the counts
    python tools/conifer_zones.py --dry-run  only print the counts

Rules (metres, x east / z south, fire at (7, -7)):
  - within SCHORCHEN_R of the Secret Night site (-108, -201): every tree is a Meshy conifer (the "Oberer
    Schorchen" stand; the 21 m around the site itself are cleared by trees.gd anyway)
  - deep forest: farther than DEEP_ROAD from every track and farther than DEEP_FIRE from the fire ->
    DEEP_SHARE of the trees become Meshy conifers, the rest keep their species
  - nothing within PLAZA_R of the fire or within MIN_ROAD of a track edge (the crowns reach the ground)
  - the aerial's conifer stands (species "spruce" from build_map.py) inside DARK_RADIUS of the fire ->
    DARK_SHARE Meshy conifers (the procedural spruce stays as the filler of those stands)
  - forest edge towards the fields (z > FIELD_Z or x > FIELD_X, within FIELD_ROAD of a track): EDGE_SHARE
    scattered Meshy conifers among the beeches
Species mix of the swapped trees: MIX_SPRUCE spruce_hd, the rest fir.
"""
import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP = ROOT / 'godot/assets/map/map.json'

SITE = (-108.0, -201.0)
SCHORCHEN_R = 85.0
FIRE = (7.0, -7.0)
DEEP_ROAD = 24.0
DEEP_FIRE = 60.0
DEEP_SHARE = 0.55
DARK_RADIUS = 150.0
PLAZA_R = 45.0                 # no Meshy conifer this close to the fire: the campsite keeps the photo look
MIN_ROAD = 6.0                 # ... nor this close to a track edge: the GLB crowns reach the ground and hung into the paths
DARK_SHARE = 0.55
FIELD_Z = 35.0
FIELD_X = 55.0
FIELD_ROAD = 18.0
EDGE_SHARE = 0.12
MIX_SPRUCE = 0.55
SEED = 2609
CONIFERS = ('fir', 'spruce_hd')


def seg_dist(p, a, b):
    ax, az = a
    bx, bz = b
    px, pz = p
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / l2))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def road_distance(p, roads):
    best = 1e9
    for road in roads:
        pts = road['pts']
        half = float(road.get('width', 3.0)) * 0.5
        for a, b in zip(pts, pts[1:]):
            best = min(best, seg_dist(p, a, b) - half)
    return best


def main():
    dry = '--dry-run' in sys.argv
    data = json.loads(MAP.read_text(encoding='utf-8'))
    roads = data['roads']
    rng = random.Random(SEED)
    counts = {'schorchen': 0, 'deep': 0, 'dark': 0, 'edge': 0}
    trees = data['trees']
    for tree in trees:
        x, z, kind = float(tree[0]), float(tree[1]), tree[2]
        if kind in CONIFERS:
            kind = 'spruce' if kind == 'spruce_hd' else 'beech'   # rerun: start from the base species again
        roll = rng.random()          # one draw per tree, whatever the rule, keeps the layout stable
        pick = rng.random()
        new = None
        d_site = math.hypot(x - SITE[0], z - SITE[1])
        d_fire = math.hypot(x - FIRE[0], z - FIRE[1])
        d_road = road_distance((x, z), roads)
        if d_fire < PLAZA_R or d_road < MIN_ROAD:
            pass
        elif d_site < SCHORCHEN_R:
            new, key = True, 'schorchen'
        elif d_road > DEEP_ROAD and d_fire > DEEP_FIRE and roll < DEEP_SHARE:
            new, key = True, 'deep'
        elif kind == 'spruce' and d_fire < DARK_RADIUS and roll < DARK_SHARE:
            new, key = True, 'dark'
        elif (z > FIELD_Z or x > FIELD_X) and d_road < FIELD_ROAD and roll < EDGE_SHARE:
            new, key = True, 'edge'
        if new:
            tree[2] = 'spruce_hd' if pick < MIX_SPRUCE else 'fir'
            counts[key] += 1
        else:
            tree[2] = kind
    total = {}
    for tree in trees:
        total[tree[2]] = total.get(tree[2], 0) + 1
    print('swapped', counts, 'species', total)
    if not dry:
        text = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
        MAP.write_text(text, encoding='utf-8')
        print('written', MAP)


if __name__ == '__main__':
    main()

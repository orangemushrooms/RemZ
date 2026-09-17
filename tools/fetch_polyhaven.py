"""Downloads the CC0 Poly Haven models and textures used by the Godot project (not committed, ~2 GB).
Usage: python tools/fetch_polyhaven.py
"""
import json, urllib.request, os, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {"User-Agent": "Mozilla/5.0 RemZ"}
def get(u):
    for i in range(4):
        try:
            return urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=120).read()
        except Exception:
            time.sleep(2)
    raise RuntimeError(u)
MODELS = ["island_tree_01", "island_tree_02", "island_tree_03", "jacaranda_tree", "fir_tree_01", "pine_tree_01", "tree_small_02", "dead_tree_trunk_02", "fern_02", "grass_medium_02", "moss_01", "dry_branches_medium_01", "bark_debris_01", "boulder_01", "tree_stump_01"]
TEXTURES = {"forest_leaves_02": "leaves", "leafy_grass": "grass", "asphalt_02": "asphalt", "gravel": "gravel", "bark_brown_02": "bark", "brown_planks_07": "planks", "clay_roof_tiles": "roof", "dry_decay_leaves": "leaves2", "mossy_rock": "rock"}
for n in MODELS:
    files = json.loads(get(f"https://api.polyhaven.com/files/{n}"))
    res = "2k" if "2k" in files["gltf"] else "1k"
    g = files["gltf"][res]["gltf"]
    d = os.path.join(ROOT, "godot", "assets", "ph", n); os.makedirs(d, exist_ok=True)
    main = os.path.join(d, f"{n}.gltf")
    if not os.path.exists(main): open(main, "wb").write(get(g["url"]))
    for rel, info in g.get("include", {}).items():
        p = os.path.join(d, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
        if not os.path.exists(p): open(p, "wb").write(get(info["url"]))
    print("model", n, res)
td = os.path.join(ROOT, "godot", "assets", "textures"); os.makedirs(td, exist_ok=True)
for asset, short in TEXTURES.items():
    files = json.loads(get(f"https://api.polyhaven.com/files/{asset}"))
    for key, tag in [("Diffuse", "albedo"), ("nor_gl", "normal"), ("Rough", "rough"), ("AO", "ao")]:
        try: url = files[key]["1k"]["jpg"]["url"]
        except KeyError: continue
        dst = os.path.join(td, f"{short}_{tag}.jpg")
        if not os.path.exists(dst): open(dst, "wb").write(get(url))
    print("texture", asset)
print("Run tools/autumn_leaves.py afterwards to recolour the tree leaves.")

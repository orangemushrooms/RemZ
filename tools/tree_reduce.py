# Blender batch: reduce Poly Haven photogrammetry trees to game-ready GLBs (numpy, fast).
#   leaf/needle cards: keep a random fraction of faces, scale survivors up around their centre
#   trunk/branch geometry: decimate (collapse) via vertex-group limited modifier
# Run: blender -b -P tools/tree_reduce.py -- <name> [<name> ...]
import bpy, sys, os, random
import numpy as np
random.seed(5)
np.random.seed(5)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PH = os.path.join(ROOT, "godot", "assets", "ph")
OUT = os.path.join(ROOT, "godot", "assets", "trees")
os.makedirs(OUT, exist_ok=True)
# name -> (leaf material keywords, leaf keep fraction, leaf scale, trunk decimate ratio)
CFG = {
    "island_tree_01": (["leaves"], 0.28, 1.9, 0.25),
    "island_tree_02": (["leaves"], 0.28, 1.9, 0.25),
    "island_tree_03": (["leaves"], 0.22, 2.0, 0.2),
    "jacaranda_tree": (["leaves"], 0.16, 2.2, 0.15),
    "tree_small_02": (["leaves"], 0.22, 2.0, 0.2),
    "fir_tree_01": (["twig"], 0.12, 2.2, 0.2),
    "dead_tree_trunk_02": ([], 1.0, 1.0, 0.3),
    "fern_02": (["fern", "leaves"], 1.0, 1.0, 1.0),
    "grass_medium_02": (["grass"], 1.0, 1.0, 1.0),
    "moss_01": ([], 1.0, 1.0, 0.5),
    "dry_branches_medium_01": ([], 1.0, 1.0, 0.4),
    "bark_debris_01": ([], 1.0, 1.0, 0.4),
    "boulder_01": ([], 1.0, 1.0, 0.15),
    "tree_stump_01": ([], 1.0, 1.0, 0.3),
}
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(CFG.keys())

def is_leaf_mat(mat, keys):
    return mat is not None and any(k in mat.name.lower() for k in keys)

def reduce_leaves(obj, leaf_slots, keep, scale):
    me = obj.data
    npoly = len(me.polygons)
    if npoly == 0:
        return
    mat_idx = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("material_index", mat_idx)
    loop_start = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("loop_start", loop_start)
    loop_total = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("loop_total", loop_total)
    nloop = len(me.loops)
    loop_vert = np.empty(nloop, dtype=np.int32); me.loops.foreach_get("vertex_index", loop_vert)
    nvert = len(me.vertices)
    co = np.empty(nvert * 3, dtype=np.float32); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    uv_layer = me.uv_layers.active
    uv = np.empty(nloop * 2, dtype=np.float32); uv_layer.data.foreach_get("uv", uv); uv = uv.reshape(-1, 2)
    is_leaf = np.isin(mat_idx, list(leaf_slots))
    keep_mask = ~is_leaf | (np.random.rand(npoly) < keep)
    # scale kept leaf faces around their centre (leaf cards have unshared vertices)
    for p in np.nonzero(is_leaf & keep_mask)[0]:
        vs = loop_vert[loop_start[p]:loop_start[p] + loop_total[p]]
        c = co[vs].mean(axis=0)
        co[vs] = c + (co[vs] - c) * scale
    kept = np.nonzero(keep_mask)[0]
    # rebuild mesh from kept polygons
    faces = [tuple(loop_vert[loop_start[p]:loop_start[p] + loop_total[p]].tolist()) for p in kept]
    new_uv = np.concatenate([uv[loop_start[p]:loop_start[p] + loop_total[p]] for p in kept]) if len(kept) else np.zeros((0, 2), np.float32)
    new_mat = mat_idx[kept]
    new = bpy.data.meshes.new(me.name + "_r")
    new.from_pydata(co.tolist(), [], faces)
    for m in me.materials:
        new.materials.append(m)
    new.polygons.foreach_set("material_index", new_mat.astype(np.int32))
    ul = new.uv_layers.new(name=uv_layer.name)
    ul.data.foreach_set("uv", new_uv.reshape(-1))
    new.update()
    obj.data = new
    # drop unused vertices
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.delete_loose()
    bpy.ops.object.mode_set(mode="OBJECT")

def decimate_trunk(obj, leaf_slots, ratio):
    me = obj.data
    if ratio >= 1.0 or len(me.polygons) == 0:
        return
    npoly = len(me.polygons)
    mat_idx = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("material_index", mat_idx)
    loop_start = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("loop_start", loop_start)
    loop_total = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("loop_total", loop_total)
    loop_vert = np.empty(len(me.loops), dtype=np.int32); me.loops.foreach_get("vertex_index", loop_vert)
    trunk = np.nonzero(~np.isin(mat_idx, list(leaf_slots)))[0]
    if len(trunk) == 0:
        return
    vidx = np.unique(np.concatenate([loop_vert[loop_start[p]:loop_start[p] + loop_total[p]] for p in trunk]))
    vg = obj.vertex_groups.new(name="trunk")
    vg.add(vidx.tolist(), 1.0, "REPLACE")
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.ratio = ratio
    mod.vertex_group = "trunk"
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier="dec")

for name in args:
    keys, keep, scale, ratio = CFG[name]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PH, name, name + ".gltf"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes:
        leaf_slots = {i for i, s in enumerate(o.material_slots) if is_leaf_mat(s.material, keys)}
        if leaf_slots and keep < 1.0:
            reduce_leaves(o, leaf_slots, keep, scale)
        decimate_trunk(o, leaf_slots, ratio)
    for i, o in enumerate(meshes):
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        for c in o.children_recursive:
            c.select_set(True)
        suffix = "" if len(meshes) == 1 else "_%s" % chr(ord("a") + i)
        out = os.path.join(OUT, name + suffix + ".glb")
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format="GLB", export_apply=True, export_image_format="JPEG", export_jpeg_quality=85)
        print("EXPORTED", out, "tris", tris, "MB", os.path.getsize(out) // 1048576, flush=True)

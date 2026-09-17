"""One-off, idempotent patch: wire recoil, hitmarker, new zombie types, inputs, ambience, deer, mushrooms."""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = os.path.join(ROOT, "godot")

def edit(rel, pairs):
    p = os.path.join(G, rel)
    s = open(p, encoding="utf-8").read()
    for a, b in pairs:
        if b in s:
            continue
        assert a in s, (rel, a[:60])
        s = s.replace(a, b, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("patched", rel)

edit("scripts/player.gd", [
    ("var _gravity := 20.0\n", "var _gravity := 20.0\nvar speed_mul := 1.0\nvar regen_mul := 1.0\nvar recoil_offset := Vector2.ZERO   # (pitch, yaw) radians of visual recoil still settling\n"),
    ("\tvar speed := SPRINT_SPEED if sprint else WALK_SPEED", "\tvar speed := (SPRINT_SPEED if sprint else WALK_SPEED) * speed_mul"),
    ("\t\thead.rotation.x = pitch\n", "\t\thead.rotation.x = pitch + recoil_offset.x\n"),
    ("\tcamera.rotation.z = (sin(bob * 0.5) * 0.004 if moving else 0.0) + sin(wobble * 30.0) * 0.02 * wobble\n",
     "\tcamera.rotation.z = (sin(bob * 0.5) * 0.004 if moving else 0.0) + sin(wobble * 30.0) * 0.02 * wobble\n\thead.rotation.x = pitch + recoil_offset.x\n\tcamera.rotation.y = recoil_offset.y\n"),
    ("\t\thp = minf(max_hp, hp + delta * 4.0)", "\t\thp = minf(max_hp, hp + delta * 4.0 * regen_mul)"),
])

edit("scripts/hud.gd", [
    ("var _damage_t := 0.0\n", "var _damage_t := 0.0\nvar _hit_t := 0.0\nvar hit_marks: Array = []\n"),
    ("\t# stats bottom-left", "\t# hitmarker: four short diagonal ticks around the crosshair\n\tfor k in 4:\n\t\tvar m := ColorRect.new()\n\t\tm.color = Color(1, 1, 1, 0.0)\n\t\tm.custom_minimum_size = Vector2(10, 2)\n\t\tm.set_anchors_preset(Control.PRESET_CENTER)\n\t\tm.pivot_offset = Vector2(5, 1)\n\t\tm.position = Vector2(-5, -1) + Vector2(cos(k * PI / 2.0 + PI / 4.0), sin(k * PI / 2.0 + PI / 4.0)) * 14.0\n\t\tm.rotation = k * PI / 2.0 + PI / 4.0\n\t\tm.mouse_filter = Control.MOUSE_FILTER_IGNORE\n\t\troot.add_child(m)\n\t\thit_marks.append(m)\n\t# stats bottom-left"),
    ("func damage_flash() -> void:", "func hitmarker(head: bool) -> void:\n\t_hit_t = 0.12\n\tfor m in hit_marks:\n\t\tm.color = Color(1.0, 0.25, 0.2, 1.0) if head else Color(1, 1, 1, 1)\n\nfunc damage_flash() -> void:"),
    ("\t\tdamage_rect.color.a = clampf(_damage_t * 3.0, 0.0, 0.45)", "\t\tdamage_rect.color.a = clampf(_damage_t * 3.0, 0.0, 0.45)\n\tif _hit_t > 0.0:\n\t\t_hit_t -= delta\n\t\tif _hit_t <= 0.0:\n\t\t\tfor m in hit_marks:\n\t\t\t\tm.color.a = 0.0"),
])

edit("scripts/sfx.gd", [
    ('\t\t"wood": st = _burst(0.3, 0.1, 0.3, 0.8)', '\t\t"wood": st = _burst(0.3, 0.1, 0.3, 0.8)\n\t\t"boom": st = _burst(1.6, 0.45, 0.05, 1.4, 45.0, -30.0)'),
])

zp = os.path.join(G, "scripts", "zombie.gd")
zs = open(zp, encoding="utf-8").read()
if '"nurse"' not in zs:
    out = []
    for ln in zs.split("\n"):
        if ln.strip().startswith('"brute":'):
            out.append('\t"brute":    { "model": "zombie_bloater", "fallback": "zombie_shambler", "hp": 320.0, "speed": 1.2, "damage": 25.0, "reach": 2.0, "attack_time": 1.6, "score": 40, "height": 2.3, "tint": Color(0.9, 0.85, 0.6) },')
            out.append('\t"nurse":    { "model": "zombie_nurse", "fallback": "zombie_runner", "hp": 80.0, "speed": 2.6, "damage": 10.0, "reach": 1.5, "attack_time": 0.9, "score": 15, "height": 1.7 },')
            out.append('\t"soldier":  { "model": "zombie_soldier", "fallback": "zombie_shambler", "hp": 180.0, "speed": 1.9, "damage": 16.0, "reach": 1.6, "attack_time": 1.0, "score": 25, "height": 1.85 },')
        else:
            out.append(ln)
    open(zp, "w", encoding="utf-8").write("\n".join(out))
    print("patched zombie types")
edit("scripts/zombie.gd", [
    ('\tvar scene = load("res://assets/models/%s.glb" % type["model"])', '\tvar path := "res://assets/models/%s.glb" % type["model"]\n\tif not ResourceLoader.exists(path) and type.has("fallback"):\n\t\tpath = "res://assets/models/%s.glb" % type["fallback"]\n\tvar scene = load(path) if ResourceLoader.exists(path) else null'),
])

edit("scripts/waves.gd", [
    ('\t\tif n >= 4 and r > 0.92:\n\t\t\tt = "brute"', '\t\tif n >= 2 and r > 0.7 and r < 0.85:\n\t\t\tt = "nurse"\n\t\tif n >= 3 and r > 0.85 and r < 0.93:\n\t\t\tt = "soldier"\n\t\tif n >= 4 and r > 0.93:\n\t\t\tt = "brute"'),
    ('\t\t\tweapons.add_ammo("pistol", 36)\n\t\t\tif weapons.unlocked["shotgun"]:\n\t\t\t\tweapons.add_ammo("shotgun", 12)', '\t\t\tweapons.refill_all()'),
])

def key(code):
    return '{\n"deadzone": 0.2,\n"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":%d,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)\n]\n}\n' % code
def mouse(btn, mask):
    return '{\n"deadzone": 0.2,\n"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":%d,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":%d,"canceled":false,"pressed":true,"double_click":false,"script":null)\n]\n}\n' % (mask, btn)
add = "weapon_3=" + key(51) + "weapon_4=" + key(52) + "weapon_5=" + key(53) + "grenade=" + key(71) + "skills=" + key(4194306) + "aim=" + mouse(2, 2) + "weapon_next=" + mouse(4, 8)
edit("project.godot", [("\n[layer_names]", add + "\n[layer_names]")])

edit("scripts/main.gd", [
    ("var waves: Waves\n", "var waves: Waves\nvar skills: Skills\nvar ambience: Ambience\n"),
    ("\twaves.setup(self, hud, player, weapons)\n", "\twaves.setup(self, hud, player, weapons)\n\tskills = Skills.new()\n\tadd_child(skills)\n\tskills.setup(player, weapons, hud, self)\n\tambience = Ambience.new()\n\tadd_child(ambience)\n\tambience.setup(player, Map.ground_pos(Map.FIRE.x, Map.FIRE.y), Map.ground_pos(-40.0, 36.0))\n\t_spawn_deer()\n"),
    ("func _build_foliage() -> void:", "func _spawn_deer() -> void:\n\tvar groups := [[Vector2(-70, -18), \"stag\"], [Vector2(-66, -14), \"deer\"], [Vector2(-64, -20), \"deer\"], [Vector2(25, 34), \"deer\"], [Vector2(28, 38), \"deer\"], [Vector2(70, 30), \"stag\"], [Vector2(74, 34), \"deer\"], [Vector2(-60, 30), \"deer\"]]\n\tvar i := 0\n\tfor g in groups:\n\t\tvar pos: Vector2 = g[0]\n\t\tvar kind: String = g[1]\n\t\tvar d := Deer.new()\n\t\td.setup(player, kind, _scene(kind), 100 + i)\n\t\tadd_child(d)\n\t\td.global_position = Map.ground_pos(pos.x, pos.y) + Vector3(0, 0.3, 0)\n\t\td.rotation.y = rng.randf() * TAU\n\t\ti += 1\n\nfunc _build_foliage() -> void:"),
    ("\t\t\t_place_real([\"boulder_01\", \"tree_stump_01\", \"dead_tree_trunk_02\"][i % 3], x, z, 0.8 + rng.randf() * 0.5, 0.8)", "\t\t\t_place_real([\"boulder_01\", \"tree_stump_01\", \"dead_tree_trunk_02\"][i % 3], x, z, 0.8 + rng.randf() * 0.5, 0.8)\n\t# mushrooms all over the forest floor\n\tfor i in 260:\n\t\tvar x: float = rng.randf_range(-105.0, 50.0)\n\t\tvar z: float = rng.randf_range(-40.0, 64.0)\n\t\tif Map.leaf_weight(x, z) < 0.6 or Map.on_road(x, z, 1.0) or Map.in_building(x, z, 1.0):\n\t\t\tcontinue\n\t\tvar kind := \"mushroom_cluster\" if rng.randf() < 0.7 else \"mushroom_fly\"\n\t\t_place(kind, x, z, 0.18 + rng.randf() * 0.2, -1.0, 1.0, 0.0)"),
    ("\tif Input.is_action_just_pressed(\"pause\"):\n\t\t_pause()", "\tif Input.is_action_just_pressed(\"pause\"):\n\t\tif skills and skills.is_open:\n\t\t\tskills.close()\n\t\telse:\n\t\t\t_pause()"),
])
print("done")

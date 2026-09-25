# Firearms with recoil and sights, selectable melee weapons, and hand grenades.
class_name Weapons
extends Node3D

const Aim = preload("res://scripts/aim_model.gd")

const Mods = preload("res://scripts/weapon_mods.gd")

const Hands = preload("res://scripts/viewmodel_hands.gd")
const Viewmodel = preload("res://scripts/viewmodel_viewport.gd")
const Effects = preload("res://scripts/weapon_effects.gd")
const MeleeModels = preload("res://scripts/melee_models.gd")
const Attachments = preload("res://scripts/weapon_attachments.gd")
const Specials = preload("res://scripts/weapon_specials.gd")

const DEFS := {
	"knife": {"name": "Field Knife", "model": "knife_real", "melee": true, "height": 0.37, "stab_damage": 110.0, "stab_rate": 0.85, "stab_range": 4.4, "mag": 0, "reserve": 0, "damage": 55.0, "rate": 0.42, "reload": 1.0, "pellets": 1, "spread": 0.0, "range": 1.85, "auto": false, "sfx": "knife_swing", "shove": 3.5,
		"pos": Vector3(0.29, -0.23, -0.57), "ads": Vector3(0.29, -0.23, -0.57), "kick_pitch": 0.0, "kick_yaw": 0.0, "kick_back": 0.0, "recover": 8.0},
	"hatchet": {"name": "Forest Axe", "model": "hatchet_real", "melee": true, "height": 0.57, "stab_damage": 225.0, "stab_rate": 1.45, "stab_range": 5.0, "mag": 0, "reserve": 0, "damage": 125.0, "rate": 0.95, "reload": 1.0, "pellets": 1, "spread": 0.0, "range": 2.35, "auto": false, "sfx": "melee", "shove": 7.0,
		"pos": Vector3(0.28, -0.30, -0.65), "ads": Vector3(0.28, -0.30, -0.65), "kick_pitch": 0.0, "kick_yaw": 0.0, "kick_back": 0.0, "recover": 5.0},
	"pistol":   { "name": "Pistol", "model": "pistol", "height": 0.11, "mag": 12, "reserve": 72, "damage": 34.0, "rate": 0.16, "reload": 1.1, "pellets": 1, "spread": 0.012, "range": 60.0, "auto": false, "sfx": "pistol", "sfx_db": 2.0,
				  "pos": Vector3(0.26, -0.21, -0.5), "ads": Vector3(0.0, -0.13, -0.38), "kick_pitch": 2.6, "kick_yaw": 0.75, "kick_back": 0.08, "recover": 7.0 },
	"revolver": { "name": "Revolver", "model": "revolver", "height": 0.13, "mag": 6, "reserve": 30, "damage": 95.0, "rate": 0.45, "reload": 2.2, "pellets": 1, "spread": 0.008, "range": 80.0, "auto": false, "sfx": "revolver", "sfx_db": -11.0,
				  "pos": Vector3(0.26, -0.21, -0.5), "ads": Vector3(0.0, -0.13, -0.38), "kick_pitch": 6.8, "kick_yaw": 1.6, "kick_back": 0.15, "recover": 5.5 },
	"smg":      { "name": "MP5", "model": "smg", "height": 0.16, "mag": 30, "reserve": 120, "damage": 22.0, "rate": 0.075, "reload": 1.6, "pellets": 1, "spread": 0.03, "range": 45.0, "auto": true, "sfx": "smg", "sfx_db": 0.0,
				  "pos": Vector3(0.24, -0.22, -0.55), "ads": Vector3(0.0, -0.135, -0.4), "kick_pitch": 1.35, "kick_yaw": 0.65, "kick_back": 0.055, "recover": 9.0 },
	"ak47":     { "name": "AK-47", "model": "ak47", "height": 0.18, "mag": 30, "reserve": 90, "damage": 42.0, "rate": 0.1, "reload": 2.0, "pellets": 1, "spread": 0.022, "range": 90.0, "auto": true, "sfx": "ak47", "sfx_db": -17.0,
				  "pos": Vector3(0.24, -0.23, -0.58), "ads": Vector3(0.0, -0.14, -0.42), "kick_pitch": 2.2, "kick_yaw": 1.05, "kick_back": 0.085, "recover": 7.5 },
	"shotgun":  { "name": "Shotgun", "model": "rifle", "height": 0.16, "mag": 6, "reserve": 24, "damage": 22.0, "rate": 0.85, "reload": 2.0, "pellets": 8, "spread": 0.07, "range": 28.0, "auto": false, "sfx": "shotgun", "sfx_db": -7.0,
				  "pos": Vector3(0.22, -0.24, -0.6), "ads": Vector3(0.0, -0.15, -0.45), "kick_pitch": 8.0, "kick_yaw": 2.0, "kick_back": 0.19, "recover": 4.5 },
	"marksman": {"name": "Ranger .308", "scope_zoom": 4.0, "model": "marksman", "pierce_targets": 3, "pierce_retention": 0.75, "height": 0.20, "mag": 5, "reserve": 10, "damage": 165.0, "rate": 1.15, "reload": 2.8, "pellets": 1, "spread": 0.0025, "range": 150.0, "auto": false, "sfx": "revolver", "sfx_db": -10.0,
		"pos": Vector3(0.24, -0.23, -0.62), "ads": Vector3(0, -0.15, -0.46), "kick_pitch": 7.0, "kick_yaw": 1.0, "kick_back": 0.16, "recover": 4.0},
	"lmg": {"name": "MG-60", "model": "lmg", "pierce_targets": 2, "pierce_retention": 0.65, "height": 0.23, "mag": 60, "reserve": 120, "damage": 40.0, "rate": 0.085, "reload": 4.2, "pellets": 1, "spread": 0.034, "range": 85.0, "auto": true, "sfx": "ak47", "sfx_db": -16.0, "sfx_pitch": 0.88,
		"pos": Vector3(0.25, -0.27, -0.64), "ads": Vector3(0, -0.16, -0.46), "kick_pitch": 2.0, "kick_yaw": 1.4, "kick_back": 0.085, "recover": 7.0},
	"breacher": {"name": "Nightbreaker 12", "model": "breacher", "height": 0.20, "mag": 8, "reserve": 16, "damage": 25.0, "rate": 0.5, "reload": 3.3, "pellets": 9, "spread": 0.075, "range": 25.0, "auto": false, "sfx": "shotgun", "sfx_db": -6.0,
		"pos": Vector3(0.24, -0.24, -0.6), "ads": Vector3(0, -0.15, -0.46), "kick_pitch": 8.5, "kick_yaw": 2.2, "kick_back": 0.19, "recover": 4.8},
	"titanbreaker": {"name": "Titanbreaker .50", "scope_zoom": 4.0, "model": "titanbreaker", "pierce_targets": 5, "pierce_retention": 0.8, "height": 0.23, "mag": 4, "reserve": 8, "damage": 420.0, "rate": 1.9, "reload": 4.2, "pellets": 1, "spread": 0.003, "range": 180.0, "auto": false, "sfx": "revolver", "sfx_db": -6.0, "sfx_pitch": 0.72, "titan_multiplier": 1.75,
		"pos": Vector3(0.24, -0.26, -0.68), "ads": Vector3(0, -0.16, -0.48), "kick_pitch": 12.0, "kick_yaw": 1.6, "kick_back": 0.23, "recover": 3.2},
	# --- Erweiterung September 2026: zwei Pistolen, zwei MPs, zwei Praezisionswaffen, zwei schwere ---
	# Optionale Felder neben den 19 Pflichtfeldern: "special" (Mechanik, siehe weapon_specials.gd),
	# "element" (Brand/Frost ueber rare_market), "flash_mode" (Muendungsfarbe aus WeaponEffects.MODES),
	# "reserve_factor" (Reservelimit statt der pauschalen x4), "mod_block" (Mods, die diese Waffe nicht
	# traegt), "bloom_gain", "move_mul(_spun)", "no_reload", "scope_style", "kick_cap"/"kick_model_cap".
	"deagle": {"name": "Desert Eagle .50", "model": "deagle", "height": 0.15, "mag": 7, "reserve": 42, "reserve_factor": 6, "damage": 118.0, "rate": 0.34, "reload": 2.0, "pellets": 1, "spread": 0.013, "range": 65.0, "auto": false, "sfx": "deagle", "sfx_db": -4.0, "sfx_pitch": 0.94, "flash_scale": 1.35,
		"mod_block": ["extended", "endless"],
		"pos": Vector3(0.26, -0.21, -0.5), "ads": Vector3(0.0, -0.13, -0.38), "kick_pitch": 9.5, "kick_yaw": 2.1, "kick_back": 0.20, "recover": 4.2},
	"flare_pistol": {"name": "Flare Pistol", "model": "flare_pistol", "height": 0.14, "mag": 1, "reserve": 12, "reserve_factor": 14, "damage": 45.0, "rate": 0.9, "reload": 1.9, "pellets": 1, "spread": 0.020, "range": 40.0, "auto": false, "sfx": "flare", "sfx_db": -9.0, "flash_scale": 1.6, "flash_mode": "fire", "element": "fire",
		"special": {"kind": "flare", "speed": 44.0, "impact": 0.0, "splash": 20.0, "radius": 3.5, "burn_time": 4.0, "splash_ignites": false, "light_range": 12.0, "flare_life": 8.0},
		"mod_block": ["extended", "endless", "match_barrel", "compensator"],
		"pos": Vector3(0.26, -0.20, -0.5), "ads": Vector3(0.0, -0.13, -0.38), "kick_pitch": 4.4, "kick_yaw": 1.2, "kick_back": 0.11, "recover": 6.0},
	"mac10": {"name": "MAC-10 SD", "model": "mac10", "height": 0.17, "mag": 40, "reserve": 160, "damage": 20.0, "rate": 0.055, "reload": 1.9, "pellets": 1, "spread": 0.040, "range": 30.0, "auto": true, "sfx": "mac10", "sfx_db": -8.0, "sfx_pitch": 1.04, "flash_scale": 0.18, "bloom_gain": 0.10,
		"mod_block": ["suppressor", "ghost", "compensator", "endless"],
		"pos": Vector3(0.24, -0.22, -0.56), "ads": Vector3(0.0, -0.135, -0.41), "kick_pitch": 1.15, "kick_yaw": 0.5, "kick_back": 0.045, "recover": 10.0},
	"cryo_smg": {"name": "Cryo SMG C7", "model": "cryo_smg", "height": 0.18, "mag": 35, "reserve": 140, "damage": 22.0, "rate": 0.07, "reload": 2.3, "pellets": 1, "spread": 0.032, "range": 40.0, "auto": true, "sfx": "cryo", "sfx_db": -11.0, "flash_scale": 0.7, "flash_mode": "frost", "element": "frost",
		"special": {"kind": "chill", "per_hit": 0.55, "titan_scale": 0.4, "chill_slow": 0.78, "freeze_time": 3.0, "after_freeze": 0.45, "brittle_mul": 1.4},
		"mod_block": ["compensator", "match_barrel"],
		"pos": Vector3(0.24, -0.23, -0.57), "ads": Vector3(0.0, -0.14, -0.42), "kick_pitch": 1.5, "kick_yaw": 0.7, "kick_back": 0.05, "recover": 9.5},
	"lever_rifle": {"name": "Lever Action .45-70", "scope_zoom": 3.0, "scope_style": "vintage", "model": "lever_rifle", "pierce_targets": 2, "pierce_retention": 0.7, "height": 0.21, "mag": 6, "reserve": 30, "damage": 125.0, "rate": 0.60, "reload": 3.4, "pellets": 1, "spread": 0.005, "range": 130.0, "auto": false, "sfx": "lever", "sfx_db": 1.0, "sfx_pitch": 0.92,
		"special": {"kind": "cycle", "at": 0.45, "sfx": "lever_cycle", "roll": 0.9},
		"mod_block": ["extended", "endless"],
		"pos": Vector3(0.24, -0.23, -0.63), "ads": Vector3(0, -0.15, -0.47), "kick_pitch": 5.6, "kick_yaw": 1.1, "kick_back": 0.14, "recover": 5.0},
	"plasma_sniper": {"name": "Plasma Rifle", "scope_zoom": 5.0, "scope_style": "digital", "model": "plasma_sniper", "pierce_targets": 2, "pierce_retention": 0.8, "height": 0.25, "mag": 6, "reserve": 30, "reserve_factor": 5, "damage": 210.0, "rate": 0.85, "reload": 3.6, "pellets": 1, "spread": 0.0035, "range": 170.0, "auto": false, "sfx": "plasma", "sfx_db": -8.0, "sfx_pitch": 0.9, "flash_scale": 1.2, "flash_mode": "plasma",
		"special": {"kind": "heat", "per_shot": 0.17, "cool": 0.22, "idle": 0.6, "regen": 0.55, "cold": 0.15, "vent_floor": 0.6, "vent_sfx": "plasma_vent"},
		"mod_block": ["suppressor", "ghost", "compensator", "extended", "endless", "quick_action"],
		"pos": Vector3(0.25, -0.26, -0.68), "ads": Vector3(0, -0.16, -0.50), "kick_pitch": 2.8, "kick_yaw": 0.6, "kick_back": 0.09, "recover": 6.5},
	"minigun": {"name": "Minigun M134", "model": "minigun", "height": 0.26, "mag": 150, "reserve": 300, "reserve_factor": 2, "damage": 32.0, "rate": 0.055, "reload": 6.5, "pellets": 1, "spread": 0.040, "range": 70.0, "auto": true, "sfx": "minigun", "sfx_db": -6.0, "flash_scale": 1.5, "bloom_gain": 0.05, "move_mul": 0.55, "move_mul_spun": 0.42,
		"special": {"kind": "spin", "up": 0.85, "down": 0.9, "hold": 0.25, "penalty": 3.2, "loop_sfx": "minigun_loop", "start_sfx": "minigun_spinup", "stop_sfx": "minigun_spindown"},
		"mod_block": ["suppressor", "ghost", "compensator", "match_barrel", "extended", "endless"],
		"pos": Vector3(0.23, -0.26, -0.60), "ads": Vector3(0.16, -0.24, -0.56), "kick_pitch": 0.9, "kick_yaw": 1.6, "kick_back": 0.03, "recover": 11.0},
	"graviton_cannon": {"name": "Graviton Cannon", "model": "graviton_cannon", "pierce_targets": 3, "pierce_retention": 0.9, "titan_multiplier": 2.4, "height": 0.26, "mag": 2, "reserve": 10, "reserve_factor": 5, "damage": 240.0, "rate": 2.4, "reload": 4.6, "pellets": 1, "spread": 0.014, "range": 60.0, "auto": false, "sfx": "graviton", "sfx_db": -2.0, "sfx_pitch": 0.88, "flash_scale": 2.2, "flash_mode": "graviton",
		"special": {"kind": "blast", "radius": 6.0, "damage": 400.0, "edge": 0.25, "self_damage": 60.0, "self_share": 0.7, "charge_sfx": "graviton_charge"},
		"mod_block": ["suppressor", "ghost", "compensator", "match_barrel", "extended", "endless"],
		"kick_cap": Vector2(0.30, 0.10), "kick_model_cap": Vector3(0.52, 0.07, 0.22),
		"pos": Vector3(0.22, -0.25, -0.62), "ads": Vector3(0.05, -0.18, -0.52), "kick_pitch": 14.0, "kick_yaw": 1.2, "kick_back": 0.30, "recover": 2.4},
}
const ORDER := ["pistol", "deagle", "revolver", "flare_pistol", "smg", "mac10", "cryo_smg", "ak47", "shotgun",
	"breacher", "lever_rifle", "marksman", "plasma_sniper", "lmg", "minigun", "titanbreaker", "graviton_cannon", "knife", "hatchet"]
const HIT_RAY_LENGTH := 600.0   # longer than the map diagonal

static func piercing_description(id: String, effective: Dictionary = {}) -> String:
	var spec: Dictionary = DEFS[id] if effective.is_empty() else effective
	if not spec.has("pierce_targets"): return ""
	return Lang.t("Penetration: up to %d zombies; each further target takes %d%% of the previous damage. Walls stop the bullet.", [spec.pierce_targets, roundi(float(spec.pierce_retention) * 100.0)])

var player: Player
var hud: Hud
var camera: Camera3D
var viewmodel: ViewmodelViewport
var state := {}
var current := "pistol"
var _last_firearm := "pistol"
var unlocked := { "pistol": true, "revolver": false, "smg": false, "ak47": false, "shotgun": false }
var skins: Dictionary = {}
var mod_owned: Dictionary = {}
var mod_loadout: Dictionary = {}
var recoil := 0.0
var sway_t := 0.0
var flash: OmniLight3D
var flash_mesh: MeshInstance3D
var effects: WeaponEffects
var specials: WeaponSpecials   # heat, spin-up, freeze build-up, flares, graviton blast
var _model_kick := Vector3.ZERO # pitch (radians), roll (radians), rearward distance
var _model_velocity := Vector3.ZERO
var zombies_root: Node3D
# upgrades (from the skill menu)
var damage_mul := 1.0
var reload_mul := 1.0
var spread_mul := 1.0
var grenades := 2
var grenades_max := 2
# recoil state
var kick_pitch := 0.0
var kick_yaw := 0.0
var ads := 0.0
var _shots_in_burst := 0
var _burst_t := 0.0
var _aim_kick := Vector2.ZERO
var _bloom := 0.0
var _grenade_scene: PackedScene
var _blood_pool: Array[GPUParticles3D] = []
var _blood_next := 0
var _melee_t := 0.0
var _melee_anim := 0.0
var _melee_stab := false
var _melee_duration := 0.42
var server_proxy := false
var network_apply := false

func setup_proxy(p: Player, h: Hud, zr: Node3D) -> void:
	server_proxy = true
	player = p
	hud = h
	camera = p.camera
	zombies_root = zr
	specials = Specials.for_scene(_scene_root(), DEFS)
	for id in DEFS:
		unlocked[id] = id in ["pistol", "knife"]
		state[id] = {"def": DEFS[id], "ammo": DEFS[id].mag, "reserve": DEFS[id].reserve, "cooldown": 0.0, "reloading": 0.0}
	_grenade_scene = load("res://assets/models/grenade.glb")

func setup(p: Player, h: Hud, zr: Node3D) -> void:
	player = p
	hud = h
	camera = p.camera
	zombies_root = zr
	specials = Specials.for_scene(_scene_root(), DEFS)
	for i in range(6, 11):
		var action := "weapon_%d" % i
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = KEY_0 if i == 10 else KEY_0 + i
			InputMap.action_add_event(action, key)
	viewmodel = Viewmodel.new()
	add_child(viewmodel)
	for id in DEFS:
		unlocked[id] = id in ["pistol", "knife"]
		var d: Dictionary = DEFS[id]
		var holder := Node3D.new()
		holder.position = d["pos"]
		var path := "res://assets/models/%s.glb" % d["model"]
		var scene = load(path) if ResourceLoader.exists(path) else null
		var weapon_model: Node3D = null
		if is_melee(id):
			holder.add_child(MeleeModels.build(id))
		elif scene:
			var model: Node3D = scene.instantiate()
			weapon_model = model
			# The Meshy barrels point along -X; rotate them towards camera forward (-Z).
			model.rotation.y = -PI / 2.0
			var inner := Node3D.new()
			inner.add_child(model)
			holder.add_child(inner)
			_fit_height(model, d["height"])
			for m in model.find_children("*", "MeshInstance3D", true, false):
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.04, 0.06, 0.3)
			box.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.12, 0.12, 0.13)
			box.material_override = mat
			holder.add_child(box)
		holder.visible = false
		viewmodel.camera.add_child(holder)
		for mesh in holder.find_children("*", "MeshInstance3D", true, false):
			mesh.set_meta("weapon_surface", true)
		var bounds := Hands.weapon_bounds(holder)
		var hands := Hands.build(id, bounds)
		holder.add_child(hands)
		for mesh in holder.find_children("*", "MeshInstance3D", true, false):
			mesh.layers = 2
		var aim_position: Vector3 = d["ads"]
		aim_position.y = -bounds.end.y - 0.008
		aim_position.z = minf(aim_position.z, -bounds.end.z - 0.18)
		# Mods hang on the weapon only after the grips, the sight line and the bounds are settled,
		# so a suppressor can never shift where the hands sit or where the gun aims.
		var mods: WeaponAttachments = null
		if weapon_model and Attachments.supported(d["model"]):
			mods = Attachments.new()
			mods.setup(d["model"], weapon_model, holder)
			holder.add_child(mods)
			mods.refresh(mod_loadout.get(id, {}))
		state[id] = { "def": d, "ammo": d["mag"], "reserve": d["reserve"], "node": holder, "hands": hands, "bounds": bounds, "aim_position": aim_position, "mods": mods, "cooldown": 0.0, "reloading": 0.0 }
	# Gentle light on the view model keeps hands readable in deep forest shade.
	var view_light := DirectionalLight3D.new()
	view_light.light_cull_mask = 2
	view_light.light_color = Color(0.9, 0.94, 1.0)
	view_light.light_energy = 0.7
	view_light.shadow_enabled = false
	view_light.rotation_degrees = Vector3(-18, -20, 0)
	view_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	viewmodel.camera.add_child(view_light)
	effects = Effects.new()
	viewmodel.camera.add_child(effects)
	effects.setup(camera)
	flash = effects.world_light
	flash_mesh = effects.front
	var gp := "res://assets/models/grenade.glb"
	_grenade_scene = load(gp) if ResourceLoader.exists(gp) else null
	set_weapon("pistol")
	_prepare_blood_pool()

# setup() runs from main._ready, where the tree has no current_scene yet, and a co-op proxy hangs
# under its Player rather than under the scene. Walking up to the node that owns the progression
# finds the real game root in both cases.
func _scene_root() -> Node:
	var node: Node = self
	while node != null:
		if "progression" in node: return node
		node = node.get_parent()
	return get_tree().current_scene

static func _fit_height(node: Node3D, height: float) -> void:
	var aabb := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).get_aabb()
		var t: Transform3D = node.global_transform.affine_inverse() * (m as Node3D).global_transform if node.is_inside_tree() else (m as Node3D).transform
		b = t * b
		aabb = b if first else aabb.merge(b)
		first = false
	if aabb.size.y > 0.0:
		var s := height / aabb.size.y
		node.scale = Vector3.ONE * s
		node.position = Vector3(-aabb.get_center().x * s, -aabb.get_center().y * s, -aabb.get_center().z * s)

func cur() -> Dictionary:
	return state[current]

func effective_damage_mul() -> float:
	return damage_mul * player.mushroom_multiplier("damage") * player.relic_multiplier("damage")

func effective_reload_mul() -> float:
	return reload_mul * player.mushroom_multiplier("reload") * player.relic_multiplier("reload")

static func is_melee(id: String) -> bool:
	return DEFS.get(id, {}).get("melee", false)

func ammo_weapon() -> String:
	return (_last_firearm if unlocked.get(_last_firearm, false) else "pistol") if is_melee(current) else current

func set_weapon(id: String) -> void:
	if not DEFS.has(id):
		return
	if not unlocked.get(id, false):
		hud.message(Lang.t("Buy the %s from the weapon trader", [DEFS[id]["name"]]), 1.4)
		return
	if current != id:
		Sfx.stop_fire_loop(self)
		if is_inside_tree(): Sfx.play(self, "weapon_switch", -10.0)
		_aim_kick = Vector2.ZERO
		_bloom = 0.0
		_shots_in_burst = 0
		kick_pitch = 0.0
		kick_yaw = 0.0
		player.recoil_offset = Vector2.ZERO
	if specials and current != id: specials.on_switch(self, current, id)
	if not is_melee(id): _last_firearm = id
	if server_proxy:
		if current != id:
			cur().reloading = 0.0
			current = id
		return
	if NetSession.is_client() and not network_apply and id != current:
		NetSession.command("weapon", [id])
	if current == id and cur()["node"].visible:
		return
	cur()["reloading"] = 0.0
	(cur()["hands"] as ViewmodelHands).reset_motion()
	for s in state.values():
		s["node"].visible = false
	current = id
	_melee_anim = 0.0
	cur()["node"].visible = true
	cur()["reloading"] = 0.0
	ads = 0.0
	_reset_scope()
	_shots_in_burst = 0
	_model_kick = Vector3.ZERO
	_model_velocity = Vector3.ZERO
	recoil = 0.0
	effects.cancel_flash()
	(cur()["hands"] as ViewmodelHands).reset_motion()
	var holder: Node3D = cur()["node"]
	holder.position = cur()["def"]["pos"]
	holder.rotation = Vector3.ZERO
	if is_melee(current): (cur()["hands"] as ViewmodelHands).anchor_melee_elbows(viewmodel.camera)
	effects.sync_muzzle(muzzle_transform())
	if current == "minigun":
		var attachments: WeaponAttachments = cur().get("mods")
		if attachments: effects.sync_second_muzzle((cur().node as Node3D).transform * Transform3D(Basis.IDENTITY, attachments.second_bore_tip()))
	hud.set_reload(0.0, 1.0)
	update_hud()

func unlock(id: String) -> void:
	unlocked[id] = true

func has_ammo_space(id: String) -> bool:
	return not is_melee(id) and state.has(id) and int(state[id]["reserve"]) < reserve_limit(id)

func add_ammo(id: String, n: int) -> void:
	state[id]["reserve"] = mini(reserve_limit(id), int(state[id]["reserve"]) + n)
	update_hud()

func reserve_limit(id: String) -> int:
	# The pistol is the safety net and carries eight magazines; everything else states its own depth
	# of pockets. A belt fed minigun under the old blanket factor would haul 600 spare rounds.
	return int(DEFS[id].mag) * int(DEFS[id].get("reserve_factor", 8 if id == "pistol" else 4))

func refill_all() -> void:
	# A survival safety net, not unlimited free ammunition for the strongest gun.
	state["pistol"].reserve = maxi(int(state["pistol"].reserve), 36)
	update_hud()

func mod_definition(id: String, slot: String, mod_id: String) -> Dictionary:
	var loadout: Dictionary = mod_loadout.get(id, {}).duplicate()
	if mod_id.is_empty(): loadout.erase(slot)
	else: loadout[slot] = mod_id
	return Mods.definition(DEFS[id], loadout)

func equip_mod(id: String, slot: String, mod_id: String) -> void:
	var definition := mod_definition(id, slot, mod_id)
	if not mod_loadout.has(id): mod_loadout[id] = {}
	if mod_id.is_empty(): mod_loadout[id].erase(slot)
	else: mod_loadout[id][slot] = mod_id
	var overflow := maxi(0, int(state[id].ammo) - int(definition.mag))
	state[id].ammo -= overflow
	state[id].reserve += overflow
	state[id].reloading = 0.0
	state[id].def = definition
	refresh_attachments(id)
	update_hud()

func apply_mod_snapshot(owned: Dictionary, loadout: Dictionary) -> void:
	if mod_owned == owned and mod_loadout == loadout: return
	mod_owned = owned.duplicate(true)
	mod_loadout = loadout.duplicate(true)
	for wid in state:
		state[wid].def = Mods.definition(DEFS[wid], mod_loadout.get(wid, {}))
		refresh_attachments(wid)

# Every path that changes a loadout - shop, snapshot from the host, test code - ends up here.
func refresh_attachments(id: String) -> void:
	if server_proxy or not state.has(id): return
	var mods: WeaponAttachments = state[id].get("mods")
	if mods: mods.refresh(mod_loadout.get(id, {}))

func apply_skin(id: String, finish: String) -> void:
	if not state.has(id) or skins.get(id, "__unset") == finish: return
	skins[id] = finish
	if not server_proxy: WeaponSkins.apply(state[id].node, finish, true)


func update_hud() -> void:
	var s := cur()
	hud.set_ammo(s["ammo"], s["reserve"], Lang.t("%s   ·   Grenades %d", [s["def"]["name"], grenades]))
	var scene := get_tree().current_scene
	if not server_proxy and scene and "progression" in scene and scene.progression and scene.progression.rare_market:
		hud.ammo_label.text += scene.progression.rare_market.ammo_label(player.peer_id)
	if is_melee(current) and not server_proxy:
		# The big readout is right-aligned and grows leftwards into the quick bar, so it keeps the
		# short word and the controls go on the quiet line underneath.
		hud.ammo_label.text = "Melee"
		hud.weapon_label.text += "   ·   " + (Lang.t("LMB slash / RMB stab") if current == "knife" else Lang.t("LMB light / RMB heavy"))

func reload() -> void:
	if is_melee(current): return
	# An energy rifle has no magazine: R dumps the heat early instead of changing one.
	if specials and specials.manual_vent(self, current):
		if NetSession.is_client() and not network_apply: NetSession.command("reload")
		return
	var s := cur()
	if s["reloading"] > 0.0 or s["ammo"] == s["def"]["mag"] or s["reserve"] <= 0:
		return
	s["reloading"] = float(s["def"]["reload"]) * effective_reload_mul()
	Sfx.stop_fire_loop(self, false)
	if NetSession.is_client() and not network_apply:
		NetSession.command("reload")
	if not server_proxy:
		Sfx.play(self, "reload", -8.0)

func effective_spread() -> float:
	var d: Dictionary = cur().def
	if is_melee(current): return 0.0
	return Aim.spread(float(d.spread), ads, Vector2(player.velocity.x, player.velocity.z).length(), player.velocity.y, _bloom, spread_mul * player.mushroom_multiplier("spread") * player.relic_multiplier("spread") * player.stance_precision())

func aim_direction() -> Vector3:
	# Scoped fire follows the optic centre; hip/iron sights also show free recoil.
	var free_aim := 1.0 - ads if cur().def.has("scope_zoom") else 1.0 - ads * 0.65
	var offset := _aim_kick * free_aim
	return (camera.global_basis * Vector3(tan(offset.y), tan(offset.x), -1)).normalized()

func update_reticle() -> void:
	if server_proxy or hud.crosshair_parts.is_empty(): return
	var centre := camera.global_position + aim_direction() * 10.0
	var point := camera.unproject_position(centre)
	var edge := camera.unproject_position(centre + camera.global_basis.x * effective_spread() * 10.0)
	hud.crosshair_parts[0].update_aim(point, point.distance_to(edge), ads, _bloom)
	var displacement := point - camera.get_viewport().get_visible_rect().size * 0.5
	for i in hud.hit_marks.size():
		var angle := float(i) * PI * 0.5 + PI * 0.25
		hud.hit_marks[i].position = displacement + Vector2(-5, -1) + Vector2.from_angle(angle) * 14.0

func try_fire() -> void:
	if not player.active or not player.alive or player.mounted_tower or player.controlling_drone:
		return
	if is_melee(current):
		melee()
		return
	var s := cur()
	if s["cooldown"] > 0.0 or s["reloading"] > 0.0:
		return
	if specials and specials.blocks_fire(self, current):
		return
	if s["ammo"] <= 0:
		s["cooldown"] = 0.2
		Sfx.play(self, "empty", -10.0)
		reload()
		return
	var d: Dictionary = s["def"]
	var shot_direction := aim_direction()
	var shot_spread := effective_spread()
	var field = get_tree().current_scene.get("cornfield")
	if field: field.scare(player.global_position)
	s["ammo"] -= 1
	# The rotary gun's barrels have to come up to speed: its interval shrinks as the spin rises.
	var rate_factor: float = specials.rate_multiplier(self, current) if specials else 1.0
	s["cooldown"] = maxf(s["cooldown"], -float(d["rate"])) + float(d["rate"]) * rate_factor
	recoil = 1.0
	# A weapon with its own element colours itself - it does not consume the bought rounds, so it
	# must not wear their colour either.
	var shot_mode: String = get_tree().current_scene.progression.rare_market.round_mode(player)
	if specials: shot_mode = specials.flash_mode(current, shot_mode)
	if not server_proxy:
		Sfx.play(self, d["sfx"], float(d.get("sfx_db", -6.0)), float(d.get("sfx_pitch", 1.0)))
		effects.fire(current, muzzle_transform(), player.velocity, float(d.get("flash_scale", 1.0)), shot_mode)
	if specials:
		specials.on_shot(self, current, (camera.global_transform * muzzle_transform()).origin, shot_direction)
	# recoil climbs while holding the trigger, drifts sideways, less when aiming
	_shots_in_burst += 1
	_burst_t = 0.32
	var climb := minf(1.0 + _shots_in_burst * 0.16, 2.4)
	var aim_f := (1.0 - ads * 0.25) * player.relic_multiplier("recoil")
	var impulse := Vector3(deg_to_rad(float(d["kick_pitch"]) * 2.2 + 1.0), deg_to_rad(1.0 if _shots_in_burst % 2 == 0 else -1.0), float(d["kick_back"]) * 0.90) * aim_f
	_model_kick += impulse * 0.25
	_model_velocity += impulse * (22.0 + float(d["recover"])) * 1.7
	if not server_proxy:
		(s["hands"] as ViewmodelHands).shot_impulse(0.6 + float(d["kick_pitch"]) * 0.16)
	kick_pitch += float(d["kick_pitch"]) * climb * aim_f * randf_range(0.85, 1.15)
	kick_yaw += float(d["kick_yaw"]) * aim_f * randf_range(-1.0, 1.0) * (1.0 if _shots_in_burst % 2 == 0 else -0.6)
	var precision_control := sqrt(maxf(0.25, spread_mul))
	var lateral := sin(float(_shots_in_burst) * 1.7) * 0.6 + sin(float(_shots_in_burst) * 0.43) * 0.4
	_aim_kick += Vector2(deg_to_rad(float(d.kick_pitch)) * 0.28, deg_to_rad(float(d.kick_yaw)) * lateral * 0.45) * climb * aim_f * precision_control
	# A heavy weapon may throw the aim further than the standard ceiling allows.
	var kick_cap: Vector2 = d.get("kick_cap", Vector2(0.16, 0.10))
	_aim_kick = _aim_kick.clamp(Vector2(-kick_cap.x * 0.31, -kick_cap.y), kick_cap)
	_bloom = minf(1.0, _bloom + float(d.get("bloom_gain", 0.14 if d.auto else 0.22)))
	player.wobble = maxf(player.wobble, 0.35)
	if NetSession.is_client():
		NetSession.command("fire", [current, ads, camera.global_rotation.y, camera.global_rotation.x])
		update_hud()
		return
	if NetSession.enabled:
		NetSession.weapon_fired(player.peer_id, current)
	var origin := camera.global_position
	var base := shot_direction
	var spread := shot_spread
	var scene := get_tree().current_scene
	var stats: RunStats = scene.stats if "stats" in scene else null
	if stats:
		stats.shots += 1
	var rare = scene.progression.rare_market
	# A weapon with its own element leaves the bought rounds alone; bought rounds still win when
	# both are present, because the player paid for them.
	var special_round: String = "" if d.has("element") else rare.consume_round(player)
	var trace_mode := "cryo" if current == "cryo_smg" else ("plasma" if current == "plasma_sniper" else special_round)
	var any_hit := false
	# Barricade boxes block movement across the entire line, including visible gaps.
	# Exclude only those boxes from bullets; towers, walls and terrain still stop shots.
	var bullet_exclude: Array[RID] = [player.get_rid()]
	for barrier_body: StaticBody3D in get_tree().get_nodes_in_group("barricade"):
		bullet_exclude.append(barrier_body.get_rid())
	for i in int(d["pellets"]):
		var dir: Vector3 = Aim.sample_direction(base, camera.global_basis.x, camera.global_basis.y, spread, randf(), randf() * TAU)
		# the ray crosses the whole map: enemies are hit at any distance, "range" only starts a gentle damage
		# falloff (full damage inside it, 55 % at three times the range)
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * HIT_RAY_LENGTH, Zombie.SHOT_MASK)
		q.collide_with_areas = true
		q.hit_from_inside = true
		var excluded: Array[RID] = bullet_exclude.duplicate()
		var victims := 0
		# Where this pellet ends up. An area weapon detonates there, hit or miss.
		var impact := origin + dir * minf(HIT_RAY_LENGTH, float(d["range"]) * 2.5)
		# One ray continues through complete actors, never through world geometry.
		for _step in 32:
			q.exclude = excluded
			var hit := Zombie.cast_ray(self, q)
			if _step == 0 and i < 3 and not trace_mode.is_empty():
				var muzzle_world: Vector3 = (camera.global_transform * muzzle_transform()).origin
				NetSession.elemental_shot(muzzle_world, hit.get("position", origin + dir * 80.0), trace_mode, not hit.is_empty(), player.peer_id)
			if hit.is_empty(): break
			impact = hit.position
			if hit.collider.get_meta("shootable_pumpkin", false):
				if hit.collider.shoot(): hud.hitmarker(false)
				break
			if hit.collider is Breakable:
				(hit.collider as Breakable).shatter()
				scene.achievements.event("window")
				break
			if scene.hunting.hit(hit.collider, float(d.damage) * effective_damage_mul(), player.peer_id):
				_blood(hit.position, dir)
				hud.hitmarker(false)
				any_hit = true
				break
			var z := Zombie.from_hit(hit)
			if not z:
				preload("res://scripts/bullet_impacts.gd").hit(scene, hit)
				break
			excluded.append(z.get_rid())
			excluded.append(hit.collider.get_rid())
			for hitbox in z._hitboxes: excluded.append(hitbox.get_rid())
			if z.alive:
				var headshot: bool = hit.collider.get_meta("headshot", hit.position.y > z.global_position.y + z.height * 0.78)
				z.last_headshot = headshot
				z.last_hit_bone = str(hit.collider.get("bone_name")) if hit.collider.get("bone_name") != null else ""
				z.killer_weapon = current
				z.killer_peer = player.peer_id
				var dist := origin.distance_to(hit.position)
				var falloff := 1.0 - 0.45 * clampf((dist - float(d["range"])) / (2.0 * float(d["range"])), 0.0, 1.0)
				var titan_bonus := float(d.get("titan_multiplier", 1.0)) if Zombie.is_boss_kind(z.net_kind) else 1.0
				var dealt := float(d["damage"]) * effective_damage_mul() * titan_bonus * falloff * pow(float(d.get("pierce_retention", 1.0)), victims)
				if headshot and z.helmet_hp > 0.0:
					# the mutation's helmet rings: the helmet takes the round, the head is spared
					dealt = z.hit_helmet(dealt, dir)
					headshot = false
					z.last_headshot = false
				elif headshot:
					dealt *= 2.2
				z.damage(dealt, dir)
				rare.hit(z, special_round, player.peer_id, current)
				if specials: specials.on_hit(self, current, z, dir, player.peer_id)
				_blood(hit.position, dir)
				hud.hitmarker(headshot)
				any_hit = true
				if headshot and get_tree().current_scene.get("achievements"):
					get_tree().current_scene.achievements.event("headshots")
				victims += 1
				if victims >= int(d.get("pierce_targets", 1)): break
		if specials: specials.on_impact(self, current, impact, player.peer_id)
	if any_hit and stats:
		stats.hits += 1
	update_hud()

# H uses the equipped blade/axe, or a gun-butt strike while holding a firearm.
func melee(stab: bool = false) -> void:
	if not player.active or not player.alive or player.mounted_tower or player.controlling_drone or _melee_t > 0.0:
		return
	var armed := is_melee(current)
	var spec: Dictionary = cur()["def"]
	_melee_stab = stab and armed
	_melee_t = float(spec.stab_rate) if _melee_stab else float(spec.rate) if armed else 0.65
	_melee_duration = _melee_t
	_melee_anim = 1.0
	player.wobble = maxf(player.wobble, 0.3)
	# stab = right click, armed swing = the weapon's own clip (knife: knife_leftklick), gun butt = generic melee
	Sfx.play(self, "melee_stab" if _melee_stab else (str(spec.sfx) if armed else "melee"), -6.0 if _melee_stab else -8.0)
	if NetSession.is_client():
		NetSession.command("melee", [camera.global_rotation.y, camera.global_rotation.x, _melee_stab])
		return
	if armed and NetSession.is_host(): NetSession.weapon_fired(player.peer_id, current, _melee_stab)
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var hit_any := false
	# a short fan of rays so a zombie slightly off-centre is still hit
	for off: float in ([0.0, -0.025, 0.025] if _melee_stab else [0.0, -0.18, 0.18]):
		var dir: Vector3 = (forward + camera.global_transform.basis.x * off).normalized()
		var reach := float(spec.stab_range) if _melee_stab else float(spec.range) if armed else 2.1
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, Zombie.SHOT_MASK)
		q.collide_with_areas = true
		q.hit_from_inside = true
		q.exclude = [player.get_rid()]
		var hit := Zombie.cast_ray(self, q)
		if not hit.is_empty() and get_tree().current_scene.hunting.hit(hit.collider, (float(spec.stab_damage) if _melee_stab else float(spec.damage) if armed else 45.0) * effective_damage_mul(), player.peer_id):
			_blood(hit.position, forward)
			hit_any = true
			break
		var z := Zombie.from_hit(hit)
		if z and z.alive:
			z.last_headshot = false
			z.killer_weapon = current if armed else "melee"
			z.killer_peer = player.peer_id
			z.damage((float(spec.stab_damage) if _melee_stab else float(spec.damage) if armed else 45.0) * effective_damage_mul(), forward)
			z.shove(forward * (float(spec.shove) if armed else 4.5))
			_blood(hit.position, forward)
			hit_any = true
			break
	if hit_any:
		hud.hitmarker(false)
		Sfx.play(self, "hit", -4.0, 0.8)
		if "stats" in get_tree().current_scene and get_tree().current_scene.stats:
			get_tree().current_scene.stats.melee_hits += 1

func throw_grenade() -> void:
	if not player.active or not player.alive or player.mounted_tower or player.controlling_drone or grenades <= 0:
		return
	grenades -= 1
	update_hud()
	Sfx.play(self, "grenade_throw", -10.0)
	if NetSession.is_client():
		NetSession.command("grenade", [camera.global_rotation.y, camera.global_rotation.x])
		return
	if "stats" in get_tree().current_scene and get_tree().current_scene.stats:
		get_tree().current_scene.stats.grenades_thrown += 1
	var g := Grenade.new()
	g.setup(_grenade_scene, zombies_root, player)
	get_tree().current_scene.add_child(g)
	var dir := -camera.global_transform.basis.z
	g.global_position = camera.global_position + dir * 0.6 + Vector3(0.2, -0.1, 0)
	g.linear_velocity = dir * 15.0 + Vector3(0, 4.0, 0) + player.velocity
	g.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	if NetSession.enabled:
		NetSession.track_grenade(g)
	player.wobble = maxf(player.wobble, 0.2)

var _mist_pool: Array[GPUParticles3D] = []
var _decal_pool: Array[Decal] = []
var _decal_next := 0
var _splat_tex: ImageTexture

func _blood(pos: Vector3, dir: Vector3) -> void:
	if server_proxy:
		get_tree().current_scene.weapons._blood(pos, dir)
		return
	if NetSession.is_host(): NetSession.blood(pos, dir)
	var p := _blood_pool[_blood_next]
	var m := _mist_pool[_blood_next]
	_blood_next = (_blood_next + 1) % _blood_pool.size()
	p.global_position = pos
	m.global_position = pos
	(p.process_material as ParticleProcessMaterial).direction = (dir + Vector3(0, 0.25, 0)).normalized()
	(m.process_material as ParticleProcessMaterial).direction = dir
	p.restart()
	m.restart()
	p.emitting = true
	m.emitting = true
	# splat: on the ground below the wound, and on whatever the exit direction hits within 2.5 m
	var space: PhysicsDirectSpaceState3D = get_parent().get_world_3d().direct_space_state
	for ray in [[pos + Vector3(0, 0.3, 0), pos + Vector3(0, -3.0, 0), 0.7], [pos, pos + dir * 2.5, 0.5]]:
		var q := PhysicsRayQueryParameters3D.create(ray[0], ray[1], 1)
		var hit: Dictionary = space.intersect_ray(q)
		if hit:
			_splat(hit.position, hit.normal, ray[2] * randf_range(0.6, 1.4))

func _splat(pos: Vector3, normal: Vector3, size: float) -> void:
	var d := _decal_pool[_decal_next]
	_decal_next = (_decal_next + 1) % _decal_pool.size()
	d.size = Vector3(size, 0.6, size)
	d.global_position = pos + normal * 0.02
	var up := Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP
	d.look_at_from_position(d.global_position, pos - normal, up)
	d.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	d.modulate = Color(randf_range(0.3, 0.45), 0.02, 0.02, 1.0)
	d.visible = true

static func _make_splat_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var blobs: Array = []
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.42) * n
		blobs.append([Vector2(n / 2.0 + cos(a) * r * 0.5, n / 2.0 + sin(a) * r * 0.5), rng.randf_range(0.03, 0.22) * n])
	for y in n:
		for x in n:
			var v := 0.0
			for b in blobs:
				var dd: float = (b[0] as Vector2).distance_to(Vector2(x, y)) / (b[1] as float)
				v += maxf(0.0, 1.0 - dd * dd)
			var alpha := clampf((v - 0.35) * 2.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.4, 0.02, 0.02, alpha))
	return ImageTexture.create_from_image(img)

func _prepare_blood_pool() -> void:
	var dot := Foliage._soft_dot()
	# droplets: small billboards, dark red, fall with gravity and shrink
	var mat := ParticleProcessMaterial.new()
	mat.spread = 32.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 9.0
	mat.gravity = Vector3(0, -12.0, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.4
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.4))
	var sct := CurveTexture.new()
	sct.curve = sc
	mat.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.04, 0.03, 1.0))
	grad.set_color(1, Color(0.25, 0.01, 0.01, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	mat.color_ramp = gt
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var qm := StandardMaterial3D.new()
	qm.albedo_texture = dot
	qm.vertex_color_use_as_albedo = true
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = qm
	# mist: a few big soft puffs that hang for a moment
	var mm := ParticleProcessMaterial.new()
	mm.spread = 50.0
	mm.initial_velocity_min = 0.6
	mm.initial_velocity_max = 2.0
	mm.gravity = Vector3(0, -1.0, 0)
	mm.scale_min = 1.0
	mm.scale_max = 2.5
	mm.damping_min = 2.0
	mm.damping_max = 4.0
	var mg := Gradient.new()
	mg.set_color(0, Color(0.45, 0.03, 0.02, 0.55))
	mg.set_color(1, Color(0.3, 0.02, 0.02, 0.0))
	var mgt := GradientTexture1D.new()
	mgt.gradient = mg
	mm.color_ramp = mgt
	var mq := QuadMesh.new()
	mq.size = Vector2(0.25, 0.25)
	mq.material = qm
	for i in 16:
		var p := GPUParticles3D.new()
		p.process_material = mat.duplicate()
		p.draw_pass_1 = quad
		p.amount = 48
		p.lifetime = 0.9
		p.one_shot = true
		p.explosiveness = 0.95
		p.emitting = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-5, -6, -5), Vector3(10, 12, 10))
		get_parent().add_child(p)
		_blood_pool.append(p)
		var m := GPUParticles3D.new()
		m.process_material = mm.duplicate()
		m.draw_pass_1 = mq
		m.amount = 10
		m.lifetime = 0.5
		m.one_shot = true
		m.explosiveness = 1.0
		m.emitting = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
		get_parent().add_child(m)
		_mist_pool.append(m)
	_splat_tex = _make_splat_texture()
	for i in 48:
		var d := Decal.new()
		d.texture_albedo = _splat_tex
		d.albedo_mix = 1.0
		d.cull_mask = 1
		d.visible = false
		get_parent().add_child(d)
		_decal_pool.append(d)


func aimed_fov() -> float:
	if DEFS[current].has("scope_zoom"):
		return rad_to_deg(2.0 * atan(tan(deg_to_rad(75.0) * 0.5) / float(DEFS[current].scope_zoom)))
	return 52.0

func _reset_scope(reset_fov := true) -> void:
	ads = 0.0
	if reset_fov: camera.fov = 75.0
	if viewmodel:
		viewmodel.set_scoped(false)
		for part in hud.crosshair_parts: part.visible = player.active and player.alive

func _process(delta: float) -> void:
	if not player or not player.alive or not player.active:
		Sfx.stop_fire_loop(self)
	if server_proxy:
		if player.active and player.alive:
			_tick_ammo(delta)
		return
	if not player or not player.active:
		if player: _reset_scope()
		if player and NetSession.enabled and player.alive:
			_tick_ammo(delta)
		return
	effects.advance(delta, player.velocity)
	_step_model_recoil(delta)
	_tick_ammo(delta)
	var s := cur()
	var d: Dictionary = s["def"]
	hud.set_reload(s["reloading"], float(d["reload"]) * effective_reload_mul())
	# Heat, spin-up or energy cells get their own gauge: hud.ammo_label is rewritten twice by
	# update_hud, so a second line of text there would be lost.
	var gauge: Dictionary = specials.hud_state(self, current) if specials else {}
	hud.set_charge(str(gauge.get("text", "")), float(gauge.get("value", 0.0)), gauge.get("colour", Color(1.0, 0.7, 0.28)))
	_handle_weapon_input(delta)

func _tick_ammo(delta: float) -> void:
	_aim_kick *= exp(-delta * Aim.KICK_RECOVERY)
	if _burst_t <= 0.0: _bloom = maxf(0.0, _bloom - delta * Aim.BLOOM_RECOVERY)
	_burst_t -= delta
	if _burst_t <= 0.0: _shots_in_burst = 0
	_melee_t = maxf(0.0, _melee_t - delta)
	for weapon_state: Dictionary in state.values():
		weapon_state["cooldown"] = maxf(-delta, weapon_state["cooldown"] - delta)
	if specials: specials.tick(self, delta)   # heat and spin also fall while the weapon is stowed
	var s := cur()
	var d: Dictionary = s["def"]
	if s["reloading"] > 0.0:
		s["reloading"] -= delta
		if s["reloading"] <= 0.0:
			var need: int = d["mag"] - s["ammo"]
			var take: int = mini(need, s["reserve"])
			s["ammo"] += take
			s["reserve"] -= take
			s["reloading"] = 0.0
			update_hud()
func _handle_weapon_input(delta: float) -> void:
	if not Input.is_action_pressed("fire"): Sfx.stop_fire_loop(self, false)
	var scene := get_tree().current_scene
	if player.controlling_drone:
		_reset_scope(false)
		for part in hud.crosshair_parts: part.hide()
		return
	if player.mounted_tower:
		_reset_scope(false) # DefenceSystem owns the mounted camera's zoom.
		return
	if "fireworks" in scene and scene.fireworks and (scene.fireworks.armed or scene.fireworks.input_grace > 0):
		_reset_scope()
		return
	if "defences" in scene and scene.defences and (scene.defences.placing or scene.defences.input_grace > 0):
		_reset_scope()
		return
	var s := cur()
	var d: Dictionary = s["def"]
	if d["auto"]:
		if Input.is_action_pressed("fire"):
			try_fire()
	elif Input.is_action_just_pressed("fire"):
		try_fire()
	if is_melee(current) and Input.is_action_just_pressed("aim"):
		melee(true)
	if Input.is_action_just_pressed("reload"):
		reload()
	if Input.is_action_just_pressed("grenade"):
		throw_grenade()
	if Input.is_action_just_pressed("melee"):
		melee()
	_melee_anim = maxf(0.0, _melee_anim - delta / _melee_duration)
	var step := 0
	if Input.is_action_just_pressed("weapon_next"):
		step = 1
	elif InputMap.has_action("weapon_prev") and Input.is_action_just_pressed("weapon_prev"):
		step = -1
	if step != 0:
		var idx := ORDER.find(current)
		for k in ORDER.size():
			idx = posmod(idx + step, ORDER.size())
			if unlocked[ORDER[idx]]:
				set_weapon(ORDER[idx])
				break
	s = cur()
	d = s["def"]
	# aim down sights
	var want_ads := 1.0 if not is_melee(current) and Input.is_action_pressed("aim") and s["reloading"] <= 0.0 else 0.0
	ads = lerpf(ads, want_ads, minf(1.0, delta * 10.0))
	camera.fov = lerpf(75.0, aimed_fov(), ads)
	var scoped: bool = d.has("scope_zoom") and ads >= 0.85 and want_ads > 0.0
	viewmodel.set_scoped(scoped, float(d.get("scope_zoom", 1.0)), str(d.get("scope_style", "mil")))
	if scoped and specials and viewmodel.scope.has_method("set_heat"):
		viewmodel.scope.set_heat(float(s.get("heat", 0.0)))
	for part in hud.crosshair_parts: part.visible = not scoped and not is_melee(current) and s.reloading <= 0
	update_reticle()
	# camera recoil recovery: part of the kick stays (the camera really moved), the rest settles back
	var rec: float = float(d["recover"])
	var applied_pitch := kick_pitch * (1.0 - exp(-delta * rec))
	var applied_yaw := kick_yaw * (1.0 - exp(-delta * rec))
	kick_pitch -= applied_pitch
	kick_yaw -= applied_yaw
	player.pitch = clampf(player.pitch + deg_to_rad(applied_pitch) * 0.45, -1.45, 1.45)
	player.rotate_y(deg_to_rad(applied_yaw) * 0.35)
	player.recoil_offset = Vector2(deg_to_rad(kick_pitch) * 0.65, deg_to_rad(kick_yaw) * 0.65)
	# view model
	recoil = maxf(0.0, recoil - delta * 7.0)
	sway_t += delta
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.5
	var n: Node3D = s["node"]
	var base_pos: Vector3 = (d["pos"] as Vector3).lerp(s["aim_position"], ads)
	var sway_amp := 1.0 - ads * 0.8
	n.position = base_pos + Vector3(sin(sway_t * 5.0) * (0.008 if moving else 0.002) * sway_amp, sin(sway_t * 10.0) * (0.005 if moving else 0.0015) * sway_amp + (-0.12 if s["reloading"] > 0.0 else 0.0), _model_kick.z)
	# melee: the gun lunges forward and rolls, then springs back
	var lunge := sin(clampf(_melee_anim, 0.0, 1.0) * PI)
	n.position += Vector3(-0.06, -0.02, -0.16) * lunge
	n.rotation.x = _model_kick.x + (-0.4 if s["reloading"] > 0.0 else 0.0) - 0.35 * lunge
	n.rotation.z = _model_kick.y + 0.5 * lunge
	if is_melee(current):
		n.position += Vector3(-0.10, 0.02, -0.04) * lunge
		n.rotation = Vector3(-0.55 if current == "hatchet" else -0.25, -0.25, 0.4) * lunge
	if current == "knife":
		n.position = base_pos + Vector3(0, sin(sway_t*5)*0.002, 0)
		if _melee_stab:
			n.position += Vector3(-0.06,0.045,-0.3)*lunge
			n.rotation = Vector3(-0.5,-0.4,-0.12).lerp(Vector3(-1.5,0,-0.05),lunge)
		else:
			n.position += Vector3(-0.19,0.015,-0.08)*lunge
			n.rotation = Vector3(-0.5,-0.4,-0.12)+Vector3(-0.18,0.4,1.0)*lunge
	if current == "hatchet":
		n.position = base_pos + Vector3(sin(sway_t*5)*0.002,0,0)
		n.position += Vector3(-0.12,0.04,-0.25)*lunge if _melee_stab else Vector3(-0.09,0,-0.10)*lunge
		n.rotation = Vector3(-0.22,-0.38,-0.16) + (Vector3(-1.1,0.2,0.65) if _melee_stab else Vector3(-0.45,0.15,0.45))*lunge
	(s["hands"] as ViewmodelHands).animate_reload(1.0 - float(s["reloading"]) / (float(d["reload"]) * effective_reload_mul()), s["reloading"] > 0.0)
	(s["hands"] as ViewmodelHands).animate_cloth(delta, Vector2(player.velocity.x, player.velocity.z).length(), ads)
	if is_melee(current): (cur()["hands"] as ViewmodelHands).anchor_melee_elbows(viewmodel.camera)
	effects.sync_muzzle(muzzle_transform())
	if current == "minigun":
		var attachments: WeaponAttachments = cur().get("mods")
		if attachments: effects.sync_second_muzzle((cur().node as Node3D).transform * Transform3D(Basis.IDENTITY, attachments.second_bore_tip()))

func visual_muzzle_world() -> Vector3:
	var tip := muzzle_transform().origin
	if server_proxy or not viewmodel:
		return camera.to_global(tip)
	# Viewmodel FOV stays at 75 degrees while the world camera zooms. Match the visible pixel,
	# not the unprojected viewmodel coordinates, including current sway and model recoil.
	var pixels := viewmodel.camera.unproject_position(viewmodel.camera.to_global(tip))
	var screen := pixels / Vector2(viewmodel.viewport.size) * camera.get_viewport().get_visible_rect().size
	if not viewmodel.image.visible: screen = camera.get_viewport().get_visible_rect().size * 0.5
	return camera.project_position(screen, maxf(camera.near + 0.01, -tip.z))

func muzzle_transform() -> Transform3D:
	var s := cur()
	# A server proxy simulates a teammate's shots and never builds a view model, so there is no
	# gun node to measure. Special rounds ask for the muzzle to start their tracer: hand them the
	# spot in front of the camera where the barrel would sit instead of a missing mesh.
	if server_proxy or not s.has("bounds"):
		return Transform3D(Basis.IDENTITY, Vector3(0.1, -0.11, -0.42))
	var bounds: AABB = s["bounds"]
	var tip := Vector3(bounds.get_center().x, bounds.end.y - 0.015, bounds.position.z - 0.006)
	if current == "ak47":
		# Bore centre measured on ak47.glb, below the raised front sight. Only reached when the
		# weapon has no measured mount data; weapon_mount_data.gd reproduces this to about a
		# millimetre and covers the other eight guns as well.
		tip.x = bounds.position.x + bounds.size.x * 0.31
		tip.y = bounds.position.y + bounds.size.y * 0.805
	# The measured bore, or the front of a mounted suppressor or barrel: flash, smoke and tracers
	# all start where the bullet actually leaves the weapon.
	var mods: WeaponAttachments = s.get("mods")
	if mods: tip = mods.muzzle_tip(tip)
	return (s["node"] as Node3D).transform * Transform3D(Basis.IDENTITY, tip)

func _step_model_recoil(delta: float) -> void:
	# Exact damped-spring integration remains stable during slow frames and pauses.
	var omega := 22.0 + float(cur()["def"]["recover"])
	var damping := 0.62
	var damped := omega * sqrt(1.0 - damping * damping)
	var decay := exp(-damping * omega * delta)
	var c := cos(damped * delta)
	var s := sin(damped * delta)
	var position := _model_kick
	var velocity := _model_velocity
	_model_kick = decay * (position * c + (velocity + damping * omega * position) * s / damped)
	_model_velocity = decay * (velocity * c - (damping * omega * velocity + omega * omega * position) * s / damped)
	var model_cap: Vector3 = cur()["def"].get("kick_model_cap", Vector3(0.32, 0.07, 0.12))
	_model_kick = _model_kick.clamp(Vector3(-0.08, -0.07, -0.02), model_cap)

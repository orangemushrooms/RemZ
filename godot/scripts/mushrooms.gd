extends RefCounted

# Game items: a single catalogue drives effects, world variants and sale prices.
const DEFS := {
	"goldroehrling": {"name": "Golden Bolete", "text": "Extremely rare find to sell · 1000 Rem Dollars at the Vendor. Not for eating.", "heal": 0.0, "sell": 1000, "weight": 0, "collectible": true, "color": Color("efbb32")},
	"steinpilz": {"name": "Porcini", "text": "+25 health", "heal": 25.0, "sell": 8, "weight": 30, "color": Color("8c6138")},
	"fliegenpilz": {"name": "Fly Agaric", "text": "-15 health; 20 s double weapon and melee damage", "heal": -15.0, "duration": 20.0, "damage": 2.0, "effect": "Damage ×2", "sell": 14, "weight": 12, "color": Color("cf302b")},
	"pfifferling": {"name": "Chanterelle", "text": "+10 health; 30 s +20% running speed", "heal": 10.0, "duration": 30.0, "speed": 1.2, "effect": "Speed +20%", "sell": 10, "weight": 18, "color": Color("edb83d"), "cap": 0.20, "flat": 0.32},
	"morchel": {"name": "Morel", "text": "+15 health; 30 s 25% shorter reload time", "heal": 15.0, "duration": 30.0, "reload": 0.75, "effect": "Reload −25%", "sell": 14, "weight": 10, "color": Color("9f8241"), "cap": 0.11, "flat": 1.7},
	"maronenroehrling": {"name": "Bay Bolete", "text": "+40 health", "heal": 40.0, "sell": 12, "weight": 16, "color": Color("754025"), "cap": 0.21, "flat": 0.75},
	"parasol": {"name": "Parasol Mushroom", "text": "+15 health; 30 s 25% less damage taken", "heal": 15.0, "duration": 30.0, "guard": 0.75, "effect": "Damage taken −25%", "sell": 12, "weight": 12, "color": Color("c0ac83"), "cap": 0.28, "flat": 0.28},
	"reizker": {"name": "Saffron Milk Cap", "text": "+10 health; 40 s double health regeneration", "heal": 10.0, "duration": 40.0, "regen": 2.0, "effect": "Regeneration ×2", "sell": 10, "weight": 14, "color": Color("c97132"), "cap": 0.22, "flat": 0.38},
	"tintenpilz": {"name": "Shaggy Ink Cap", "text": "35 s 35% less weapon spread", "heal": 0.0, "duration": 35.0, "spread": 0.65, "effect": "Spread −35%", "sell": 16, "weight": 9, "color": Color("d6d0b9"), "cap": 0.12, "flat": 1.5},
	"violetter_roetelritterling": {"name": "Wood Blewit", "text": "+5 health; 40 s +35% weapon and melee damage", "heal": 5.0, "duration": 40.0, "damage": 1.35, "effect": "Damage +35%", "sell": 18, "weight": 7, "color": Color("9267a5"), "cap": 0.22, "flat": 0.55},
	"krause_glucke": {"name": "Cauliflower Fungus", "text": "+60 health", "heal": 60.0, "sell": 22, "weight": 5, "color": Color("d2bf85"), "cap": 0.13, "flat": 0.8},
}

const GOLD_ROUND_CHANCE := 0.05
static var _gold_shimmer: ShaderMaterial

static func gold_shimmer() -> ShaderMaterial:
	if _gold_shimmer == null:
		_gold_shimmer = ShaderMaterial.new()
		_gold_shimmer.shader = preload("res://shaders/gold_mushroom_shimmer.gdshader")
	return _gold_shimmer

# Ordinary locations remain deterministic for co-op. Only the host rolls this
# separate, optional collectible once per round, then replicates its position.
static func rare_slot(random: RandomNumberGenerator, candidates: int) -> int:
	if candidates <= 0 or random.randf() >= GOLD_ROUND_CHANCE: return -1
	return random.randi_range(0, candidates - 1)

static func empty_stock() -> Dictionary:
	var stock := {}
	for kind in DEFS: stock[kind] = 0
	return stock

static func choose(random: RandomNumberGenerator) -> String:
	var total := 0
	for spec in DEFS.values(): total += int(spec.weight)
	var roll := random.randi_range(0, total - 1)
	for kind in DEFS:
		roll -= int(DEFS[kind].weight)
		if roll < 0: return kind
	return "steinpilz"

static func multiplier(effects: Dictionary, attribute: String) -> float:
	var result := 1.0
	for kind in effects:
		if float(effects[kind]) <= 0.0 or not DEFS.has(kind): continue
		var value: float = DEFS[kind].get(attribute, 1.0)
		result = minf(result, value) if attribute in ["reload", "spread", "guard"] else maxf(result, value)
	return result

static func tick(effects: Dictionary, delta: float) -> void:
	for kind in effects.keys():
		effects[kind] = maxf(0.0, float(effects[kind]) - delta)
		if effects[kind] <= 0.0: effects.erase(kind)

static func summary(effects: Dictionary) -> String:
	var lines := PackedStringArray()
	for kind in effects:
		if DEFS.has(kind) and float(effects[kind]) > 0.0:
			lines.append(Lang.t("%s · %s · %d s", [DEFS[kind].name, DEFS[kind].get("effect", ""), ceili(effects[kind])]))
	return "\n".join(lines)

# Empty result means success; callers own HUD, sound and statistics.
static func consume(player, stock: Dictionary, kind: String) -> String:
	if not DEFS.has(kind): return "Unknown kind of mushroom."
	if not player.alive: return "You cannot eat right now."
	if int(stock.get(kind, 0)) <= 0: return Lang.t("No %s in your inventory.", [DEFS[kind].name])
	var spec: Dictionary = DEFS[kind]
	if spec.get("collectible", false): return "Keep the Golden Bolete: sell it to the Vendor for 1000 Rem Dollars."
	if float(spec.heal) > 0.0 and not spec.has("duration") and player.hp >= player.max_hp:
		return "Health full – the mushroom stays in your inventory."
	stock[kind] -= 1
	player.hp = clampf(player.hp + float(spec.heal), 1.0, player.max_hp)
	if spec.has("duration"):
		# Refresh this species; stacking never multiplies a stat indefinitely.
		player.mushroom_effects[kind] = float(spec.duration)
	player.hud.set_health(player.hp)
	return ""

static func model(kind: String) -> Node3D:
	if kind == "goldroehrling":
		# Reuse the detailed Meshy bolete geometry and PBR maps with private materials.
		var gold := WorldModels.create("mushroom_maronenroehrling", 0.4)
		if gold:
			gold.set_meta("model_id", "mushroom_goldroehrling")
			for mesh: MeshInstance3D in gold.find_children("*", "MeshInstance3D", true, false):
				for surface in mesh.mesh.get_surface_count():
					var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
					if not original: continue
					var material := original.duplicate() as BaseMaterial3D
					material.albedo_color = Color(1.0, 0.82, 0.24)
					material.metallic = 0.3
					material.roughness = 0.38
					material.next_pass = gold_shimmer()
					mesh.set_surface_override_material(surface, material)
			return gold
	var id := "mushroom_cluster" if kind == "steinpilz" else "mushroom_fly" if kind == "fliegenpilz" else "mushroom_" + kind
	var imported := WorldModels.create(id, 0.4)
	if imported: return imported
	var root := Node3D.new()
	var spec: Dictionary = DEFS[kind]
	var stem_material := StandardMaterial3D.new()
	stem_material.albedo_color = Color("cbbda0")
	stem_material.roughness = 0.95
	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = spec.color
	cap_material.roughness = 0.82
	if kind == "goldroehrling":
		stem_material.next_pass = gold_shimmer()
		cap_material.next_pass = gold_shimmer()
	var count := 7 if kind == "krause_glucke" else 3
	for i in count:
		var cluster := Node3D.new()
		root.add_child(cluster)
		cluster.position = Vector3(cos(i * 2.4) * 0.11, 0, sin(i * 2.4) * 0.11) if i > 0 else Vector3.ZERO
		cluster.scale = Vector3.ONE * (1.0 - i * 0.075)
		var stem := CylinderMesh.new()
		stem.top_radius = 0.025
		stem.bottom_radius = 0.045
		stem.height = 0.25 if kind != "krause_glucke" else 0.1
		stem.radial_segments = 10
		_piece(cluster, stem, Vector3.UP * stem.height * 0.5, stem_material)
		var cap := SphereMesh.new()
		cap.radius = float(spec.get("cap", 0.2))
		cap.height = cap.radius * 2.0
		cap.is_hemisphere = true
		cap.radial_segments = 16
		cap.rings = 8
		var top := _piece(cluster, cap, Vector3.UP * stem.height, cap_material)
		top.scale.y = float(spec.get("flat", 0.6))
		if kind in ["morchel", "parasol", "tintenpilz"]:
			for spot in 8:
				var dot := SphereMesh.new()
				dot.radius = 0.016
				dot.height = 0.02
				dot.radial_segments = 6
				dot.rings = 4
				var angle := spot * TAU / 8.0
				_piece(top, dot, Vector3(cos(angle) * cap.radius * 0.7, cap.radius * 0.7, sin(angle) * cap.radius * 0.7), stem_material)
	return root

static func _piece(parent: Node3D, mesh: Mesh, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

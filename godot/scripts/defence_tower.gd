class_name DefenceTower
extends Node3D

const COST := 120
const REPAIR_COST := 35
const LIMIT := 40   # 26 Sep 2026: doubled from 20
const HEALTH := [240.0, 400.0, 600.0]
const RANGE := [26.0, 32.0, 38.0]
const UPGRADES := [100, 175]
# Completed waves relative to each type: basic, reinforced, elite.
const UPGRADE_WAVE_OFFSETS := [0, 2, 5]
const HALF_ARC := 80.0 * PI / 180.0
const TYPES := ["standard", "searchlight", "siren", "supply", "flame", "mortar", "frost", "mg42", "sniper", "rocket", "tesla", "harpoon", "graviton"]
# Kinds that deal no direct damage (the generic "deals damage" expectations skip them), kinds that
# never go onto the roof (the siren would lure the horde onto the hut wall, the post heals a ground
# radius), the heavy prey the harpoon is built for, and what the eight new ones bring per tier.
const SUPPORT := ["searchlight", "siren", "supply"]
const ROOF_BANNED := ["siren", "supply"]
const HEAVY_KINDS := ["brute", "bride", "zombie_stag"]
const SUPPLY_LIMIT := 1
const ROCKET_MIN_RANGE := 8.0
const ROCKETS_PER_SALVO := 4
const ROCKET_BLAST := 5.0
const LURE_SECONDS := 12.0
const TETHER_SECONDS := 6.0
const PULL_RADIUS := 10.0
const MARK_BONUS := 1.15
const SPECS := {
	"standard": {"unlock_waves": 0, "name": "Sentinel", "cost": 120, "range": 26.0, "damage": 18.0, "rate": 0.22, "heat": 0.13, "health": 1.0, "info": "Precise bursts"},
	"flame": {"unlock_waves": 2, "name": "Flamethrower", "cost": 260, "range": 14.0, "damage": 14.0, "rate": 0.12, "heat": 0.035, "health": 1.2, "info": "Cone of fire hits several enemies"},
	"mortar": {"unlock_waves": 4, "name": "Mortar", "cost": 380, "range": 120.0, "damage": 210.0, "rate": 2.8, "heat": 0.2, "health": 1.4, "info": "Arcing shot · 12 m blast radius"},
	"mg42": {"unlock_waves": 6, "name": "Heavy MG", "cost": 450, "range": 44.0, "damage": 27.0, "rate": 0.085, "heat": 0.055, "health": 1.6, "info": "High rate of fire · watch the heat"},
	"tesla": {"unlock_waves": 8, "name": "Tesla Coil", "cost": 600, "range": 22.0, "damage": 75.0, "rate": 0.9, "heat": 0.16, "health": 1.8, "info": "Chain lightning jumps to nearby enemies"},
	# The eight of 2 Oct 2026. "rate" is the cooldown of a pulse for the support kinds (the siren's 45 s,
	# the supply post's 3 s tick); "damage" the heal per tick for the post, the chill per pulse for the
	# frost cannon (plus 9 points of cold damage), one rocket for the pod, one harpoon for the launcher.
	"searchlight": {"unlock_waves": 1, "name": "Searchlight", "cost": 150, "range": 40.0, "damage": 0.0, "rate": 2.5, "heat": 0.0, "health": 0.9, "info": "Lights up stalkers · lit targets take 15% more from every tower"},
	"siren": {"unlock_waves": 2, "name": "Decoy Siren", "cost": 220, "range": 40.0, "damage": 0.0, "rate": 45.0, "heat": 0.0, "health": 1.1, "info": "Lures every common zombie nearby for 12 s · 45 s recharge"},
	"supply": {"unlock_waves": 2, "name": "Supply Post", "cost": 300, "range": 12.0, "damage": 25.0, "rate": 3.0, "heat": 0.0, "health": 1.2, "info": "Repairs gates, sandbags and towers nearby · hands out ammo · one per team"},
	"frost": {"unlock_waves": 5, "name": "Frost Cannon", "cost": 420, "range": 18.0, "damage": 9.0, "rate": 0.25, "heat": 0.05, "health": 1.3, "info": "Cone of cold · chills, then freezes solid · frozen targets take 40% more"},
	"sniper": {"unlock_waves": 6, "name": "Sniper Nest", "cost": 480, "range": 90.0, "damage": 150.0, "rate": 2.0, "heat": 0.25, "health": 1.2, "info": "One shot every two seconds through up to 3 bodies · head hits"},
	"rocket": {"unlock_waves": 7, "name": "Rocket Pod", "cost": 520, "range": 45.0, "damage": 120.0, "rate": 6.0, "heat": 0.0, "health": 1.4, "info": "Salvo of four rockets · 5 m blast · 6 s reload · 8 m minimum range"},
	"harpoon": {"unlock_waves": 9, "name": "Harpoon Launcher", "cost": 700, "range": 40.0, "damage": 320.0, "rate": 4.0, "heat": 0.2, "health": 1.5, "info": "Harpoons brutes and titans · tethered giants move at half speed for 6 s"},
	"graviton": {"unlock_waves": 11, "name": "Graviton Trap", "cost": 900, "range": 30.0, "damage": 40.0, "rate": 14.0, "heat": 0.0, "health": 1.6, "info": "Implosion drags every zombie within 10 m into a heap · 14 s recharge"},
}
var kind := "standard"
var rooftop := false
var operator_peer := 0
var trigger := false
var aiming := false
var control_timeout := 0.0
var exit_position := Vector3.ZERO
var tower_id := 0
var owner_peer := 1
var level := 1
var hp := 240.0
var replica := false
var game: Node
var body: StaticBody3D
var gun: Node3D
var muzzle: Node3D
var label: Label3D
var tracer: MeshInstance3D
var flash: OmniLight3D
var target: Zombie
var cooldown := 0.0
var heat := 0.0
var overheated := false
var shots := 0
var last_impact := Vector3.ZERO
var chain_points := PackedVector3Array()
var _scan := 0.0
var _flash_t := 0.0
var aim_yaw := 0.0
var aim_pitch := 0.0
var reinforcement: Node3D
var armour: Node3D
var flame: CPUParticles3D
var fx: Node3D
var shot_audio: Node3D
var _weapon_model: Node3D
var _model_rest := Vector3.ZERO
var _recoil := 0.0
var _recoil_velocity := 0.0
var _trace_origin := Vector3.ZERO
var _trace_direction := Vector3.FORWARD
var _trace_distance := 0.0
var _trace_travel := 0.0
var _lightning: MeshInstance3D
# 2 Oct 2026: the searchlight's beam, the siren's beacon, the harpoon's rope, the post's clock.
var active_t := 0.0                 # siren wailing / searchlight pulse / supply pulse, seconds left
var tether: Zombie                  # the giant on the harpoon's rope (host)
var tether_t := 0.0
var tether_end := Vector3.INF       # where the rope ends, replicated so clients draw it too
var _beam: SpotLight3D
var _beam_cone: MeshInstance3D
var _beacon: SpotLight3D
var _beacon_head: Node3D
var _rope: MeshInstance3D
var _lit_target: Zombie
var _ammo_given: Dictionary = {}    # peer -> game seconds of the last magazine the post handed out
var _supply_clock := 0.0
static var _boxes: Dictionary = {}
static var _cylinders: Dictionary = {}
static var _model_scenes: Dictionary = {}

func spec() -> Dictionary:
	return SPECS.get(kind, SPECS.standard)

func attack_range() -> float:
	return float(spec().range) + (level-1)*6.0

func manual_spread() -> float:
	# Small unaimed cone; holding the sights steadies every manually operated turret.
	var degrees: float = {"standard": 0.65, "mg42": 0.9, "mortar": 0.8, "flame": 0.7, "tesla": 0.35, "sniper": 0.3, "rocket": 1.1, "frost": 0.7, "harpoon": 0.4, "graviton": 0.9}.get(kind, 0.65)
	return tan(deg_to_rad(degrees)) * (0.25 if aiming else 1.0)

func upgrade_cost() -> int:
	return roundi(UPGRADES[mini(level-1,1)] * float(spec().cost)/COST)

func refund() -> int:
	return int(spec().cost)/3

# The field of view the sights give an operator: the sniper nest looks through its scope.
func aim_fov() -> float:
	return 30.0 if kind == "sniper" else 55.0

func is_support() -> bool:
	return kind in SUPPORT

func seat_position() -> Vector3:
	# Tall mortar tubes and the coil need a side operating position to keep the reticle clear.
	var seat := Vector3(0.7 if kind in ["tesla","mortar","harpoon","graviton"] else 0.35 if kind in ["flame","rocket","frost","searchlight","sniper"] else 0.0,2.55,0.85)
	return to_global(seat.rotated(Vector3.UP,gun.rotation.y if gun else 0.0))

static func material(color: Color, metal := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.78 if metal == 0.0 else 0.42
	return mat

static func piece(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = mat
	parent.add_child(instance)
	return instance

static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	if not _boxes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_boxes[size] = mesh
	return piece(parent, _boxes[size], pos, mat)

static func cylinder(parent: Node3D, radius: float, length: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var key := Vector2(radius, length)
	if not _cylinders.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		mesh.radial_segments = 16
		_cylinders[key] = mesh
	return piece(parent, _cylinders[key], pos, mat)

func _ready() -> void:
	add_to_group("defence_towers")
	add_to_group("render_dynamic")
	_scan = float(tower_id % 8) * 0.03
	if kind == "tesla":
		_lightning = preload("res://scripts/tower_lightning.gd").new()
		add_child(_lightning)
	var steel := material(Color(0.12, 0.15, 0.14), 0.8)
	var wood := material(Color(0.75, 0.69, 0.57))
	wood.albedo_texture = load("res://assets/textures/planks_albedo.jpg")
	wood.normal_enabled = true
	wood.normal_texture = load("res://assets/textures/planks_normal.jpg")
	wood.roughness_texture = load("res://assets/textures/planks_rough.jpg")
	var concrete := material(Color(0.75, 0.73, 0.66))
	concrete.albedo_texture = load("res://assets/textures/ph_concrete_albedo.jpg")
	concrete.normal_enabled = true
	concrete.normal_texture = load("res://assets/textures/ph_concrete_normal.jpg")
	var brass := material(Color(0.54, 0.39, 0.13), 0.7)
	var sand := material(Color(0.39, 0.37, 0.23))
	if not rooftop:
		for x in [-0.8, 0.8]:
			for z in [-0.8, 0.8]:
				box(self, Vector3(0.55, 0.3, 0.55), Vector3(x, 0.07, z), concrete)
				box(self, Vector3(0.19, 2.5, 0.19), Vector3(x, 1.32, z), steel)
		for z in [-0.8, 0.8]:
			for sign_x in [-1, 1]:
				Barricade._add_bar(self, Vector3(-0.8 * sign_x, 0.25, z), Vector3(0.8 * sign_x, 2.4, z), 0.09, steel)
		for i in 9:
			box(self, Vector3(2.15, 0.14, 0.235), Vector3(0, 2.45, (i - 4) * 0.24), wood)
		for x in [-0.92, 0.92]:
			for z in [-0.68, 0.0, 0.68]:
				var bag := WorldModels.attach(self, "sandbag", Vector3(x, 2.52, z), 0.65, 0)
				if bag:
					bag.rotation.y = PI * 0.5
				else:
					var preview := cylinder(self, 0.22, 0.65, Vector3(x, 2.7, z), sand)
					preview.rotation.x = PI * 0.5
		for i in 7:
			box(self, Vector3(0.55, 0.075, 0.1), Vector3(0, 0.26 + i * 0.33, 1.08), steel)
		for x in [-0.31, 0.31]:
			box(self, Vector3(0.065, 2.5, 0.07), Vector3(x, 1.28, 1.08), steel)
		cylinder(self, 0.12, 0.7, Vector3(0, 2.85, 0), steel)
	else:
		box(self, Vector3(1.25, 0.7, 1.25), Vector3(0, -0.25, 0), steel)
		cylinder(self, 0.18, 0.5, Vector3(0, 0.3, 0), steel)
	gun = Node3D.new()
	gun.position.y = 0.65 if rooftop else 3.15
	add_child(gun)
	box(gun, Vector3(0.48, 0.38, 0.85), Vector3(0, 0, -0.08), steel)
	box(gun, Vector3(0.32, 0.4, 0.48), Vector3(0.4, -0.03, 0), sand)
	for x in [-0.13, 0.13]:
		var barrel := cylinder(gun, 0.058, 1.4, Vector3(x, 0, -0.99), steel)
		barrel.rotation.x = PI * 0.5
		for i in 7:
			var fin := cylinder(gun, 0.087, 0.035, Vector3(x, 0, -0.65 - i * 0.11), steel)
			fin.rotation.x = PI * 0.5
	for i in 7:
		cylinder(gun, 0.025, 0.15, Vector3(0.24 + i * 0.03, -0.18, -0.1), brass)
	box(gun, Vector3(0.2, 0.18, 0.22), Vector3(0, 0.3, -0.05), steel)
	var lens := material(Color(0.7, 0.12, 0.035))
	lens.emission_enabled = true
	lens.emission = Color(1, 0.15, 0.02)
	box(gun, Vector3(0.09, 0.075, 0.01), Vector3(0, 0.3, -0.165), lens)
	reinforcement = Node3D.new()
	add_child(reinforcement)
	for x in [-0.92, 0.92]:
		box(reinforcement, Vector3(0.08, 0.8, 1.8), Vector3(x, 1.95, 0), steel)
	armour = Node3D.new()
	gun.add_child(armour)
	for x in [-0.38, 0.38]:
		var plate := box(armour, Vector3(0.35, 0.6, 0.09), Vector3(x, 0.06, -0.49), steel)
		plate.rotation.y = -signf(x) * 0.3
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -1.7)
	gun.add_child(muzzle)
	_build_variant(steel, brass)
	body = StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var collider := BoxShape3D.new()
	collider.size = Vector3(1.25, 0.65, 1.25) if rooftop else Vector3(2.15, 2.52, 2.15)
	shape.shape = collider
	shape.position.y = 0.325 if rooftop else 1.26
	body.add_child(shape)
	label = Label3D.new()
	label.position = Vector3(0, 1.6 if rooftop else 4.0, 0)
	label.font_size = 36
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 18.0
	add_child(label)
	var glow := material(Color(1, 0.75, 0.22))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer = box(self, Vector3(0.018, 0.018, 1), Vector3.ZERO, glow)
	tracer.top_level = true
	tracer.visible = false
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash = OmniLight3D.new()
	flash.light_color = Color(1, 0.58, 0.12)
	flash.omni_range = 5
	flash.visible = false
	muzzle.add_child(flash)
	fx = preload("res://scripts/tower_effects.gd").new()
	fx.kind = kind
	muzzle.add_child(fx)
	flame = fx.jet
	_build_special(steel)
	_weapon_model = gun.get_node_or_null("WeaponModel")
	if _weapon_model:
		_model_rest = _weapon_model.position
	refresh()

# The parts the eight towers of 2 Oct 2026 carry beyond a weapon mesh: the searchlight's lamp and its
# visible beam, the siren's turning beacon, the harpoon's rope. They hang on the muzzle or the gun, so
# they follow the aim like the barrel does.
func _build_special(steel: Material) -> void:
	match kind:
		"searchlight":
			_beam = SpotLight3D.new()
			_beam.name = "Beam"
			_beam.light_color = Color(1.0, 0.93, 0.78)
			_beam.light_energy = 0.0
			_beam.spot_range = float(spec().range) + 18.0
			_beam.spot_angle = 11.0
			_beam.spot_angle_attenuation = 0.5
			_beam.shadow_enabled = true
			_beam.add_to_group("searchlights")
			muzzle.add_child(_beam)
			# the visible beam cone is 40 m long: it is made the first time the lamp lights, so the icon
			# renderer and the bounds of a dark lamp never see it
		"siren":
			_beacon_head = Node3D.new()
			# on top of the Meshy motor head (the model's crown sits at y 1.18 above the pivot), else on the box
			_beacon_head.position = Vector3(0.24, 0.93, -0.18) if gun.has_node("WeaponModel") else Vector3(0, 0.42, 0.2)
			gun.add_child(_beacon_head)
			var dome := SphereMesh.new()
			dome.radius = 0.13
			dome.height = 0.26
			var red := material(Color(0.85, 0.07, 0.05))
			red.emission_enabled = true
			red.emission = Color(1.0, 0.12, 0.05)
			red.emission_energy_multiplier = 0.4
			piece(_beacon_head, dome, Vector3.ZERO, red)
			_beacon = SpotLight3D.new()
			_beacon.light_color = Color(1.0, 0.16, 0.08)
			_beacon.light_energy = 0.0
			_beacon.spot_range = 22.0
			_beacon.spot_angle = 38.0
			_beacon.shadow_enabled = false
			_beacon.rotation.y = PI * 0.5
			_beacon_head.add_child(_beacon)
		"harpoon":
			var hemp := material(Color(0.42, 0.33, 0.2))
			_rope = box(self, Vector3(0.028, 0.028, 1), Vector3.ZERO, hemp)
			_rope.top_level = true
			_rope.visible = false
			_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"supply":
			pass
	if kind in SUPPORT:
		tracer.visible = false

func _build_beam_cone() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.24
	cone.bottom_radius = tan(deg_to_rad(11.0)) * float(spec().range) + 0.24
	cone.height = float(spec().range)
	cone.radial_segments = 24
	cone.rings = 1
	_beam_cone = MeshInstance3D.new()
	_beam_cone.mesh = cone
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://shaders/tower_beam.gdshader")
	_beam_cone.material_override = glow
	_beam_cone.rotation.x = PI * 0.5
	_beam_cone.position.z = -float(spec().range) * 0.5
	_beam_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(_beam_cone)

func max_hp() -> float:
	return HEALTH[level - 1]*float(spec().health)

# What a tier brings, for the Mechanic's upgrade rows: the gun's damage per hit (the mortar shell's
# blast), the range and the hull.
func damage_at(tier: int) -> float:
	return float(spec().damage) + (tier - 1) * tier_step()

# What one tier adds to the kind's own number: a mortar shell, a rocket, a harpoon, a heal tick.
func tier_step() -> float:
	match kind:
		"mortar": return 50.0
		"rocket": return 25.0
		"sniper": return 30.0
		"harpoon": return 60.0
		"graviton": return 10.0
		"supply": return 10.0
		"frost": return 3.0
		"searchlight", "siren": return 0.0
	return 7.0

# The label of that number on the Mechanic's rows.
func stat_label() -> String:
	match kind:
		"supply": return "heal"
		"searchlight", "siren": return "effect"
	return "damage"

func range_at(tier: int) -> float:
	return float(spec().range) + (tier - 1) * 6.0

func hp_at(tier: int) -> float:
	return HEALTH[clampi(tier, 1, 3) - 1] * float(spec().health)

func attack_point(from: Vector3) -> Vector3:
	var direction := Vector3(from.x - global_position.x, 0, from.z - global_position.z).normalized()
	return global_position + direction * 1.05

func damage(amount: float) -> void:
	if replica or NetSession.is_client() or hp <= 0.0: return
	hp = maxf(0, hp - amount)
	refresh()
	if hp <= 0:
		game.defences.release_tower(self)
		Sfx.play_at(game, "barricade_break", global_position, -2)
		game.hud.message("Gun turret destroyed!", 2)
		queue_free()

func refresh() -> void:
	if reinforcement: reinforcement.visible = level >= 2 and not rooftop
	if armour: armour.visible = level >= 3
	if label:
		label.visible = operator_peer == 0 or operator_peer != (NetSession.local_id() if NetSession.enabled else game.player.peer_id)
		var args := [spec().name, Lang.raw("I".repeat(level)), ceili(hp), int(max_hp())]
		label.text = Lang.t("%s %s · %d / %d · OCCUPIED", args) if operator_peer else Lang.t("%s %s · %d / %d", args)
		label.modulate = Color(1, 0.58, 0.32) if hp < max_hp() * 0.4 else Color(0.82, 0.9, 0.76)

func target_point(enemy: Zombie) -> Vector3:
	if enemy is Earthworm: return enemy.aim_point()
	# Aim inside an animated torso hitbox, including hunched/leaning variants.
	for volume in enemy._shot_volumes:
		var bone: String = volume.bone_name.to_lower()
		if "spine" in bone or "chest" in bone: return volume.to_global(volume.center)
	for area in enemy._hitboxes:
		var bone: String = str(area.get_parent().bone_name).to_lower()
		if not ("spine" in bone or "chest" in bone): continue
		var shape: CollisionShape3D = area.get_child(0)
		if not shape.has_meta("tower_center"):
			var center := Vector3.ZERO
			var points: PackedVector3Array = shape.shape.points
			for point in points: center += point
			shape.set_meta("tower_center",center/maxi(1,points.size()))
		return shape.to_global(shape.get_meta("tower_center"))
	return enemy.global_position+Vector3.UP*enemy.height*0.55

# Where the muzzle ends up once the gun has swung onto `aim`. Sight checks use this, not the
# barrel's current pose: a roof turret that dipped over the eaves at a zombie by the wall put its
# muzzle behind the hut wall, every later check failed and it stayed blind for the rest of the round.
func muzzle_toward(aim: Vector3) -> Vector3:
	var direction := aim - gun.global_position
	var pitch := atan2(direction.y, Vector2(direction.x, direction.z).length())
	if kind in ["tesla", "siren", "supply"]: pitch = 0.0
	elif kind == "mortar": pitch = maxf(0.8, pitch)
	var pose := Transform3D(Basis.from_euler(Vector3(pitch, atan2(-direction.x, -direction.z) - rotation.y, 0)), gun.position)
	return global_transform * (pose * muzzle.position)

# The harpoon's prey: the giants and the heavy infected it was built for.
static func is_heavy(z: Zombie) -> bool:
	return Zombie.is_boss_kind(str(z.net_kind)) or str(z.net_kind) in HEAVY_KINDS

# What the siren can lure: the common horde. Bosses, the bride and the beasts keep their own minds.
static func lurable(z: Zombie) -> bool:
	return is_instance_valid(z) and z.alive and not Zombie.is_boss_kind(str(z.net_kind)) and str(z.net_kind) not in ["bride", "zombie_dog", "zombie_stag"]

func can_see(z: Zombie) -> bool:
	if not is_instance_valid(z) or not z.targetable(): return false
	if kind == "supply": return false
	if kind == "siren":
		return lurable(z) and global_position.distance_to(z.global_position) <= attack_range()
	if kind == "rocket" and global_position.distance_to(z.global_position) < ROCKET_MIN_RANGE: return false
	var direction := z.global_position - global_position
	if Vector2(direction.x, direction.z).length_squared() > 0.01:
		var yaw := atan2(-direction.x, -direction.z)
		if absf(angle_difference(rotation.y, yaw)) > HALF_ARC: return false
	var aim := target_point(z)
	var origin := muzzle_toward(aim)
	if origin.distance_squared_to(aim) > pow(attack_range(), 2): return false
	var q := PhysicsRayQueryParameters3D.create(origin, aim, Zombie.SHOT_MASK, [body.get_rid()])
	q.collide_with_areas = true
	if not z._shot_volumes.is_empty() and z._hitboxes.is_empty():
		# Reject a covered target before searching every other enemy for an
		# occluder. Limbs protruding in front of cover remain valid targets.
		q.collision_mask = 1 | 8
		var world_hit := get_world_3d().direct_space_state.intersect_ray(q)
		var endpoint: Vector3 = world_hit.position if not world_hit.is_empty() else aim
		var exposed := false
		for volume in z._shot_volumes:
			if not volume.intersect(q.from, endpoint, false).is_empty():
				exposed = true
				break
		if not exposed: return false
		q.collision_mask = Zombie.SHOT_MASK
	var hit := Zombie.cast_ray(self, q)
	return Zombie.from_hit(hit) == z

func _physics_process(delta: float) -> void:
	_flash_t = maxf(0, _flash_t - delta)
	_trace_travel += delta * 280.0
	tracer.visible = _trace_travel < _trace_distance and kind in ["standard", "mg42", "sniper"]
	if tracer.visible:
		var length := minf(2.2, minf(_trace_travel, _trace_distance - _trace_travel))
		tracer.global_position = _trace_origin + _trace_direction * _trace_travel
		tracer.scale = Vector3(0.7, 0.7, maxf(0.02, length))
	flash.visible = _flash_t > 0
	flash.light_energy = (1.7 + sin(Time.get_ticks_msec() * 0.067) * 0.3) if kind == "flame" else 3.5 * clampf(_flash_t / 0.045, 0, 1)
	# Exact damped-spring solution: the mesh recoils, the ballistic aim and seat stay stable.
	var omega := 15.0 if kind == "mortar" else 24.0
	var impulse := _recoil_velocity + omega * _recoil
	var decay := exp(-omega * delta)
	_recoil = (_recoil + impulse * delta) * decay
	_recoil_velocity = (_recoil_velocity - omega * impulse * delta) * decay
	if _weapon_model:
		_weapon_model.position = _model_rest + Vector3(0, 0, _recoil)
		_weapon_model.rotation.x = _recoil * 0.4
	gun.rotation.y = lerp_angle(gun.rotation.y, aim_yaw, minf(1, delta * 4.0))
	gun.rotation.x = lerp_angle(gun.rotation.x,0.0 if kind in ["tesla","siren","supply"] else maxf(0.8,aim_pitch) if kind=="mortar" else aim_pitch,minf(1,delta*4.0))
	_update_special_visuals(delta)
	if replica or NetSession.is_client() or not game.started or game.over: return
	active_t = maxf(0.0, active_t - delta)
	if tether_t > 0.0:
		tether_t = maxf(0.0, tether_t - delta)
		if is_instance_valid(tether) and tether.alive: tether_end = target_point(tether)
		else: tether_t = 0.0
	if tether_t <= 0.0:
		tether = null
		tether_end = Vector3.INF
	cooldown -= delta
	heat = maxf(0, heat - delta * (0.3 if overheated else 0.1))
	if overheated and heat <= 0.05: overheated = false
	if operator_peer:
		var p: Player = NetSession.world.actor(operator_peer) if NetSession.enabled else game.player
		if not is_instance_valid(p) or not p.alive:
			game.defences.release_tower(self)
			return
		p.global_position = seat_position()
		control_timeout -= delta
		if control_timeout <= 0:
			trigger = false
			aiming = false
		if trigger and cooldown <= 0 and not overheated:
			var basis := p.camera.global_basis
			var direction := preload("res://scripts/aim_model.gd").sample_direction(-basis.z, basis.x, basis.y, manual_spread(), randf(), randf() * TAU)
			var aim := p.camera.global_position + direction*attack_range()
			var ray := PhysicsRayQueryParameters3D.create(p.camera.global_position,aim,Zombie.SHOT_MASK,[body.get_rid(),p.get_rid()])
			ray.collide_with_areas = true
			var hit := Zombie.cast_ray(self, ray)
			fire_at(hit.position if not hit.is_empty() else aim)
		return
	if kind == "supply":
		_supply_clock -= delta
		if cooldown <= 0.0 and _supply_clock <= 0.0:
			_supply_clock = 0.5
			if _supply_needed(): fire_at(global_position + Vector3.UP * 2.0)
		return
	if kind == "siren":
		_scan -= delta
		if _scan <= 0.0:
			_scan = 0.25
			if cooldown <= 0.0:
				var bait := _lure_candidates()
				if not bait.is_empty(): fire_at(bait[0].global_position)
		return
	_scan -= delta
	if _scan <= 0:
		_scan = 0.25
		target = null
		var candidates: Array[Zombie] = []
		var reach_squared := pow(attack_range(), 2)
		for z in game.zombies_root.get_children():
			if not z is Zombie or not z.alive: continue
			if muzzle.global_position.distance_squared_to(target_point(z)) > reach_squared: continue
			candidates.append(z)
		# Preserve nearest-visible targeting, but stop after the first visible
		# candidate instead of casting through the horde in spawn order.
		candidates.sort_custom(func(a: Zombie, b: Zombie): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
		# The harpoon launcher waits for a giant while any is in reach; only an empty field gets the small fry.
		if kind == "harpoon":
			var heavies := candidates.filter(func(z: Zombie): return is_heavy(z))
			if not heavies.is_empty(): candidates = heavies
		for z in candidates:
			if can_see(z):
				target = z
				break
		# Nothing in sight: level the barrel instead of leaving it dipped at the last kill.
		if not target: aim_pitch = 0.0
	if not is_instance_valid(target) or not target.alive:
		_lit_target = null
		return
	var direction := (head_point(target) if kind == "sniper" else target_point(target)) - gun.global_position
	aim_yaw = wrapf(atan2(-direction.x, -direction.z) - rotation.y, -PI, PI)
	aim_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	var aligned: bool = absf(angle_difference(gun.rotation.y, aim_yaw)) < 0.12 and (kind in ["tesla","mortar"] or absf(angle_difference(gun.rotation.x, aim_pitch)) < 0.12)
	if kind == "searchlight":
		# The lamp follows its target and keeps it lit; a fresh target gets the pulse (the lock-on sweep).
		if aligned and can_see(target):
			target.spot_mark_t = maxf(target.spot_mark_t, 0.5)
			active_t = maxf(active_t, 0.35)
			if target != _lit_target and cooldown <= 0.0: shoot()
		return
	if cooldown <= 0 and not overheated and aligned and can_see(target):
		shoot()

# The head of a body, for the sniper nest: the head's own shot volume or hitbox, else the top of the torso.
func head_point(enemy: Zombie) -> Vector3:
	if enemy is Earthworm: return enemy.aim_point()
	for volume in enemy._shot_volumes:
		if "head" in str(volume.bone_name).to_lower(): return volume.to_global(volume.center)
	for area in enemy._hitboxes:
		if "head" in str(area.get_parent().bone_name).to_lower():
			var shape: CollisionShape3D = area.get_child(0)
			return shape.global_position
	return enemy.global_position + Vector3.UP * enemy.height * 0.9

func shoot() -> void:
	if not is_instance_valid(target) or not target.alive: return
	var aim := head_point(target) if kind == "sniper" else target_point(target)
	# Ballistic dispersion can miss; world geometry and other enemies stop each shot.
	var distance := muzzle.global_position.distance_to(aim)
	aim += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * distance * 0.009
	fire_at(aim)

func fire_at(aim: Vector3) -> void:
	chain_points.clear()
	cooldown = float(spec().rate) * (1.0-(level-1)*0.1)
	heat = minf(1, heat + float(spec().heat))
	if heat >= 0.99: overheated = true
	var direction := (aim - muzzle.global_position).normalized()
	var end: Vector3 = muzzle.global_position + direction * attack_range()
	var q := PhysicsRayQueryParameters3D.create(muzzle.global_position, end, Zombie.SHOT_MASK, [body.get_rid()])
	q.collide_with_areas = true
	var hit := Zombie.cast_ray(self, q)
	last_impact = hit.position if not hit.is_empty() else end
	var z := Zombie.from_hit(hit)
	if not z and kind in ["standard", "mg42"]:
		preload("res://scripts/bullet_impacts.gd").hit(game, hit)
	if kind not in ["mortar", "rocket", "graviton"] and not is_support() and not hit.is_empty() and game.hunting:
		game.hunting.hit(hit.collider, damage_at(level), operator_peer if operator_peer else owner_peer)
	match kind:
		"mortar":
			last_impact = muzzle.global_position + (aim - muzzle.global_position).limit_length(attack_range())
			launch_shell(true)
		"rocket":
			last_impact = muzzle.global_position + (aim - muzzle.global_position).limit_length(attack_range())
			launch_rockets(true)
		"frost":
			for enemy in _cone(direction, 20.0):
				hurt(enemy, direction)
				_chill(enemy)
		"sniper":
			_pierce(direction, hit)
		"harpoon":
			if z and z.alive:
				var heavy := is_heavy(z)
				hurt(z, direction, 1.0 if heavy else 0.35)
				if heavy and z.alive:
					tether = z
					tether_t = TETHER_SECONDS
					tether_end = target_point(z)
					z.tether_t = TETHER_SECONDS
		"graviton":
			# the trap goes off where it was aimed (a wall on the way stops it earlier), not where the ray ends
			var reach: Vector3 = muzzle.global_position + (aim - muzzle.global_position).limit_length(attack_range())
			if hit.is_empty() or muzzle.global_position.distance_to(hit.position) > muzzle.global_position.distance_to(reach): last_impact = reach
			_implode(last_impact)
		"searchlight":
			_pulse_mark()
		"siren":
			_lure()
		"supply":
			_supply_tick()
		"flame":
			for enemy in game.zombies_root.get_children():
				if not enemy is Zombie or not enemy.alive: continue
				var offset: Vector3 = target_point(enemy)-muzzle.global_position
				if offset.length()<=attack_range() and offset.normalized().dot(direction)>cos(deg_to_rad(20)) and clear_ray(muzzle.global_position,enemy):
					hurt(enemy,direction)
		"tesla":
			if z and z.alive:
				var chained: Array[Zombie] = [z]
				var previous := z
				hurt(z,direction)
				for i in 2+level:
					var next: Zombie
					var best := 7.0
					for enemy in game.zombies_root.get_children():
						if not enemy is Zombie or not enemy.alive or enemy in chained: continue
						var gap: float = previous.global_position.distance_to(enemy.global_position)
						if gap<best and clear_ray(previous.global_position+Vector3.UP*previous.height*0.7,enemy):
							next = enemy
							best = gap
					if not next: break
					chain_points.append(target_point(previous))
					chain_points.append(target_point(next))
					hurt(next,direction,0.75)
					chained.append(next)
					previous = next
		_:
			if z and z.alive: hurt(z,direction)
	shots += 1
	show_shot()

func hurt(enemy: Zombie, direction: Vector3, multiplier := 1.0, headshot := false) -> void:
	enemy.killer_peer = operator_peer if operator_peer else owner_peer
	enemy.killer_weapon = "tower"
	enemy.last_headshot = headshot
	# A searchlight on the body: every tower hits it harder for as long as the beam rests on it.
	var lit: float = MARK_BONUS if float(enemy.get("spot_mark_t")) > 0.0 else 1.0
	enemy.damage(damage_at(level) * multiplier * lit * (1.5 if headshot else 1.0), direction)

# Every body inside a cone from the muzzle, in sight: the flamethrower's and the frost cannon's reach.
func _cone(direction: Vector3, half_angle_deg: float) -> Array[Zombie]:
	var hits: Array[Zombie] = []
	for enemy in game.zombies_root.get_children():
		if not enemy is Zombie or not enemy.alive: continue
		var offset: Vector3 = target_point(enemy) - muzzle.global_position
		if offset.length() <= attack_range() and offset.normalized().dot(direction) > cos(deg_to_rad(half_angle_deg)) and clear_ray(muzzle.global_position, enemy):
			hits.append(enemy)
	return hits

# The frost cannon chills through the cryo SMG's own build-up: a full meter freezes the body solid
# with the frost status, label, shader and snapshot the rare market already owns.
func _chill(enemy: Zombie) -> void:
	var specials = preload("res://scripts/weapon_specials.gd").for_scene(game)
	if specials == null or not enemy.alive: return
	var amount := 0.12 + (level - 1) * 0.02
	if is_heavy(enemy): amount *= 0.4
	specials.chill(enemy, amount, operator_peer if operator_peer else owner_peer, "cryo_smg")

# The sniper nest: one round through up to three bodies, each further one at 70 %, a head hit at 150 %.
# The world stops it, like every other bullet.
func _pierce(direction: Vector3, first: Dictionary) -> void:
	var hit := first
	var victims := 0
	var share := 1.0
	var seen: Array = []
	var guard := 0
	while not hit.is_empty() and guard < 8:
		guard += 1
		var z := Zombie.from_hit(hit)
		if z == null:
			preload("res://scripts/bullet_impacts.gd").hit(game, hit)
			break
		if z.alive and z not in seen:
			seen.append(z)
			var head: bool = hit.position.distance_to(head_point(z)) < 0.32
			hurt(z, direction, share, head)
			victims += 1
			share *= 0.7
			if victims >= 3: break
		# carry on behind the body: the hit volumes are not physics bodies, so the ray simply restarts
		# a little past the entry point and a second hit on the same body is skipped
		var from: Vector3 = hit.position + direction * 0.45
		var q := PhysicsRayQueryParameters3D.create(from, muzzle.global_position + direction * attack_range(), Zombie.SHOT_MASK, [body.get_rid()])
		q.collide_with_areas = true
		hit = Zombie.cast_ray(self, q)
	last_impact = hit.position if not hit.is_empty() else muzzle.global_position + direction * attack_range()

# The rocket pod: four darts out of the four tubes, 110 ms apart, each a drone rocket with a 5 m
# blast that the host credits to the tower. Replicas launch the same salvo from the snapshot and
# only fly it; the bursts reach them as the host's explosion RPC.
func launch_rockets(authoritative: bool) -> void:
	for i in ROCKETS_PER_SALVO:
		if i == 0: _launch_rocket(i, authoritative)
		else: get_tree().create_timer(0.11 * i, false).timeout.connect(_launch_rocket.bind(i, authoritative))

func _launch_rocket(index: int, authoritative: bool) -> void:
	if not is_inside_tree() or not is_instance_valid(muzzle): return
	var tube := Vector3(0.17 if index % 2 == 0 else -0.17, 0.17 if index < 2 else -0.17, 0.0)
	var origin: Vector3 = muzzle.global_transform * tube
	var direction := (last_impact - origin).normalized()
	direction = direction.rotated(Vector3.UP, randf_range(-0.012, 0.012)).rotated(direction.cross(Vector3.UP).normalized(), randf_range(-0.012, 0.012))
	var rocket = preload("res://scripts/drone_rocket.gd").new()
	rocket.setup(game, origin, direction, attack_range() + 4.0, damage_at(level), operator_peer if operator_peer else owner_peer, "tower", not authoritative)
	rocket.heavy_bonus = 1.5
	rocket.excluded.append(body.get_rid())
	game.add_child(rocket)
	_recoil_velocity = minf(7, _recoil_velocity + 0.9)
	_flash_t = 0.07

# The graviton trap: everything within PULL_RADIUS of the impact is dragged towards it (the far ones
# hardest, so the heap forms where the shot landed) and takes a little damage. The optics and the
# sound belong to show_shot, which every peer runs.
func _implode(point: Vector3) -> void:
	for enemy in game.zombies_root.get_children():
		if not enemy is Zombie or not enemy.alive: continue
		var centre: Vector3 = enemy.global_position + Vector3.UP * enemy.height * 0.5
		var distance := point.distance_to(centre)
		if distance > PULL_RADIUS + enemy.height * 0.25: continue
		var pull := 2.5 + 4.5 * clampf(distance / PULL_RADIUS, 0.0, 1.0)
		# the hit first: damage() writes its own knockback, the shove towards the point has to win
		hurt(enemy, (centre - point).normalized())
		if enemy.alive: enemy.shove((point - centre).normalized() * pull)
	if game.hunting: game.hunting.blast(point, PULL_RADIUS * 0.5, damage_at(level), operator_peer if operator_peer else owner_peer)

# The searchlight's lock-on pulse: everything inside the beam is marked for three seconds at once.
func _pulse_mark() -> void:
	active_t = maxf(active_t, 1.5)
	_lit_target = target
	var forward: Vector3 = -muzzle.global_basis.z
	for enemy in game.zombies_root.get_children():
		if not enemy is Zombie or not enemy.alive: continue
		var offset: Vector3 = target_point(enemy) - muzzle.global_position
		if offset.length() <= attack_range() and offset.normalized().dot(forward) > cos(deg_to_rad(14.0)):
			enemy.spot_mark_t = maxf(enemy.spot_mark_t, 3.0)

func _lure_candidates() -> Array[Zombie]:
	var bait: Array[Zombie] = []
	var reach_squared := pow(attack_range(), 2)
	for enemy in game.zombies_root.get_children():
		if enemy is Zombie and lurable(enemy) and global_position.distance_squared_to(enemy.global_position) <= reach_squared:
			bait.append(enemy)
	bait.sort_custom(func(a: Zombie, b: Zombie): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return bait

# The siren: every common zombie in reach forgets the player, the gates and the hut for 12 s and
# comes for the siren itself (zombie.gd honours lure_tower in _choose_defence).
func _lure() -> void:
	active_t = LURE_SECONDS
	for enemy in _lure_candidates():
		enemy.lure_tower = self
		enemy.lure_t = LURE_SECONDS

# Structures and shooters the supply post would tend to right now.
func _supply_needed() -> bool:
	for bar in _supply_structures():
		if bar.hp < bar.max_hp(): return true
	for p in _supply_players():
		var w = p.equipped_weapons()
		if w and w.has_ammo_space(w.ammo_weapon()) and _ammo_due(p): return true
	return false

func _supply_structures() -> Array:
	var found: Array = []
	var reach := attack_range()
	var lines: Array = game.defence_lines() if game.has_method("defence_lines") else (game.get("barricades") if game.get("barricades") is Array else [])
	for bar in lines:
		if not is_instance_valid(bar) or bar.hp <= 0.0: continue
		if bar.has_method("distance_to_line") and bar.distance_to_line(global_position) > reach: continue
		found.append(bar)
	for other in game.defences.towers.values():
		if is_instance_valid(other) and other != self and other.hp > 0.0 and other.global_position.distance_to(global_position) <= reach:
			found.append(other)
	return found

func _supply_players() -> Array:
	var actors: Array = NetSession.world.actors.values() if NetSession.enabled and NetSession.world else [game.player]
	var near: Array = []
	for p in actors:
		if is_instance_valid(p) and p is Player and p.alive and p.global_position.distance_to(global_position) <= 6.0: near.append(p)
	return near

func _ammo_due(p: Player) -> bool:
	return Time.get_ticks_msec() / 1000.0 - float(_ammo_given.get(p.peer_id, -1000.0)) >= 20.0

# The supply post's tick: `damage` points of repair on every gate, sandbag line and tower in reach,
# half a magazine for every shooter standing beside it (once per 20 s and player).
func _supply_tick() -> void:
	var heal := damage_at(level)
	for bar in _supply_structures():
		if bar.hp >= bar.max_hp(): continue
		bar.hp = minf(bar.max_hp(), bar.hp + heal)
		if bar.has_method("_update_health_display"): bar._update_health_display()
		elif bar.has_method("refresh"): bar.refresh()
	for p in _supply_players():
		var w = p.equipped_weapons()
		if w == null or not _ammo_due(p): continue
		var id: String = w.ammo_weapon()
		if not w.has_ammo_space(id): continue
		_ammo_given[p.peer_id] = Time.get_ticks_msec() / 1000.0
		w.add_ammo(id, ceili(float(Weapons.DEFS[id].mag) * 0.5))
		if p == game.player: game.hud.message(Lang.t("Supply post: ammunition for the %s", [Weapons.DEFS[id].name]), 1.5)

# Beam, beacon and rope move on every peer: the host from its own state, a replica from the snapshot.
func _update_special_visuals(delta: float) -> void:
	match kind:
		"searchlight":
			var on := active_t > 0.0
			var pulse := active_t > 0.5
			_beam.light_energy = move_toward(_beam.light_energy, (11.0 if pulse else 6.0) if on else 0.0, delta * 30.0)
			if _beam.light_energy > 0.05 and _beam_cone == null: _build_beam_cone()
			if _beam_cone:
				_beam_cone.visible = _beam.light_energy > 0.05
				var glow: ShaderMaterial = _beam_cone.material_override
				glow.set_shader_parameter("strength", _beam.light_energy / 6.0)
		"siren":
			var on := active_t > 0.0
			if on: _beacon_head.rotation.y += delta * 5.5
			_beacon.light_energy = move_toward(_beacon.light_energy, 4.0 if on else 0.0, delta * 20.0)
			var dome: MeshInstance3D = _beacon_head.get_child(0)
			(dome.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if on else 0.4
		"harpoon":
			var taut := tether_t > 0.0 and tether_end.is_finite()
			_rope.visible = taut
			if taut:
				var from := muzzle.global_position
				var length := from.distance_to(tether_end)
				if length > 0.05:
					_rope.global_position = from.lerp(tether_end, 0.5)
					_rope.look_at(tether_end, Vector3.UP)
					_rope.scale = Vector3(1, 1, length)
		"supply":
			if _supply_clock < 0.0: _supply_clock = 0.0

func clear_ray(from: Vector3, enemy: Zombie) -> bool:
	if kind == "siren": return true
	var ray := PhysicsRayQueryParameters3D.create(from,target_point(enemy),1|8,[body.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func launch_shell(authoritative: bool) -> void:
	var shell = preload("res://scripts/tower_shell.gd").new()
	shell.start = muzzle.global_position
	shell.destination = last_impact
	shell.damage_amount = float(spec().damage)+(level-1)*50.0
	shell.owner_peer = operator_peer if operator_peer else owner_peer
	shell.authoritative = authoritative
	shell.excluded.append(body.get_rid())
	shell.game = game
	game.add_child(shell)

func _build_variant(steel: Material, copper: Material) -> void:
	var path := "res://assets/models/tower_%s.glb" % kind
	if kind == "standard" and not ResourceLoader.exists(path): return
	for child in gun.get_children():
		if child is MeshInstance3D: child.hide()
	if ResourceLoader.exists(path):
		if not _model_scenes.has(path): _model_scenes[path] = load(path)
		var model: Node3D = _model_scenes[path].instantiate()
		model.name = "WeaponModel"
		gun.add_child(model)
		if kind=="flame": gun.position.y = 0.9 if rooftop else 3.4
	elif kind == "siren":
		# Two flared horns and the motor housing; the beacon dome comes from _build_special.
		box(gun, Vector3(0.5, 0.42, 0.55), Vector3(0, 0.05, 0.2), steel)
		for x in [-0.27, 0.27]:
			var horn := CylinderMesh.new()
			horn.top_radius = 0.09
			horn.bottom_radius = 0.3
			horn.height = 0.75
			horn.radial_segments = 20
			var mouth := piece(gun, horn, Vector3(x, 0.08, -0.5), steel)
			mouth.rotation.x = -PI * 0.5
	elif kind == "supply":
		# Crates, a medical box and the radio mast: the post is a pallet, not a gun.
		var olive := material(Color(0.33, 0.37, 0.24))
		var white := material(Color(0.86, 0.86, 0.82))
		box(gun, Vector3(1.1, 0.1, 0.9), Vector3(0, -0.3, 0), steel)
		box(gun, Vector3(0.55, 0.34, 0.4), Vector3(-0.25, -0.08, 0.2), olive)
		box(gun, Vector3(0.55, 0.34, 0.4), Vector3(-0.25, 0.26, 0.2), olive)
		box(gun, Vector3(0.42, 0.3, 0.42), Vector3(0.28, -0.1, -0.15), olive)
		box(gun, Vector3(0.36, 0.22, 0.26), Vector3(0.28, 0.16, -0.15), white)
		box(gun, Vector3(0.06, 0.12, 0.02), Vector3(0.28, 0.16, -0.285), material(Color(0.8, 0.1, 0.1)))
		box(gun, Vector3(0.14, 0.04, 0.02), Vector3(0.28, 0.16, -0.285), material(Color(0.8, 0.1, 0.1)))
		var mast := cylinder(gun, 0.018, 1.6, Vector3(0.45, 0.6, 0.3), steel)
		mast.position.y = 0.55
	elif kind == "searchlight":
		# A drum with a lens, until the Meshy lamp is imported.
		var drum := cylinder(gun, 0.42, 0.7, Vector3(0, 0, -0.35), steel)
		drum.rotation.x = PI * 0.5
		var lens := material(Color(0.9, 0.95, 1.0))
		lens.emission_enabled = true
		lens.emission = Color(1.0, 0.95, 0.8)
		var glass := cylinder(gun, 0.38, 0.03, Vector3(0, 0, -0.71), lens)
		glass.rotation.x = PI * 0.5
	else:
		# Functional preview while generated assets are being imported.
		box(gun,Vector3(0.6,0.5,0.8),Vector3.ZERO,steel)
		var barrel := cylinder(gun,0.2 if kind=="mortar" else 0.07,1.7,Vector3(0,0,-0.9),steel)
		barrel.rotation.x = PI/2
		if kind=="flame":
			for x in [-0.5,0.5]: cylinder(gun,0.2,0.9,Vector3(x,0,0.25),material(Color(0.5,0.12,0.06)))
		if kind=="tesla":
			barrel.hide()
			for i in 9: cylinder(gun,0.35,0.055,Vector3(0,0.1+i*0.09,0),copper)
	if kind=="tesla": muzzle.position = Vector3(0,1.25,0)
	elif kind=="searchlight": muzzle.position = Vector3(0,0,-1.1)
	elif kind=="siren": muzzle.position = Vector3(0,0.1,-1.0)
	elif kind=="supply": muzzle.position = Vector3(0,0.9,0)

func show_shot() -> void:
	if not is_inside_tree() or not muzzle: return
	var start := muzzle.global_position
	var direction := last_impact - start
	if direction.length() < 0.05: return
	if not shot_audio:
		shot_audio = preload("res://scripts/tower_audio.gd").new()
		shot_audio.tower = self
		muzzle.add_child(shot_audio)
	shot_audio.fire()
	fx.global_basis = muzzle.global_basis if kind in ["mortar", "rocket"] else Basis.looking_at(direction.normalized(), Vector3.UP)
	fx.fire(minf(direction.length(), attack_range()))
	_recoil_velocity = minf(7, _recoil_velocity + {"mortar": 6.0, "mg42": 1.3, "standard": 1.8, "flame": 0.12, "frost": 0.1, "sniper": 2.6, "harpoon": 2.2, "graviton": 0.8}.get(kind, 0.0))
	_flash_t = {"flame": 0.20, "frost": 0.16, "mortar": 0.09, "siren": 0.5, "supply": 0.4, "searchlight": 0.3, "rocket": 0.0}.get(kind, 0.045)
	flash.light_color = {"tesla": Color(0.3, 0.6, 1), "frost": Color(0.55, 0.8, 1), "graviton": Color(0.6, 0.3, 1), "siren": Color(1, 0.15, 0.08), "supply": Color(0.4, 1, 0.5), "searchlight": Color(1, 0.95, 0.8)}.get(kind, Color(1, 0.58, 0.18))
	if operator_peer == game.player.peer_id:
		game.player.add_tremor({"mortar": 0.22, "rocket": 0.12, "sniper": 0.1, "harpoon": 0.14, "graviton": 0.2}.get(kind, 0.045), 0.18)
	match kind:
		"mortar":
			if replica or NetSession.is_client(): launch_shell(false)
			return
		"rocket":
			if replica or NetSession.is_client(): launch_rockets(false)
			return
		"graviton":
			preload("res://scripts/weapon_specials.gd").blast_visuals(game, last_impact)
			return
		"siren":
			active_t = LURE_SECONDS
			return
		"searchlight":
			active_t = maxf(active_t, 1.5)
			return
		"supply":
			fx.pulse(attack_range())
			return
	if kind == "tesla":
		var links := PackedVector3Array([start, last_impact])
		links.append_array(chain_points)
		_lightning.fire(links)
	_trace_origin = start
	_trace_direction = direction.normalized()
	_trace_distance = minf(direction.length(), attack_range()) if kind != "mg42" or shots % 3 == 0 else 0.0
	_trace_travel = 0.0
	tracer.global_position = start
	tracer.look_at(last_impact, Vector3.UP)

# Zombie: navmesh pathing to the player, attacks player or a blocking barricade, plays GLB clips.
class_name Zombie
extends CharacterBody3D

# "skins": every GLB in assets/models that may stand in for the type, one is picked per zombie (missing files
# are skipped, "model" / "fallback" remain the default). The field titan is taller than the beeches (22-29 m)
# and handled by titan.gd (ground strike, no stagger, always casts shadows).
const TYPES := {
	"titan_hunter": {"name": "JAGDTITAN", "model": "zombie_colossus", "hp": 2400.0, "speed": 6.0, "damage": 85.0, "reach": 8.0, "attack_time": 3.0, "score": 230, "height": 8.0, "tint": Color(0.58, 0.83, 0.65), "giant": true, "blast_radius": 4.0, "windup": 1.7, "recovery": 1.1, "structure_mul": 0.65, "warning_color": Color(0.45, 1.0, 0.3)},
	"titan_siege": {"name": "BELAGERUNGSTITAN", "model": "zombie_bloater", "hp": 6000.0, "speed": 2.6, "damage": 130.0, "reach": 10.0, "attack_time": 4.5, "score": 350, "height": 14.0, "tint": Color(0.7, 0.66, 0.51), "giant": true, "blast_radius": 6.0, "windup": 2.8, "recovery": 2.0, "structure_mul": 1.6, "warning_color": Color(1.0, 0.68, 0.1)},
	"titan_ash": {"name": "ASCHETITAN", "model": "zombie_titan", "hp": 4500.0, "speed": 3.6, "damage": 100.0, "reach": 13.0, "attack_time": 4.5, "score": 320, "height": 19.0, "tint": Color(0.68, 0.46, 0.42), "giant": true, "blast_radius": 10.0, "windup": 3.2, "recovery": 2.0, "structure_mul": 1.0, "warning_color": Color(1.0, 0.25, 0.15)},
	"titan": {"model": "zombie_titan", "skins": ["zombie_titan", "zombie_colossus"], "fallback": "zombie_bloater", "hp": 7500.0, "speed": 4.2, "damage": 120.0, "reach": 14.0, "attack_time": 4.0, "score": 400, "height": 27.0, "tint": Color(0.78, 0.8, 0.78), "giant": true},
	"shambler": { "model": "zombie_shambler", "skins": ["zombie_shambler", "zombie_farmer", "zombie_hiker", "zombie_grandma"], "hp": 100.0, "speed": 1.6, "damage": 12.0, "reach": 1.6, "attack_time": 1.1, "score": 10, "height": 1.8 },
	"runner": { "model": "zombie_runner", "skins": ["zombie_runner", "zombie_jogger"], "hp": 60.0, "speed": 4.2, "damage": 8.0, "reach": 1.4, "attack_time": 0.7, "score": 15, "height": 1.7 },
	"brute":    { "model": "zombie_bloater", "fallback": "zombie_shambler", "hp": 320.0, "speed": 1.2, "damage": 25.0, "reach": 2.0, "attack_time": 1.6, "score": 40, "height": 2.3, "tint": Color(0.9, 0.85, 0.6) },
	"nurse":    { "model": "zombie_nurse", "fallback": "zombie_runner", "hp": 80.0, "speed": 2.6, "damage": 10.0, "reach": 1.5, "attack_time": 0.9, "score": 15, "height": 1.7 },
	"soldier":  { "model": "zombie_soldier", "skins": ["zombie_soldier", "zombie_forester"], "fallback": "zombie_shambler", "hp": 180.0, "speed": 1.9, "damage": 16.0, "reach": 1.6, "attack_time": 1.0, "score": 25, "height": 1.85 },
}

var type: Dictionary
var hp: float
var height: float
var alive := true
var player: Player
var barricades: Array = []
var hut_doors: Array = []
var hut: HutHealth                 # the Waldhütte; raiders inside the ring go for it, everyone hits it when close
var perimeter: Perimeter
var raider := false
var agent: NavigationAgent3D
var anim: AnimationPlayer
var model: Node3D
var state := "walk"
var attack_t := 0.0
var hit_pending := 0.0
var hit_target = null
var hit_reach := 1.6
var growl_t := 0.0
var dead_t := 0.0
var speed_mul := 1.0
var frost_mul := 1.0
var rare_status := ""
var _rare_marker: Label3D
var _rare_particles: CPUParticles3D
var _repath := 0.0
var _shadow_t := 0.0
var _on_kill: Callable
var damage_mul := 1.0           # difficulty
var last_headshot := false      # set by weapons before damage(), read by the kill statistics
var killer_weapon := ""          # weapon id of the fatal shot ("" = grenade / other)
var killer_peer := 1
var net_kind := "shambler"
var model_path := ""
var appearance_seed := 0
var replica := false
var siege_target: Node3D
var lane_bar: Barricade
const AGGRO_RANGE := 10.0
const AGGRO_RELEASE_RANGE := 14.0
var _aggro_target: Player
var _aggro_check := 0.0
var hunting := false
var _hunt_refresh := 0.0
var _hunt_path := PackedVector3Array()
var max_hp := 100.0
var net_position := Vector3.ZERO
var net_yaw := 0.0
var _materials: Array[BaseMaterial3D] = []
static var _scenes := {}
static var force_skin := ""          # tests: every new zombie uses this model while it is set (and exists)
const HITBOX_LAYER := 32
const SHOT_MASK := 1 | 8 | HITBOX_LAYER
static var _hitbox_shapes := {}
var _hitboxes: Array[Area3D] = []

static func preload_models() -> void:
	for spec: Dictionary in TYPES.values():
		for name in skin_names(spec):
			var path := "res://assets/models/%s.glb" % name
			if not _scenes.has(path):
				_scenes[path] = load(path) if ResourceLoader.exists(path) else null

# all model names a type may use: its skins, the default model and the fallback
static func skin_names(spec: Dictionary) -> Array:
	var names: Array = []
	for n in spec.get("skins", []):
		names.append(n)
	if not names.has(spec["model"]): names.append(spec["model"])
	if spec.has("fallback") and not names.has(spec["fallback"]): names.append(spec["fallback"])
	return names

# one of the type's generated skins at random; the default model, then the fallback, when none exists yet
static func pick_model_path(spec: Dictionary) -> String:
	if force_skin != "" and ResourceLoader.exists("res://assets/models/%s.glb" % force_skin):
		return "res://assets/models/%s.glb" % force_skin
	var avail: Array = []
	for n in spec.get("skins", [spec["model"]]):
		if ResourceLoader.exists("res://assets/models/%s.glb" % n):
			avail.append(n)
	if not avail.is_empty():
		return "res://assets/models/%s.glb" % avail[randi() % avail.size()]
	var path := "res://assets/models/%s.glb" % spec["model"]
	if not ResourceLoader.exists(path) and spec.has("fallback"):
		path = "res://assets/models/%s.glb" % spec["fallback"]
	return path

static func is_titan_kind(kind: String) -> bool:
	return bool(TYPES.get(kind, {}).get("giant", false))

func setup(type_name: String, p: Player, bars: Array, spd_mul: float, on_kill: Callable) -> void:
	net_kind = type_name
	type = TYPES[type_name]
	player = p
	barricades = bars
	speed_mul = spd_mul
	_on_kill = on_kill
	hp = type["hp"]
	max_hp = hp
	height = type["height"]
	model_path = pick_model_path(type)
	appearance_seed = randi()
	growl_t = randf_range(2.0, 8.0)
	_repath = randf_range(0.05, 0.4)
	raider = randf() < 0.35

func _ready() -> void:
	hut_doors = get_tree().get_nodes_in_group("hut_doors")
	var huts := get_tree().get_nodes_in_group("hut_health")
	if not huts.is_empty():
		hut = huts[0]
		perimeter = hut.game.perimeter
	# The movement capsule is only a bullet fallback for models without a rig.
	collision_layer = 2 | HITBOX_LAYER
	collision_mask = 1 | 2 | 8 | 16
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = height
	shape.shape = cap
	shape.position.y = height / 2.0
	add_child(shape)
	agent = NavigationAgent3D.new()
	agent.radius = 0.45
	agent.height = height
	agent.path_desired_distance = 0.8
	agent.target_desired_distance = 1.0
	agent.avoidance_enabled = not replica
	agent.neighbor_distance = 6.0
	agent.max_neighbors = 6
	agent.max_speed = float(type["speed"]) * speed_mul
	agent.velocity_computed.connect(_on_velocity_computed)
	add_child(agent)
	var appearance := RandomNumberGenerator.new()
	appearance.seed = appearance_seed
	var path := model_path
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var scene = _scenes[path]
	if scene:
		model = scene.instantiate()
		add_child(model)
		_fit_model()
		anim = model.find_child("AnimationPlayer", true, false)
		if anim:
			for n in ["walk", "attack", "death"]:
				if anim.has_animation(n):
					anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR if n == "walk" else Animation.LOOP_NONE
			anim.speed_scale = appearance.randf_range(0.85, 1.15)
			anim.play("walk")
		# pale, desaturated decayed skin instead of the old green cast
		var tint: Color = type.get("tint", Color.from_hsv(appearance.randf_range(0.02, 0.09), appearance.randf_range(0.08, 0.18), appearance.randf_range(0.7, 0.95)))
		for m in model.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var mat: Material = mi.mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					var dup: BaseMaterial3D = mat.duplicate()
					dup.albedo_color = dup.albedo_color * tint
					dup.emission_enabled = true
					dup.emission = Color.BLACK
					mi.set_surface_override_material(i, dup)
					_materials.append(dup)
	var scale_var := appearance.randf_range(0.94, 1.08)
	if model:
		model.scale *= scale_var
		_build_hitboxes()
		if not _hitboxes.is_empty():
			collision_layer = 2

# Keep navigation capsules small; bullets use convex volumes fitted to the rig's
# weighted vertices. Bone attachments follow walking, attacks and model scaling.
func _build_hitboxes() -> void:
	for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if not mesh.skin or mesh.skeleton.is_empty(): continue
		var rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if not rig: continue
		var cache_key := model_path + ":" + str(model.get_path_to(mesh))
		if not _hitbox_shapes.has(cache_key):
			var points := {}
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				if vertices.is_empty() or bones.is_empty(): continue
				var influences := bones.size() / vertices.size()
				for vertex in vertices.size():
					for influence in influences:
						var index := vertex * influences + influence
						if weights[index] < 0.25: continue
						var bind := bones[index]
						var bone := mesh.skin.get_bind_bone(bind)
						if bone < 0: bone = rig.find_bone(mesh.skin.get_bind_name(bind))
						if bone < 0: continue
						if not points.has(bone): points[bone] = PackedVector3Array()
						points[bone].append(mesh.skin.get_bind_pose(bind) * vertices[vertex])
			var shapes := {}
			for bone in points:
				if points[bone].size() < 4: continue
				var hull := ConvexPolygonShape3D.new()
				hull.points = points[bone]
				shapes[bone] = hull
			_hitbox_shapes[cache_key] = shapes
		for bone in _hitbox_shapes[cache_key]:
			var attachment := BoneAttachment3D.new()
			attachment.bone_name = rig.get_bone_name(bone)
			rig.add_child(attachment)
			var area := Area3D.new()
			area.collision_layer = HITBOX_LAYER
			area.collision_mask = 0
			area.monitoring = false
			area.monitorable = false
			area.set_meta("zombie", self)
			area.set_meta("headshot", "head" in str(attachment.bone_name).to_lower())
			attachment.add_child(area)
			var shape := CollisionShape3D.new()
			shape.shape = _hitbox_shapes[cache_key][bone]
			area.add_child(shape)
			_hitboxes.append(area)

static func from_hit(hit: Dictionary) -> Zombie:
	if hit.is_empty(): return null
	var collider: Object = hit.collider
	if collider is Zombie: return collider
	return collider.get_meta("zombie") as Zombie if collider.has_meta("zombie") else null

func _fit_model() -> void:
	# Meshy rigs are exported in metres at the height passed to the rigging step (1.7 m).
	# Skinned mesh AABBs are not reliable here, so scale from that known height.
	var s := height / 1.7
	model.scale = Vector3.ONE * s
	model.position = Vector3.ZERO

func play(name: String) -> void:
	if state == name and name != "attack":
		return
	state = name
	if anim and anim.has_animation(name):
		anim.play(name, 0.15)

func damage(n: float, dir: Vector3) -> void:
	if replica or NetSession.is_client(): return
	if not alive:
		return
	hp -= n
	Sfx.play_at(get_parent(), "hit", global_position, -6.0)
	_flash()
	# flinch: short stagger with knockback along the shot direction, scaled by the hit (heavier for big calibres)
	var k := clampf(n / 60.0, 0.3, 1.5)
	_stagger = maxf(_stagger, 0.16 + 0.14 * k)
	_stagger_len = _stagger
	_knock = Vector3(dir.x, 0.0, dir.z).normalized() * (1.4 + 1.6 * k) / type["hp"] * 100.0
	_knock = _knock.limit_length(3.2)
	attack_t = maxf(attack_t, 0.25)
	if hp <= 0.0:
		die(dir)

var _stagger := 0.0
var _pool: Decal
var _fade_t := 0.0

# called by the wave system: bodies of the previous round sink away
func clear_body() -> void:
	if not alive and _fade_t <= 0.0:
		_fade_t = 4.0 + randf() * 3.0
var _stagger_len := 0.3
var _knock := Vector3.ZERO

var _flash_t := 0.0

func _flash() -> void:
	_flash_t = 0.12
	_set_emission(true)

func _set_emission(on: bool) -> void:
	for material in _materials:
		material.emission = Color(0.5, 0.1, 0.1) if on else Color.BLACK

func die(dir: Vector3) -> void:
	alive = false
	for hitbox in _hitboxes:
		hitbox.collision_layer = 0
	hit_pending = 0.0
	velocity = Vector3.ZERO
	play("death")
	if not type.get("giant", false): Sfx.play_at(get_parent(), "zombie_death", global_position, -20.0)
	collision_layer = 0
	collision_mask = 1
	agent.avoidance_enabled = false
	if _on_kill.is_valid():
		_on_kill.call(self)   # main scores the kill (difficulty, streak) and keeps the statistics
	global_position += Vector3(dir.x, 0.0, dir.z).normalized() * 0.3
	if not replica: _drop_loot()
	# blood pool decal on the ground, grows while the body bleeds out
	var scene := get_tree().current_scene
	if "weapons" in scene and scene.weapons and scene.weapons._splat_tex:
		_pool = Decal.new()
		_pool.texture_albedo = scene.weapons._splat_tex
		_pool.albedo_mix = 1.0
		_pool.modulate = Color(0.32, 0.02, 0.02, 0.3)
		_pool.size = Vector3(0.4, 0.5, 0.35)
		_pool.cull_mask = 1
		scene.add_child(_pool)
		_pool.global_position = global_position + Vector3(dir.x, 0.0, dir.z).normalized() * 0.4 + Vector3(0, 0.05, 0)
		_pool.rotation.y = randf() * TAU

func update_rare_visual() -> void:
	if not _rare_marker and not rare_status.is_empty():
		_rare_marker = Label3D.new()
		_rare_marker.position.y = minf(height, 3.0) + 0.2
		_rare_marker.font_size = 32
		_rare_marker.pixel_size = 0.006
		_rare_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_rare_marker.visibility_range_end = 35
		add_child(_rare_marker)
		_rare_particles = CPUParticles3D.new()
		_rare_particles.amount = 14
		_rare_particles.lifetime = 0.7
		_rare_particles.position.y = minf(height * 0.5, 2.0)
		_rare_particles.direction = Vector3.UP
		_rare_particles.spread = 35
		_rare_particles.initial_velocity_min = 0.4
		_rare_particles.initial_velocity_max = 1.5
		_rare_particles.gravity = Vector3(0, 0.4, 0)
		_rare_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_rare_particles.emission_sphere_radius = 0.28
		var spark := SphereMesh.new()
		spark.radius = 0.035
		spark.height = 0.07
		spark.radial_segments = 6
		spark.rings = 3
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.vertex_color_use_as_albedo = true
		spark.material = glow
		_rare_particles.mesh = spark
		add_child(_rare_particles)
	if _rare_marker:
		_rare_marker.visible = alive and not rare_status.is_empty()
		_rare_marker.text = "BRAND" if rare_status == "fire" else "FROST"
		_rare_marker.modulate = Color(1, 0.4, 0.1) if rare_status == "fire" else Color(0.3, 0.8, 1)
		_rare_particles.emitting = _rare_marker.visible
		_rare_particles.color = _rare_marker.modulate

func _physics_process(delta: float) -> void:
	update_rare_visual()
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0: _set_emission(false)
	if replica:
		global_position = global_position.lerp(net_position, 1.0-exp(-delta*16.0))
		rotation.y = lerp_angle(rotation.y, net_yaw, 1.0-exp(-delta*16.0))
		if not alive and is_instance_valid(_pool):
			dead_t += delta
			var growth := clampf(dead_t / 9.0, 0.0, 1.0)
			var size := 0.4 + 1.5 * (1.0 - pow(1.0 - growth, 2.0))
			_pool.size = Vector3(size, 0.5, size * 0.85)
			_pool.modulate.a = minf(1.0, 0.3 + growth)
		return
	if NetSession.enabled:
		var target_player := NetSession.nearest_player(global_position)
		if target_player: player = target_player
	if not alive:
		dead_t += delta
		if _pool:
			var g := clampf(dead_t / 9.0, 0.0, 1.0)
			var sz := 0.4 + 1.5 * (1.0 - pow(1.0 - g, 2.0))
			_pool.size = Vector3(sz, 0.5, sz * 0.85)
			_pool.modulate.a = minf(1.0, 0.3 + g)
		if _fade_t > 0.0:
			_fade_t -= delta
			if _fade_t < 2.0:
				global_position.y -= delta * (0.35 if height < 5.0 else height * 0.2)
			if _fade_t <= 0.0:
				if _pool:
					_pool.queue_free()
				queue_free()
		return
	if not player or not player.alive or (not player.active and not NetSession.enabled):
		return
	# skinned shadow casters are expensive: only the zombies within 35 m of the player throw shadows
	_shadow_t -= delta
	if _shadow_t <= 0.0 and model:
		_shadow_t = 0.5
		var near_player: bool = bool(type.get("giant", false)) or global_position.distance_squared_to(player.global_position) < 35.0 * 35.0
		for m in model.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near_player else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _stagger > 0.0:
		_stagger -= delta
		var t := _stagger / _stagger_len
		velocity.x = _knock.x * t
		velocity.z = _knock.z * t
		if not is_on_floor():
			velocity.y -= 20.0 * delta
		move_and_slide()
		if model:
			model.rotation.x = -0.4 * sin(t * PI)
			model.position.y = 0.06 * sin(t * PI)
		return
	if model and model.rotation.x != 0.0:
		model.rotation.x = 0.0
		model.position.y = 0.0
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return
	var player_priority := _nearby_player_priority(delta)
	_update_hunt(delta)
	var p := global_position
	var to_player := player.global_position - p
	to_player.y = 0.0
	var dist := to_player.length()
	# Commit to a breach: steering sideways must not cancel a defence target.
	var bar = null
	var bd := 1e9
	if not hunting and is_instance_valid(siege_target) and siege_target.hp > 0.0:
		bar = siege_target
		bd = bar.attack_point(p).distance_squared_to(p)
	var path := _hunt_path if hunting else agent.get_current_navigation_path().slice(agent.get_current_navigation_path_index())
	for b in barricades:
		var blocking: bool = _blocks_hunt(b, path) if hunting else (b.intercepts(p, player.global_position, path) or (b == lane_bar and b.hp > 0.0 and b._local(p).y * b._local(player.global_position).y < 0.0))
		if blocking:
			var dd: float = b.attack_point(p).distance_squared_to(p)
			if bar == null or dd + 16.0 < bd:
				bd = dd
				bar = b
	# Nearby exposed towers can be attacked; a blocking fence still takes priority.
	if bar == null and not hunting:
		for tower in get_tree().get_nodes_in_group("defence_towers"):
			if tower.hp > 0.0 and tower.global_position.distance_squared_to(p) < 12.0 * 12.0:
				var dd: float = tower.attack_point(p).distance_squared_to(p)
				if dd < bd and dd < to_player.length_squared():
					bar = tower
					bd = dd
	# The Waldhütte itself: raiders inside the ring head for its walls, every zombie close to a wall hits it.
	if bar == null and not player_priority and is_instance_valid(hut) and hut.hp > 0.0:
		var hut_point := hut.attack_point(p)
		var hd := hut_point.distance_squared_to(p)
		var inside: bool = not is_instance_valid(perimeter) or perimeter.contains(Vector2(p.x, p.z))
		if (raider and inside and not hunting) or (hd < HutHealth.RAID_RANGE * HutHealth.RAID_RANGE and hd < to_player.length_squared()):
			bar = hut
			bd = hd
	siege_target = bar
	for door: Door in hut_doors:
		if door.crosses(p, player.global_position):
			var dd := door.center.distance_squared_to(p)
			if dd < bd:
				bd = dd
				bar = door
	if player_priority: bar = null
	var target: Vector3 = bar.attack_point(p) if bar else player.global_position
	agent.target_desired_distance = 0.25 if bar else 1.0
	var to_target := target - p
	to_target.y = 0.0
	var d := to_target.length()
	var dir := to_target.normalized()
	# face the target
	var yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, delta * 6.0))
	attack_t -= delta
	var reach: float = 1.9 if bar else type["reach"]
	if d < reach:
		velocity = Vector3.ZERO
		agent.velocity = Vector3.ZERO
		if attack_t <= 0.0:
			play("attack")
			attack_t = type["attack_time"]
			hit_pending = 0.35
			hit_target = bar
			hit_reach = reach
		elif attack_t < type["attack_time"] - 0.7 and state == "attack":
			play("walk")
	else:
		if state != "walk" and attack_t < type["attack_time"] - 0.7:
			play("walk")
		if state == "walk":
			_repath -= delta
			if _repath <= 0.0:
				_repath = 0.35 if dist < 20.0 else 0.8
				if agent.target_position.distance_squared_to(target) > 1.0 or agent.is_navigation_finished():
					agent.target_position = bar.approach_point(p) if bar is Barricade else target
			var next := agent.get_next_path_position()
			var mv := next - p
			mv.y = 0.0
			if hunting and bar == null and _can_hit(null):
				# An open approach must not stall at an obsolete or finished path.
				mv = to_player
			var sp: float = type["speed"] * speed_mul * frost_mul
			var want: Vector3 = mv.normalized() * sp if mv.length() > 0.05 else Vector3.ZERO
			if agent.avoidance_enabled:
				agent.set_velocity(want)
			else:
				_on_velocity_computed(want)
		else:
			velocity = Vector3.ZERO
			agent.velocity = Vector3.ZERO
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	if hit_pending > 0.0:
		hit_pending -= delta
		if hit_pending <= 0.0:
			if hit_target != null and not is_instance_valid(hit_target):
				hit_target = null
				return
			var dd: float = hit_target.attack_point(global_position).distance_to(global_position) if hit_target else player.global_position.distance_to(global_position)
			if dd < hit_reach + 0.6 and _can_hit(hit_target):
				if hit_target:
					hit_target.damage(type["damage"] * damage_mul)
				elif player.alive:
					player.damage(type["damage"] * damage_mul, global_position)
	growl_t -= delta
	if growl_t <= 0.0 and dist < 25.0:
		growl_t = randf_range(4.0, 12.0)
		Sfx.play_at(get_parent(), "growl", global_position, -5.0)

func begin_hunt() -> void:
	hunting = true
	siege_target = null
	lane_bar = null
	hit_pending = 0.0
	_hunt_refresh = 0.0
	_repath = 0.0

func _update_hunt(delta: float) -> void:
	if not hunting: return
	_hunt_refresh -= delta
	if _hunt_refresh <= 0.0:
		_hunt_refresh = 1.0
		siege_target = null
		_hunt_path = NavigationServer3D.map_get_path(agent.get_navigation_map(), global_position, player.global_position, true)
		agent.target_position = player.global_position
		agent.get_next_path_position()
		_repath = 0.0

func _blocks_hunt(bar: Barricade, path: PackedVector3Array) -> bool:
	if bar.hp <= 0.0: return false
	# Only attack barriers on the actual route, never the old assigned spawn lane.
	var previous := global_position
	if path.size() < 2: return bar.crosses(previous, player.global_position)
	for point in path:
		if bar.crosses(previous, point): return true
		previous = point
	return false

func _nearby_player_priority(delta: float) -> bool:
	_aggro_check -= delta
	if _aggro_check <= 0.0 or (is_instance_valid(_aggro_target) and not _aggro_target.alive):
		_aggro_check = 0.2
		var previous := _aggro_target
		_aggro_target = null
		var candidates: Array = NetSession.world.actors.values() if NetSession.is_host() and NetSession.world else [player]
		var nearest := INF
		for candidate: Player in candidates:
			if not is_instance_valid(candidate) or not candidate.alive: continue
			var distance := global_position.distance_to(candidate.global_position)
			var radius := AGGRO_RELEASE_RANGE if candidate == previous else AGGRO_RANGE
			if distance > radius or distance >= nearest: continue
			# Check at ground level even for titans: seeing over a wall must not bypass it.
			var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, candidate.global_position + Vector3.UP, 1 | 8, [get_rid()])
			if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
			nearest = distance
			_aggro_target = candidate
		if previous != _aggro_target:
			_repath = 0.0
			# Cancel a pending swing at the old target when changing priorities.
			hit_pending = 0.0
	if is_instance_valid(_aggro_target) and _aggro_target.alive:
		player = _aggro_target
		return true
	return false

func _on_velocity_computed(safe: Vector3) -> void:
	if replica or not alive or not player or (not player.active and not NetSession.enabled) or get_tree().paused:
		return
	velocity.x = safe.x
	velocity.z = safe.z
	move_and_slide()

func _can_hit(bar: Variant) -> bool:
	var origin := global_position + Vector3.UP * height * 0.65
	var target: Vector3 = bar.attack_point(global_position) + Vector3.UP if bar else player.global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 8)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return true
	if bar == null: return false
	return hit.collider == bar.body or (bar is HutHealth and hit.collider.is_in_group("hut_body"))

# strong push from a melee strike, independent of the hit stagger scaling
func shove(impulse: Vector3) -> void:
	if not alive:
		return
	_stagger = maxf(_stagger, 0.42)
	_stagger_len = _stagger
	_knock = Vector3(impulse.x, 0.0, impulse.z) * (100.0 / maxf(float(type["hp"]), 60.0))
	_knock = _knock.limit_length(5.0)
	attack_t = maxf(attack_t, 0.5)

# Supply drops: bigger zombies drop more often. Ammunition for the current gun, sometimes a grenade or a medkit.
func _drop_loot() -> void:
	var scene := get_tree().current_scene
	if not ("weapons" in scene) or scene.weapons == null:
		return
	var chance := 0.16 + 0.06 * (float(type["score"]) / 10.0)
	if "difficulty" in scene:
		chance *= float(scene.difficulty.get("drop", 1.0))
	if randf() > chance:
		return
	var r := randf()
	var kind := "ammo"
	if r < 0.14:
		kind = "medkit"
	elif r < 0.34:
		kind = "grenade"
	var drop := Pickup.new()
	drop.setup(kind)
	scene.add_child(drop)
	drop.global_position = global_position + Vector3(randf_range(-0.4, 0.4), 0.05, randf_range(-0.4, 0.4))

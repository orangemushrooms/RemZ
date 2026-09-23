# Zombie: navmesh pathing to the player, attacks player or a blocking barricade, plays GLB clips.
class_name Zombie
extends CharacterBody3D

# "skins": every GLB in assets/models that may stand in for the type, one is picked per zombie (missing files
# are skipped, "model" / "fallback" remain the default). The field titan is taller than the beeches (22-29 m)
# and handled by titan.gd (ground strike, no stagger, always casts shadows).
const TYPES := {
	"earthworm": {"name": "DER ERDWURM", "model": "zombie_earthworm", "hp": 2600.0, "speed": 8.0, "damage": 48.0, "reach": 9.0, "attack_time": 3.0, "score": 300, "height": 14.0, "worm": true, "tint": Color.WHITE},
	"earthworm_ancient": {"name": "DER GRABMAHR", "model": "zombie_earthworm_ancient", "hp": 3800.0, "speed": 7.0, "damage": 62.0, "reach": 11.0, "attack_time": 3.4, "score": 420, "height": 19.0, "worm": true, "tint": Color.WHITE},
	"titan_hunter": {"name": "JAGDTITAN", "model": "zombie_colossus", "hp": 1700.0, "speed": 6.0, "damage": 45.0, "reach": 8.0, "attack_time": 3.0, "score": 230, "height": 8.0, "tint": Color(0.58, 0.83, 0.65), "giant": true, "blast_radius": 4.0, "windup": 1.7, "recovery": 1.1, "structure_mul": 0.65, "warning_color": Color(0.45, 1.0, 0.3)},
	"titan_siege": {"name": "BELAGERUNGSTITAN", "model": "zombie_bloater", "hp": 3600.0, "speed": 2.6, "damage": 80.0, "reach": 10.0, "attack_time": 4.5, "score": 350, "height": 14.0, "tint": Color(0.7, 0.66, 0.51), "giant": true, "blast_radius": 6.0, "windup": 2.8, "recovery": 2.0, "structure_mul": 1.6, "warning_color": Color(1.0, 0.68, 0.1)},
	"titan_ash": {"name": "ASCHETITAN", "model": "zombie_titan", "hp": 3000.0, "speed": 3.6, "damage": 60.0, "reach": 13.0, "attack_time": 4.5, "score": 320, "height": 19.0, "tint": Color(0.68, 0.46, 0.42), "giant": true, "blast_radius": 10.0, "windup": 3.2, "recovery": 2.0, "structure_mul": 1.0, "warning_color": Color(1.0, 0.25, 0.15)},
	"titan": {"model": "zombie_titan", "skins": ["zombie_titan", "zombie_colossus"], "fallback": "zombie_bloater", "hp": 4200.0, "speed": 4.2, "damage": 70.0, "reach": 14.0, "attack_time": 4.0, "score": 400, "height": 27.0, "tint": Color(0.78, 0.8, 0.78), "giant": true},
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
var _frost_particles: CPUParticles3D
var _rare_light: OmniLight3D
var _frost_visible := false
var _frost_meshes: Array[MeshInstance3D] = []
var _frost_surface: ShaderMaterial
var _repath := 0.0
var _shadow_t := 0.0
var _shadow_near := -1
var _visual_meshes: Array[MeshInstance3D] = []
var _decision_time := 0.0
var _decision_target: Node3D
var _rest_contact_time := 0.0
var _terrain_floor := RID()
var _ground_ray: PhysicsRayQueryParameters3D
var _ground_motion: PhysicsTestMotionParameters3D
var _on_kill: Callable
var damage_mul := 1.0           # difficulty
var last_headshot := false      # set by weapons before damage(), read by the kill statistics
var killer_weapon := ""          # weapon id of the fatal shot ("" = grenade / other)
var killer_peer := 1
var damage_peers: Dictionary = {} # Contributors for this enemy's lifetime, host only.
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
var _shot_volumes: Array[HitVolume] = []
var _shot_model_transform := Transform3D()
var _shot_world_bounds: AABB
var _shot_has_bounds := false
static var _volume_library: Resource
const HitVolume = preload("res://scripts/zombie_hit_volume.gd")

static func _load_volume_library() -> void:
	if _volume_library: return
	_volume_library = load("res://assets/data/zombie_hit_volumes.tres")
	# Binary export can erase nested Array[Plane] metadata. Restore it once per
	# shared hull: a rejected configure() call otherwise leaves a null rig in
	# release builds, which crashes the host on the first intersecting shot.
	var library: Dictionary = _volume_library.get_meta("volumes", {})
	for shapes: Dictionary in library.values():
		for baked: Dictionary in shapes.values():
			var planes: Array[Plane] = []
			planes.assign(baked.planes)
			baked.planes = planes

static func preload_models() -> void:
	_load_volume_library()
	for spec: Dictionary in TYPES.values():
		for name in skin_names(spec):
			var path := "res://assets/models/%s.glb" % name
			if not _scenes.has(path):
				_scenes[path] = load(path) if ResourceLoader.exists(path) else null
				if _scenes[path]:
					_scenes[path] = preload("res://scripts/zombie_animation.gd").prepare(_scenes[path])
					var source: Node3D = _scenes[path].instantiate()
					_prepare_hitbox_shapes(source, path)
					source.free()

# Submit the real skinned/material variants while the loading screen is still
# up. Loading a GLB alone does not prepare its first visible GPU draw/pipeline.
static func prewarm_visuals(game: Node3D) -> void:
	if DisplayServer.get_name() == "headless": return
	var viewport := SubViewport.new()
	viewport.name = "ZombieRenderWarmup"
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	viewport.size = Vector2i(96, 96)
	viewport.own_world_3d = true
	viewport.msaa_3d = game.get_viewport().msaa_3d
	viewport.use_taa = game.get_viewport().use_taa
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = game.settings.env
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.shadow_enabled = true
	viewport.add_child(light)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 5, 13)
	camera.look_at(Vector3(0, 0.8, -2.5))
	camera.current = true
	var index := 0
	for packed in _scenes.values():
		if not packed: continue
		var visual: Node3D = packed.instantiate()
		viewport.add_child(visual)
		visual.position = Vector3((index % 4 - 1.5) * 2.5, 0, -(index / 4) * 2.5)
		for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
				if not source: continue
				var material := source.duplicate() as BaseMaterial3D
				material.emission_enabled = true
				material.emission = Color.BLACK
				mesh.set_surface_override_material(surface, material)
		index += 1
	var effects: Node3D = load("res://scripts/combat_warmup.gd").populate(viewport, game)
	for frame in 8:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(game) or not is_instance_valid(viewport): return
	# Frost uses a separate skinned shader variant, including each model's vertex
	# layout. Compile it here as well, before special ammunition can hit a horde.
	var frost := ShaderMaterial.new()
	frost.shader = preload("res://shaders/frost_surface.gdshader")
	for child in viewport.get_children():
		if child == effects: continue
		for mesh: MeshInstance3D in child.find_children("*", "MeshInstance3D", true, false):
			mesh.material_overlay = frost
	for frame in 8:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(game) or not is_instance_valid(viewport): return
	# Retain warm resources: freeing the last material can discard its generated
	# shader/pipeline and turn the first real tower/effect into a cold load again.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.process_mode = Node.PROCESS_MODE_DISABLED
	await game.get_tree().process_frame

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

static func is_worm_kind(kind: String) -> bool:
	return bool(TYPES.get(kind, {}).get("worm", false))

static func is_boss_kind(kind: String) -> bool:
	return is_titan_kind(kind) or is_worm_kind(kind)

func targetable() -> bool:
	return alive

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
	_shadow_t = float(appearance_seed % 31) / 62.0
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
			_visual_meshes.append(mi)
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
		if not _hitboxes.is_empty() or not _shot_volumes.is_empty():
			collision_layer = 2
		add_to_group("shot_targets")

# Keep navigation capsules small; bullets use convex volumes fitted to the rig's
# weighted vertices. Bone-space volumes follow walking, attacks and model scaling.
# Prepare the exact same weighted convex volumes during loading, never on a
# model's first combat spawn. Shared immutable shapes preserve hit precision.
static func _prepare_hitbox_shapes(source: Node3D, path: String) -> void:
	for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		if not mesh.skin or mesh.skeleton.is_empty(): continue
		var rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if not rig: continue
		var cache_key := path + ":" + str(source.get_path_to(mesh))
		if _hitbox_shapes.has(cache_key): continue
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
			var bounds := AABB(hull.points[0], Vector3.ZERO)
			var center := Vector3.ZERO
			for point in hull.points:
				bounds = bounds.expand(point)
				center += point
			hull.set_meta("shot_bounds", bounds.grow(0.00001))
			hull.set_meta("shot_center", center / hull.points.size())
			hull.set_meta("shot_hash", var_to_bytes(hull.points).hex_encode().sha256_text())
			shapes[bone] = hull
		_hitbox_shapes[cache_key] = shapes

func _build_hitboxes() -> void:
	_prepare_hitbox_shapes(model, model_path)
	_load_volume_library()
	var library: Dictionary = _volume_library.get_meta("volumes", {}) if _volume_library else {}
	for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if not mesh.skin or mesh.skeleton.is_empty(): continue
		var rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if not rig: continue
		var cache_key := model_path + ":" + str(model.get_path_to(mesh))
		for bone in _hitbox_shapes[cache_key]:
			var hull: ConvexPolygonShape3D = _hitbox_shapes[cache_key][bone]
			var baked: Dictionary = library.get(cache_key, {}).get(bone, {})
			if baked.get("hash", "") == hull.get_meta("shot_hash"):
				var volume := HitVolume.new()
				volume.configure(rig, bone, hull, baked.planes, self)
				_shot_volumes.append(volume)
				continue
			# New or changed meshes retain native precision until their hulls are rebaked.
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

# All ballistic consumers use the same query. World geometry/animals and any
# unbaked hitboxes still use native physics. Baked bones are tested only for
# actors close to the ray, using their current (unthrottled) animation pose.
static func cast_ray(context: Node3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	var hit := context.get_world_3d().direct_space_state.intersect_ray(query)
	if not query.collide_with_areas or not (query.collision_mask & HITBOX_LAYER): return hit
	var endpoint: Vector3 = hit.position if not hit.is_empty() else query.to
	var best_distance := query.from.distance_squared_to(endpoint)
	var candidates: Array = []
	for zombie: Zombie in context.get_tree().get_nodes_in_group("shot_targets"):
		if not zombie.targetable() or zombie.is_queued_for_deletion() or zombie._shot_volumes.is_empty() or query.exclude.has(zombie.get_rid()): continue
		# A conservative model-space envelope includes arms, leaning poses and
		# all rig animations; it follows model offsets, not the movement capsule.
		var transform := zombie.model.global_transform
		if not zombie._shot_has_bounds or transform != zombie._shot_model_transform:
			zombie._shot_model_transform = transform
			zombie._shot_world_bounds = transform * AABB(Vector3(-3, -2, -3), Vector3(6, 7, 6))
			zombie._shot_has_bounds = true
		var bounds := zombie._shot_world_bounds
		var entry: Variant = bounds.intersects_segment(query.from, endpoint)
		if bounds.has_point(query.from): candidates.append([0.0, zombie])
		elif entry != null: candidates.append([query.from.distance_squared_to(entry), zombie])
	# Process the nearest possible hit first. Once it is confirmed, envelopes
	# behind it cannot occlude it and need no per-bone pose/convex tests.
	candidates.sort_custom(func(a: Array, b: Array): return a[0] < b[0])
	for candidate_entry: Array in candidates:
		if float(candidate_entry[0]) > best_distance: break
		var zombie: Zombie = candidate_entry[1]
		for volume in zombie._shot_volumes:
			var candidate: Dictionary = volume.intersect(query.from, endpoint, query.hit_from_inside)
			if candidate.is_empty(): continue
			var distance := query.from.distance_squared_to(candidate.position)
			if distance > best_distance: continue
			best_distance = distance
			hit = candidate
			endpoint = candidate.position
	return hit

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
	if n > 0.0: damage_peers[killer_peer] = true
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
var _pool_complete := false
var _rare_visual_state := -1
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
	if not alive: return
	alive = false
	for hitbox in _hitboxes:
		hitbox.collision_layer = 0
	hit_pending = 0.0
	velocity = Vector3.ZERO
	play("death")
	if not is_boss_kind(net_kind): Sfx.play_at(get_parent(), "zombie_death", global_position, -20.0)
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
		var effect = preload("res://scripts/elemental_effects.gd")
		_rare_particles = effect.particles("fire", minf(height * 0.22, 1.0), height)
		_rare_particles.position.y = height * 0.45
		add_child(_rare_particles)
		_frost_particles = effect.particles("frost", minf(height * 0.26, 1.2), height)
		_frost_particles.position.y = height * 0.5
		add_child(_frost_particles)
		_rare_light = OmniLight3D.new()
		_rare_light.position.y = height * 0.6
		_rare_light.omni_range = minf(height * 1.5, 6.0)
		_rare_light.shadow_enabled = false
		add_child(_rare_light)
		_frost_surface = ShaderMaterial.new()
		_frost_surface.shader = preload("res://shaders/frost_surface.gdshader")
		for mesh in find_children("*", "MeshInstance3D", true, false):
			_frost_meshes.append(mesh)
	if _rare_marker:
		var burning := alive and rare_status.contains("fire")
		var frozen := alive and rare_status.contains("frost")
		var visual_state := int(burning) + int(frozen) * 2
		if visual_state != _rare_visual_state:
			_rare_visual_state = visual_state
			_rare_marker.visible = burning or frozen
			_rare_marker.text = "BRAND + FROST" if burning and frozen else ("BRAND" if burning else "FROST")
			_rare_marker.modulate = Color(1, 0.4, 0.1) if burning else Color(0.3, 0.8, 1)
			_rare_particles.emitting = burning
			_frost_particles.emitting = frozen
			_rare_light.visible = burning or frozen
			_rare_light.light_color = _rare_marker.modulate
			_rare_light.light_energy = 0.45
		if frozen != _frost_visible:
			_frost_visible = frozen
			for mesh in _frost_meshes:
				if is_instance_valid(mesh): mesh.material_overlay = _frost_surface if frozen else null
		if burning: _rare_light.light_energy = 0.7 + sin(Time.get_ticks_msec() * 0.017 + appearance_seed) * 0.2

func _physics_process(delta: float) -> void:
	update_rare_visual()
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0: _set_emission(false)
	if replica:
		global_position = global_position.lerp(net_position, 1.0-exp(-delta*16.0))
		rotation.y = lerp_angle(rotation.y, net_yaw, 1.0-exp(-delta*16.0))
		if not alive and is_instance_valid(_pool) and not _pool_complete:
			dead_t += delta
			var growth := clampf(dead_t / 9.0, 0.0, 1.0)
			var size := 0.4 + 1.5 * (1.0 - pow(1.0 - growth, 2.0))
			_pool.size = Vector3(size, 0.5, size * 0.85)
			_pool.modulate.a = minf(1.0, 0.3 + growth)
			_pool_complete = growth >= 1.0
		return
	if NetSession.enabled:
		var target_player := NetSession.nearest_player(global_position)
		if target_player: player = target_player
	if not alive:
		dead_t += delta
		if _pool and not _pool_complete:
			var g := clampf(dead_t / 9.0, 0.0, 1.0)
			var sz := 0.4 + 1.5 * (1.0 - pow(1.0 - g, 2.0))
			_pool.size = Vector3(sz, 0.5, sz * 0.85)
			_pool.modulate.a = minf(1.0, 0.3 + g)
			_pool_complete = g >= 1.0
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
		if int(near_player) != _shadow_near:
			_shadow_near = int(near_player)
			for mesh in _visual_meshes:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near_player else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_decision_time -= delta
	if _decision_time <= 0.0 or (not is_instance_valid(_decision_target) and _decision_target != null):
		_decision_time = 0.16 + float(appearance_seed % 7) * 0.01
		_decision_target = _choose_defence(p, player_priority)
	var bar: Node3D = _decision_target if is_instance_valid(_decision_target) else null
	if bar and ((bar is Door and bar.is_open) or (not bar is Door and bar.hp <= 0.0)):
		_decision_target = _choose_defence(p, player_priority)
		_decision_time = 0.16 + float(appearance_seed % 7) * 0.01
		bar = _decision_target
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

# Reconsider strategic targets at staggered intervals. Movement, animation,
# hit timing, range checks and damage still run every physics tick.
func _choose_defence(p: Vector3, player_priority: bool) -> Node3D:
	var to_player := player.global_position - p
	to_player.y = 0.0
	# Commit to a breach: steering sideways must not cancel a defence target.
	var bar = null
	var bd := 1e9
	if not hunting and is_instance_valid(siege_target) and siege_target.hp > 0.0:
		bar = siege_target
		bd = bar.attack_point(p).distance_squared_to(p)
	var path := PackedVector3Array()
	for b in barricades:
		if b.hp <= 0.0: continue
		path = _hunt_path if hunting else agent.get_current_navigation_path().slice(agent.get_current_navigation_path_index())
		break
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
	return bar

func begin_hunt() -> void:
	hunting = true
	_decision_time = 0.0
	_decision_target = null
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
			_decision_time = 0.0
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
	# Resting attackers need no repeated capsule sweep over unchanged ground.
	# Refresh contact periodically so a removed platform still makes them fall.
	if is_on_floor() and velocity.length_squared() < 0.000001:
		_rest_contact_time -= get_physics_process_delta_time()
		if _rest_contact_time > 0.0: return
		_rest_contact_time = 0.16 + float(appearance_seed % 7) * 0.01
	else:
		_rest_contact_time = 0.0
	if _move_on_terrain(): return
	move_and_slide()
	_terrain_floor = RID()
	if is_on_floor():
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			var collider := collision.get_collider() as Node
			if collider and collider.is_in_group("terrain_ground") and collision.get_normal().y > 0.9:
				_terrain_floor = collision.get_collider_rid()
				break

# On the open heightfield, ground rays plus a swept capsule against every
# other obstacle avoids repeated floor-recovery sweeps. Walls, actors, gates,
# steep slopes, steps, platforms, falling and knockback keep the native solver.
# This changes no simulation rate, rendering setting or obstacle collision.
func _move_on_terrain() -> bool:
	if not _terrain_floor.is_valid() or not is_on_floor() or not (collision_mask & 1) or height > 5.0 or velocity.y > 0.01: return false
	var delta := get_physics_process_delta_time()
	var travel := Vector3(velocity.x, 0, velocity.z) * delta
	var destination := global_position + travel
	if not _ground_ray:
		_ground_ray = PhysicsRayQueryParameters3D.new()
		_ground_ray.collision_mask = 1 | 8
		_ground_ray.exclude = [get_rid()]
		_ground_motion = PhysicsTestMotionParameters3D.new()
		_ground_motion.margin = safe_margin
		_ground_motion.recovery_as_collision = true
	_ground_ray.from = destination + Vector3.UP * 0.4
	_ground_ray.to = destination - Vector3.UP * 0.5
	var ground := get_world_3d().direct_space_state.intersect_ray(_ground_ray)
	if ground.is_empty() or ground.rid != _terrain_floor or ground.normal.y < 0.9: return false
	# Match CharacterBody's default uphill projection; downhill uses floor snap.
	# Re-sample after projection, including a possible triangle/crest transition.
	if travel.dot(ground.normal) < 0.0:
		destination = global_position + travel.slide(ground.normal)
		_ground_ray.from = destination + Vector3.UP * 0.4
		_ground_ray.to = destination - Vector3.UP * 0.5
		ground = get_world_3d().direct_space_state.intersect_ray(_ground_ray)
		if ground.is_empty() or ground.rid != _terrain_floor or ground.normal.y < 0.9: return false
	# Analytic support height of the capsule's lower hemisphere on this plane.
	destination.y = ground.position.y + 0.35 * (1.0 / ground.normal.y - 1.0) + safe_margin
	if absf(destination.y - global_position.y) > 0.15: return false
	_ground_motion.from = global_transform
	_ground_motion.motion = destination - global_position
	_ground_motion.exclude_bodies = [_terrain_floor]
	if PhysicsServer3D.body_test_motion(get_rid(), _ground_motion): return false
	global_position = destination
	velocity.y = 0.0
	return true

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

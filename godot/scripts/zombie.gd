# Zombie: navmesh pathing to the player, attacks player or a blocking barricade, plays GLB clips.
class_name Zombie
extends CharacterBody3D

# "skins": every GLB in assets/models that may stand in for the type, one is picked per zombie (missing files
# are skipped, "model" / "fallback" remain the default). The field titan is taller than the beeches (22-29 m)
# and handled by titan.gd (ground strike, no stagger, always casts shadows).
const TYPES := {
	"earthworm": {"name": "THE EARTHWORM", "model": "zombie_earthworm", "hp": 2600.0, "speed": 8.0, "damage": 48.0, "reach": 9.0, "attack_time": 3.0, "score": 300, "height": 14.0, "worm": true, "tint": Color.WHITE},
	"earthworm_ancient": {"name": "THE GRAVE WYRM", "model": "zombie_earthworm_ancient", "hp": 3800.0, "speed": 7.0, "damage": 62.0, "reach": 11.0, "attack_time": 3.4, "score": 420, "height": 19.0, "worm": true, "tint": Color.WHITE},
	"titan_hunter": {"name": "HUNTER TITAN", "model": "zombie_colossus", "hp": 1700.0, "speed": 6.0, "damage": 45.0, "reach": 8.0, "attack_time": 3.0, "score": 230, "height": 8.0, "tint": Color(0.58, 0.83, 0.65), "giant": true, "blast_radius": 4.0, "windup": 1.7, "recovery": 1.1, "structure_mul": 0.65, "warning_color": Color(0.45, 1.0, 0.3)},
	"titan_siege": {"name": "SIEGE TITAN", "model": "zombie_bloater", "hp": 3600.0, "speed": 2.6, "damage": 80.0, "reach": 10.0, "attack_time": 4.5, "score": 350, "height": 14.0, "tint": Color(0.7, 0.66, 0.51), "giant": true, "blast_radius": 6.0, "windup": 2.8, "recovery": 2.0, "structure_mul": 1.6, "warning_color": Color(1.0, 0.68, 0.1)},
	"titan_ash": {"name": "ASH TITAN", "model": "zombie_titan", "hp": 3000.0, "speed": 3.6, "damage": 60.0, "reach": 13.0, "attack_time": 4.5, "score": 320, "height": 19.0, "tint": Color(0.68, 0.46, 0.42), "giant": true, "blast_radius": 10.0, "windup": 3.2, "recovery": 2.0, "structure_mul": 1.0, "warning_color": Color(1.0, 0.25, 0.15)},
	"titan": {"model": "zombie_titan", "skins": ["zombie_titan", "zombie_colossus"], "fallback": "zombie_bloater", "hp": 4200.0, "speed": 4.2, "damage": 70.0, "reach": 14.0, "attack_time": 4.0, "score": 400, "height": 27.0, "tint": Color(0.78, 0.8, 0.78), "giant": true},
	"forest_spirit": {"name": "THE FOREST SPIRIT", "model": "zombie_forest_spirit", "hp": 1650.0, "speed": 3.0, "damage": 24.0, "reach": 2.5, "attack_time": 1.8, "score": 220, "height": 3.4, "boss": true, "tint": Color.WHITE},
	"shambler": { "model": "zombie_shambler", "skins": ["zombie_shambler", "zombie_farmer", "zombie_hiker", "zombie_grandma"], "hp": 120.0, "speed": 1.75, "damage": 15.0, "reach": 1.6, "attack_time": 1.0, "score": 10, "height": 1.8 },
	"runner": { "model": "zombie_runner", "skins": ["zombie_runner", "zombie_jogger"], "hp": 75.0, "speed": 4.6, "damage": 11.0, "reach": 1.4, "attack_time": 0.6, "score": 15, "height": 1.7 },
	"brute":    { "model": "zombie_bloater", "fallback": "zombie_shambler", "hp": 420.0, "speed": 1.35, "damage": 34.0, "reach": 2.0, "attack_time": 1.5, "score": 40, "height": 2.3, "tint": Color(0.9, 0.85, 0.6) },
	"nurse":    { "model": "zombie_nurse", "fallback": "zombie_runner", "hp": 95.0, "speed": 2.9, "damage": 13.0, "reach": 1.5, "attack_time": 0.85, "score": 15, "height": 1.7 },
	"soldier":  { "model": "zombie_soldier", "skins": ["zombie_soldier", "zombie_forester"], "fallback": "zombie_shambler", "hp": 230.0, "speed": 2.1, "damage": 21.0, "reach": 1.6, "attack_time": 0.95, "score": 25, "height": 1.85 },
	# 26 Sep 2026, the special infected. "ranged": the spitter lobs acid at gates, the hut and players from
	# min..range metres (acid_pool seconds of structure damage per second). "screamer": on sight it calls the
	# horde: every zombie within call_radius hunts the marked player, "call" runners join the wave, the player
	# is marked on every minimap for "mark" seconds. "stalker": spawns only in the maize (weather / night) and
	# is invisible unless a flashlight beam is on it. "beast": rig-less Meshy animals moved by zombie_beast.gd
	# (the dog lunges, the stag charges and rams).
	"spitter":  { "name": "SPITTER", "model": "zombie_spitter", "fallback": "zombie_bloater", "hp": 260.0, "speed": 1.5, "damage": 14.0, "reach": 1.8, "attack_time": 1.4, "score": 35, "height": 2.15,
		"ranged": {"range": 17.0, "min": 5.0, "cooldown": 4.2, "damage": 22.0, "structure": 95.0, "acid": 6.5, "speed": 15.0} },
	"screamer": { "name": "SCREAMER", "model": "zombie_screamer", "fallback": "zombie_nurse", "hp": 150.0, "speed": 2.7, "damage": 12.0, "reach": 1.5, "attack_time": 0.9, "score": 45, "height": 1.72,
		"screamer": {"range": 24.0, "cooldown": 22.0, "call": 3, "mark": 12.0, "call_radius": 70.0} },
	"stalker":  { "name": "STALKER", "model": "zombie_stalker", "fallback": "zombie_jogger", "hp": 110.0, "speed": 3.4, "damage": 19.0, "reach": 1.5, "attack_time": 0.8, "score": 40, "height": 1.72, "stalker": true },
	"zombie_dog": { "name": "FARM DOG", "model": "zombie_dog", "hp": 65.0, "speed": 7.2, "damage": 12.0, "reach": 1.5, "attack_time": 0.7, "score": 20, "height": 0.8,
		"beast": {"length": 1.35, "lunge": 0.5} },
	"zombie_stag": { "name": "ZOMBIE STAG", "model": "zombie_stag", "fallback": "stag", "hp": 400.0, "speed": 5.0, "damage": 24.0, "reach": 2.2, "attack_time": 2.2, "score": 70, "height": 1.75,
		"beast": {"length": 2.5, "charge": 11.5, "ram": 34.0, "ram_structure": 110.0, "charge_range": 28.0, "cooldown": 6.0} },
}
# blood moon (day_night_cycle.gd): every zombie walks this much faster while the red moon is up
static var horde_pace := 1.0
# the helmet of an armored zombie (waves >= 10): headshots ring off it until it is shot away
const HELMET_HP := 70.0
const HELMET_SHARE := 0.2          # share of a deflected headshot that still reaches the body
static var _helmet_scene: PackedScene
static var _helmet_material: StandardMaterial3D
static var _helmet_loaded := false

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
# A swing is held for its follow-through and a flinch for HIT_HOLD before the gait resumes; cutting
# them at the strike snapped the arms back into the walk every attack and every hit (visible twitching).
const HIT_HOLD := 0.45
var _hit_t := 0.0
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
var armored := false               # host decision before add_child: carries a helmet (see HELMET_HP)
var helmet_hp := 0.0
var _helmet: Node3D
var _helmet_gone := false
var cloak := 1.0                   # stalkers: 1 fully visible .. 0.07 a shimmer (see _update_cloak)
var _reveal_t := 0.0               # lightning: cold white glow for a moment (weather.gd)
var _spit_pending := 0.0
var _spit_target := Vector3.INF
var _call_t := 0.0                 # screamer: seconds until it may call the horde again
var calls := 0                     # screamer: horde calls so far (tests, statistics)
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
static var _clip_info := {}          # model path -> {clip: {length, speed, peak}}, measured once by preload_models
static var force_skin := ""          # tests: every new zombie uses this model while it is set (and exists)
# Animation layer. "state" stays the logical state (walk / attack / death / hit / idle / scream) that the AI,
# the tests and the co-op snapshot use; "clip" is the concrete clip of this zombie's rig: its own gait (walk,
# walk2 or run), alternating swings (attack / attack2), a random fall (death .. death3), a flinch (hit / hit2).
# Older rigs with only walk / attack / death keep working: the missing clips fall back to the gait.
var clip := ""
var _locomotion := "walk"
var _anim_last_pos := Vector3.ZERO
var _ground_speed := 0.0            # smoothed horizontal speed from the real displacement (host and replica alike)
var _stand_t := 0.0
var _anim_lod := 1                  # 1 = every frame, 2 / 3 = distant actors advance their rig every 2nd / 3rd tick
var _anim_accum := 0.0
var _anim_tick := 0
var _swing := 0
var _scream_t := 0.0
var _screamed := false
const ANIM_LOD_NEAR := 45.0
const ANIM_LOD_FAR := 90.0
const SCREAM_RANGE := 14.0
const SCREAM_CHANCE := 35           # percent of the common zombies that stop once to scream at the player
# Head tracking: within HEAD_LOOK_RANGE the head bone turns towards the player on top of the clip (a
# LookAtModifier3D on the rig), fading out beyond it and while falling. "--no-headlook" disables it.
var _head_look: LookAtModifier3D
var _head_look_target: Node3D
const HEAD_LOOK_RANGE := 12.0
const LOD_BIAS := 0.6
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

static func preload_models(host: Node = null) -> void:
	_load_volume_library()
	for spec: Dictionary in TYPES.values():
		for name in skin_names(spec):
			var path := "res://assets/models/%s.glb" % name
			if not _scenes.has(path):
				_scenes[path] = load(path) if ResourceLoader.exists(path) else null
				if _scenes[path]:
					_scenes[path] = preload("res://scripts/zombie_animation.gd").prepare(_scenes[path], host)
					var source: Node3D = _scenes[path].instantiate()
					if not bool(spec.get("boss", false)): _prepare_hitbox_shapes(source, path)
					if not bool(spec.get("giant", false)) and not bool(spec.get("worm", false)) and not bool(spec.get("boss", false)): ZombieGore.prepare(source, path)
					source.free()
			if _scenes[path] and not _clip_info.has(path):
				_clip_info[path] = preload("res://scripts/zombie_animation.gd").measure(_scenes[path], host)

# Clip metrics of a model (see zombie_animation.measure); measured on demand for models outside TYPES.
static func clip_info(path: String) -> Dictionary:
	if not _clip_info.has(path):
		var scene: PackedScene = _scenes.get(path)
		_clip_info[path] = preload("res://scripts/zombie_animation.gd").measure(scene) if scene else {}
	return _clip_info[path]

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
	return is_titan_kind(kind) or is_worm_kind(kind) or bool(TYPES.get(kind, {}).get("boss", false))

static func is_beast_kind(kind: String) -> bool:
	return TYPES.get(kind, {}).has("beast")

static func is_stalker_kind(kind: String) -> bool:
	return bool(TYPES.get(kind, {}).get("stalker", false))

# common humanoids that may wear the helmet of the mutation (never bosses, beasts or the stalker)
static func can_be_armored(kind: String) -> bool:
	return kind in ["shambler", "soldier", "brute", "spitter", "nurse"]

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
			for n in anim.get_animation_list():
				var gait := n.begins_with("walk") or n.begins_with("run") or n.begins_with("idle")
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR if gait else Animation.LOOP_NONE
			_locomotion = _pick_locomotion(appearance)
			anim.speed_scale = 1.0
			state = ""
			play("walk")
		# slight per-body variation of the decayed skin; the PBR textures carry the real colour now
		var tint: Color = type.get("tint", Color.from_hsv(appearance.randf_range(0.02, 0.09), appearance.randf_range(0.0, 0.1), appearance.randf_range(0.82, 1.0)))
		# The 50k-triangle rigs carry Godot's imported LODs; drop to the coarser ones a little earlier than the
		# scenery does (a horde of 60 at 15-25 m is the case that matters), giants stay at full detail.
		var lod_bias := LOD_BIAS if not bool(type.get("giant", false)) else 1.0
		for flag in OS.get_cmdline_user_args():
			if flag.begins_with("--zombie-lod-bias="): lod_bias = float(flag.get_slice("=", 1))
		for m in model.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			_visual_meshes.append(mi)
			mi.lod_bias = lod_bias
			var overrides := []
			for i in mi.mesh.get_surface_count():
				var mat: Material = mi.mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					var dup: BaseMaterial3D = mat.duplicate()
					dup.albedo_color = dup.albedo_color * tint
					dup.emission_enabled = true
					dup.emission = Color.BLACK
					dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					if bool(type.get("stalker", false)):
						dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
						dup.albedo_color.a = 0.07
					mi.set_surface_override_material(i, dup)
					_materials.append(dup)
					overrides.append(dup)
				else:
					overrides.append(null)
			_gore_overrides[mi] = overrides
	var scale_var := appearance.randf_range(0.94, 1.08)
	if model:
		model.scale *= scale_var
		_build_hitboxes()
		# the cut into body and parts comes after the hit shapes: they are keyed on the original mesh node
		if not is_boss_kind(net_kind) and not "--no-gore" in OS.get_cmdline_user_args():
			ZombieGore.prepare(model, model_path)
			_gore_parts = ZombieGore.attach(model, model_path, _gore_overrides)
			for part in _gore_parts.values(): _visual_meshes.append(part)
		if not _hitboxes.is_empty() or not _shot_volumes.is_empty():
			collision_layer = 2
		add_to_group("shot_targets")
		_build_head_look()
		if armored: _build_helmet()
		if bool(type.get("stalker", false)): cloak = 0.07
	_anim_last_pos = global_position
	agent.max_speed = float(type["speed"]) * speed_mul * 1.45   # headroom for the blood moon pace

func _build_head_look() -> void:
	if bool(type.get("giant", false)) or bool(type.get("worm", false)) or "--no-headlook" in OS.get_cmdline_user_args(): return
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not rig or rig.find_bone("Head") < 0: return
	_head_look = LookAtModifier3D.new()
	_head_look.bone_name = "Head"
	# The rig faces +Z and stands along +Y; read the head bone's own axes off its rest pose instead of
	# assuming a convention (Meshy heads are tilted about 27 degrees in rest).
	var rest := rig.get_bone_global_rest(rig.find_bone("Head")).basis
	_head_look.forward_axis = _closest_bone_axis(rest, Vector3(0, 0, 1))
	_head_look.primary_rotation_axis = _closest_unsigned_axis(rest, Vector3.UP)
	_head_look.use_secondary_rotation = true
	_head_look.use_angle_limitation = true
	_head_look.symmetry_limitation = true
	_head_look.primary_limit_angle = deg_to_rad(110.0)
	_head_look.primary_damp_threshold = 0.6
	_head_look.secondary_limit_angle = deg_to_rad(50.0)
	_head_look.secondary_damp_threshold = 0.6
	_head_look.duration = 0.4
	_head_look.transition_type = Tween.TRANS_SINE
	_head_look.ease_type = Tween.EASE_IN_OUT
	_head_look.influence = 0.0
	rig.add_child(_head_look)

# The signed bone axis (rest pose, skeleton space) that points most along a direction.
static func _closest_bone_axis(rest: Basis, direction: Vector3) -> SkeletonModifier3D.BoneAxis:
	var candidates := [[SkeletonModifier3D.BONE_AXIS_PLUS_X, rest.x], [SkeletonModifier3D.BONE_AXIS_MINUS_X, -rest.x],
		[SkeletonModifier3D.BONE_AXIS_PLUS_Y, rest.y], [SkeletonModifier3D.BONE_AXIS_MINUS_Y, -rest.y],
		[SkeletonModifier3D.BONE_AXIS_PLUS_Z, rest.z], [SkeletonModifier3D.BONE_AXIS_MINUS_Z, -rest.z]]
	var best: SkeletonModifier3D.BoneAxis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	var best_dot := -INF
	for candidate in candidates:
		var d: float = (candidate[1] as Vector3).normalized().dot(direction)
		if d > best_dot:
			best_dot = d
			best = candidate[0]
	return best

static func _closest_unsigned_axis(rest: Basis, direction: Vector3) -> Vector3.Axis:
	var dots := [absf(rest.x.normalized().dot(direction)), absf(rest.y.normalized().dot(direction)), absf(rest.z.normalized().dot(direction))]
	var best := Vector3.AXIS_Y
	if dots[0] >= dots[1] and dots[0] >= dots[2]: best = Vector3.AXIS_X
	elif dots[2] > dots[1]: best = Vector3.AXIS_Z
	return best

# Fade the head tracking with the distance to the player it hunts; off while falling, screaming or frozen.
func _update_head_look(delta: float) -> void:
	if not _head_look: return
	var want := 0.0
	if alive and is_instance_valid(player) and state != "scream" and frost_mul > 0.0:
		if _head_look_target != player:
			_head_look_target = player
			# the player's origin is at the feet: look at the head (camera pivot) when there is one
			var focus: Node3D = player.head if "head" in player and player.head is Node3D else player
			_head_look.target_node = _head_look.get_path_to(focus)
		var d := global_position.distance_to(player.global_position)
		want = clampf((HEAD_LOOK_RANGE - d) / 4.0, 0.0, 1.0) * 0.85
	_head_look.influence = lerpf(_head_look.influence, want, 1.0 - exp(-delta * 6.0))
	_head_look.active = _head_look.influence > 0.01

# ---------------------------------------------------------------- the mutation: a steel helmet
static func _load_helmet() -> void:
	if _helmet_loaded: return
	_helmet_loaded = true
	var path := "res://assets/models/zombie_helmet.glb"
	_helmet_scene = load(path) if ResourceLoader.exists(path) else null
	_helmet_material = StandardMaterial3D.new()
	_helmet_material.albedo_color = Color(0.3, 0.32, 0.3)
	_helmet_material.metallic = 0.8
	_helmet_material.roughness = 0.55

# The helmet hangs on the Head bone through a BoneAttachment3D. Bone space is centimetres times the model
# scale, so every size is divided by the rig's world scale; the bone's own axes are read off its rest pose
# (Meshy heads sit tilted), the helmet's dome points along the bone axis that is world-up in rest.
func _build_helmet() -> void:
	if not model: return
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not rig: return
	var head := rig.find_bone("Head")
	if head < 0: return
	_load_helmet()
	helmet_hp = HELMET_HP
	var attachment := BoneAttachment3D.new()
	attachment.name = "Helmet"
	attachment.bone_name = rig.get_bone_name(head)
	rig.add_child(attachment)
	_helmet = attachment
	var world_scale: float = maxf(rig.global_transform.basis.get_scale().y, 0.0001)
	var unit := 1.0 / world_scale                      # bone-space units per metre
	var rest := rig.get_bone_global_rest(head).basis
	var inverse := rest.inverse()
	var up := (inverse * Vector3.UP).normalized()
	var forward := (inverse * Vector3.FORWARD * -1.0).normalized()   # the rig faces +Z
	var frame := Basis()
	frame.y = up
	frame.z = forward
	frame.x = up.cross(forward).normalized()
	frame.z = frame.x.cross(up).normalized()
	frame = frame.orthonormalized()
	var holder := Node3D.new()
	holder.transform = Transform3D(frame, up * 0.115 * unit)
	attachment.add_child(holder)
	var visual: Node3D
	if _helmet_scene:
		visual = _helmet_scene.instantiate()
		var bounds := Barricade._bounds(visual)
		var longest := maxf(maxf(bounds.size.x, bounds.size.z), 0.001)
		var fit := 0.31 * unit / longest
		visual.scale = Vector3.ONE * fit
		visual.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * fit
		for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.mesh.get_surface_count():
				var source := mesh.mesh.surface_get_material(i) as BaseMaterial3D
				if source:
					var dark := source.duplicate() as BaseMaterial3D
					dark.albedo_color = Color(0.55, 0.58, 0.5)
					dark.metallic = 0.6
					dark.roughness = 0.6
					mesh.set_surface_override_material(i, dark)
	else:
		visual = Node3D.new()
		var dome := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.14 * unit
		sphere.height = 0.2 * unit
		dome.mesh = sphere
		dome.scale = Vector3(1.0, 0.85, 1.1)
		dome.material_override = _helmet_material
		visual.add_child(dome)
		var brim := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.13 * unit
		ring.outer_radius = 0.165 * unit
		brim.mesh = ring
		brim.position.y = -0.05 * unit
		brim.material_override = _helmet_material
		visual.add_child(brim)
	holder.add_child(visual)

# A headshot on a helmeted zombie: the helmet takes the hit, the body only HELMET_SHARE of it, no headshot
# bonus. The last hit knocks the helmet off (a tumbling chunk), after that heads pop as usual.
func hit_helmet(damage: float, dir: Vector3) -> float:
	if helmet_hp <= 0.0: return damage
	helmet_hp -= damage
	Sfx.play_at(get_parent(), "helmet_ping", global_position + Vector3.UP * height * 0.9, -6.0, randf_range(0.9, 1.15), 5.0, 50.0)
	if helmet_hp <= 0.0:
		helmet_hp = 0.0
		drop_helmet(dir)
	return damage * HELMET_SHARE

func drop_helmet(dir: Vector3) -> void:
	if _helmet_gone: return
	_helmet_gone = true
	helmet_hp = 0.0
	if not is_instance_valid(_helmet): return
	var holder := _helmet.get_child(0) if _helmet.get_child_count() > 0 else null
	var origin := _helmet.global_position
	if holder:
		var chunk := RigidBody3D.new()
		chunk.collision_layer = 0
		chunk.collision_mask = 1 | 8
		chunk.mass = 1.2
		chunk.angular_damp = 1.0
		var shape := CollisionShape3D.new()
		var ball := SphereShape3D.new()
		ball.radius = 0.15
		shape.shape = ball
		chunk.add_child(shape)
		var visual := Node3D.new()
		chunk.add_child(visual)
		# the helmet's own scale is bone space: rebuild it at world size on the chunk
		var world_scale: float = maxf(_helmet.global_transform.basis.get_scale().y, 0.0001)
		_helmet.remove_child(holder)
		visual.add_child(holder)
		holder.transform = Transform3D(holder.basis.orthonormalized().scaled(Vector3.ONE * world_scale), Vector3.ZERO)
		holder.scale = Vector3.ONE * world_scale
		holder.position = Vector3.ZERO
		get_parent().add_child(chunk)
		chunk.global_position = origin + Vector3.UP * 0.1
		var push := (Vector3(dir.x, 0.0, dir.z).normalized() if dir.length() > 0.01 else Vector3.UP) * randf_range(2.0, 3.5) + Vector3.UP * randf_range(2.5, 4.0)
		chunk.linear_velocity = push
		chunk.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		var cleanup := get_tree().create_timer(12.0)
		cleanup.timeout.connect(func(): if is_instance_valid(chunk): chunk.queue_free())
	_helmet.queue_free()
	_helmet = null

# replicas: the host's helmet state (snapshot fields 15 / 16)
func apply_helmet(hp: float, has_armor: bool) -> void:
	if has_armor and not armored:
		armored = true
		if model and not _helmet and hp > 0.0: _build_helmet()
	helmet_hp = hp
	if armored and hp <= 0.0 and not _helmet_gone: drop_helmet(Vector3.UP)

# ---------------------------------------------------------------- the stalker's cloak
# Nearly invisible unless a flashlight beam (anyone's) is on it, it is swinging, it was just hit, lightning
# lights the forest or it is dead. Runs on host and replicas alike from what each peer can see.
const CLOAK_HIDDEN := 0.07
const CLOAK_RANGE := 30.0

func _lit_by_flashlight() -> bool:
	var actors: Array = NetSession.world.actors.values() if NetSession.enabled and NetSession.world else [player]
	var centre := global_position + Vector3.UP * height * 0.5
	for actor in actors:
		if not is_instance_valid(actor) or not (actor is Player) or not actor.flashlight or not actor.flashlight.visible: continue
		var light: SpotLight3D = actor.flashlight
		if not light.is_inside_tree(): continue
		var to := centre - light.global_position
		var d := to.length()
		if d > CLOAK_RANGE or d < 0.01: continue
		var cosine := (-light.global_basis.z).normalized().dot(to / d)
		if cosine >= cos(deg_to_rad(light.spot_angle) * 0.85 + 0.03): return true
	return false

func _update_cloak(delta: float) -> void:
	var lit := not alive or state == "attack" or _flash_t > 0.0 or _reveal_t > 0.0 or _lit_by_flashlight()
	var target := 1.0 if lit else CLOAK_HIDDEN
	cloak = move_toward(cloak, target, delta * (5.0 if lit else 1.2))
	for material in _materials:
		material.albedo_color.a = cloak
	var shadows := cloak > 0.5
	if shadows != _cloak_shadows:
		_cloak_shadows = shadows
		for mesh in _visual_meshes:
			if is_instance_valid(mesh): mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
var _cloak_shadows := true

func visible_on_map() -> bool:
	return not bool(type.get("stalker", false)) or cloak > 0.5

# A lightning strike (weather.gd): the body glows cold white for a moment, so the whole horde stands out.
func lightning_reveal(seconds: float) -> void:
	_reveal_t = maxf(_reveal_t, seconds)
	for material in _materials:
		material.emission = Color(0.62, 0.72, 0.95)

# The gait this body walks with: runners take the run clip, everyone else one of the walk variants.
func _pick_locomotion(rng: RandomNumberGenerator) -> String:
	if not anim: return "walk"
	if float(type["speed"]) * speed_mul >= 2.4 and anim.has_animation("run"):
		return "run"
	# Only walks whose own pace is within 0.55-2x of this body's speed: an elderly shuffle played at three
	# times its pace looks like a film run fast, not like a zombie.
	var gaits: Array[String] = []
	var fitting: Array[String] = []
	var pace := float(type["speed"]) * speed_mul
	for n in ["walk", "walk2", "walk3"]:
		if not anim.has_animation(n): continue
		gaits.append(n)
		var natural := _natural_speed(n)
		if natural <= 0.0 or (pace / natural >= 0.55 and pace / natural <= 2.0): fitting.append(n)
	if gaits.is_empty(): return "walk"
	if not fitting.is_empty(): gaits = fitting
	return gaits[rng.randi() % gaits.size()]

# The gait for the current pace: a slowed runner (frost) drops to its walk clip instead of a slow-motion sprint.
func _gait() -> String:
	if _locomotion == "run" and _ground_speed < 1.9 and anim and anim.has_animation("walk") and alive and clip == "run":
		return "walk"
	if _locomotion == "run" and clip == "walk" and _ground_speed < 2.3: return "walk"
	return _locomotion

# The concrete clip of this rig for a logical state; "" when the rig has no clip for it.
func _variant(name: String) -> String:
	if not anim: return ""
	var options: Array[String] = []
	match name:
		"walk":
			return _gait() if anim.has_animation(_gait()) else ("walk" if anim.has_animation("walk") else "")
		"attack":
			for n in ["attack", "attack2", "attack3"]:
				if anim.has_animation(n): options.append(n)
			if options.is_empty(): return ""
			_swing += 1
			return options[(_swing + appearance_seed) % options.size()]
		"death":
			return _death_clip()
		"hit":
			for n in ["hit", "hit2"]:
				if anim.has_animation(n): options.append(n)
			return "" if options.is_empty() else options[randi() % options.size()]
	return name if anim.has_animation(name) else ""

# The fall follows the shot (25 Sep 2026). Every rig carries Meshy library deaths: 184 falls forward (hips
# travel +Z, the rig's front), 189 crumples backward, 185 sinks slowly backward, 188 folds over a belly
# wound, and 183 is the stiff plank drop with the arms spread the whole way down - that one is never
# picked (PLANK_SPREAD: hands wider than this many shoulder widths 40 % into the fall). The metrics come
# from zombie_animation.measure at load (clip_info), never from seeking the live rig: that left the first
# body of every model lying flat before its fall even started.
const PLANK_SPREAD := 14.5
const CRUMPLE_SPREAD := 8.0
var _death_dir := Vector3.ZERO

static func is_plank(info: Dictionary) -> bool:
	return float(info.get("spread_mid", 0.0)) > PLANK_SPREAD

# 188 folds over a belly wound with the arms held in: believable from any side, so it joins both sets
static func is_crumple(info: Dictionary) -> bool:
	return float(info.get("spread_end", 99.0)) < CRUMPLE_SPREAD and float(info.get("spread_mid", 99.0)) < CRUMPLE_SPREAD

func _death_clip() -> String:
	var options: Array[String] = []
	for n in anim.get_animation_list():
		if n.begins_with("death"): options.append(n)
	if options.is_empty(): return ""
	var info := clip_info(model_path)
	var local := Vector3.ZERO
	if model and _death_dir.length() > 0.01:
		local = model.global_basis.inverse() * _death_dir
	# only a shot clearly from behind (the bullet travelling along the rig's front) drops the body onto its
	# face; everything else, including a shot with no direction, goes onto the back or folds over
	var forward := local.z > 0.35
	var backward := not forward
	var matching: Array[String] = []
	var natural: Array[String] = []
	for n in options:
		var m: Dictionary = info.get(n, {})
		if m.is_empty() or is_plank(m): continue
		natural.append(n)
		var falls_forward: bool = float(m.get("travel_z", 0.0)) > 0.0
		if not is_crumple(m) and ((forward and not falls_forward) or (backward and falls_forward)): continue
		matching.append(n)
	if not matching.is_empty(): return matching[randi() % matching.size()]
	if not natural.is_empty(): return natural[randi() % natural.size()]
	return options[randi() % options.size()]

# Seconds into a clip at which its strike lands (measured), or a guess for unmeasured rigs.
func _peak(name: String) -> float:
	var info: Dictionary = clip_info(model_path).get(name, {})
	return float(info.get("peak", 0.6)) if not info.is_empty() else 0.6

# Ground speed a gait clip was made for, in world metres per second for this body's scale.
func _natural_speed(name: String) -> float:
	var info: Dictionary = clip_info(model_path).get(name, {})
	if info.is_empty() or not model: return 0.0
	return float(info.get("speed", 0.0)) * model.scale.y

# Per tick: stride matching, idle when standing, gait switch and the animation LOD of distant actors.
func _update_animation(delta: float) -> void:
	if not anim or not model: return
	var p := global_position
	var moved := Vector2(p.x - _anim_last_pos.x, p.z - _anim_last_pos.z).length() / maxf(delta, 0.001)
	_anim_last_pos = p
	if moved > 40.0: moved = 0.0     # spawn placement or teleport, not a stride
	_ground_speed = lerpf(_ground_speed, moved, 1.0 - exp(-delta * 10.0))
	_update_head_look(delta)
	# distant rigs: skinning stays on the GPU every frame, the pose only changes every 2nd / 3rd tick
	var lod := 1
	if is_instance_valid(player) and not bool(type.get("giant", false)) and alive:
		var d2 := p.distance_squared_to(player.global_position)
		lod = 1 if d2 < ANIM_LOD_NEAR * ANIM_LOD_NEAR else (2 if d2 < ANIM_LOD_FAR * ANIM_LOD_FAR else 3)
	if lod != _anim_lod:
		_anim_lod = lod
		_anim_accum = 0.0
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE if lod == 1 else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if _anim_lod > 1:
		_anim_accum += delta
		_anim_tick += 1
		if _anim_tick % _anim_lod == 0 and anim.active:
			anim.advance(_anim_accum)
			_anim_accum = 0.0
	if not alive or state != "walk": return
	if _ground_speed < 0.12:
		_stand_t += delta
		if _stand_t > 0.35 and clip != "idle" and anim.has_animation("idle"):
			clip = "idle"
			anim.play("idle", 0.3)
			anim.speed_scale = 0.9 + float(appearance_seed % 5) * 0.05
			return
	else:
		_stand_t = 0.0
	if clip == "idle" and _ground_speed >= 0.3:
		clip = _variant("walk")
		anim.play(clip, 0.25)
	elif clip != "idle":
		var gait := _variant("walk")
		if gait != "" and gait != clip:
			clip = gait
			anim.play(clip, 0.3)
	if clip != "idle":
		var natural := _natural_speed(clip)
		var target := clampf(_ground_speed / natural, 0.35, 2.4) if natural > 0.05 else 1.0
		anim.speed_scale = lerpf(anim.speed_scale, target, 1.0 - exp(-delta * 8.0))

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
	if state == name and name != "attack" and name != "hit":
		return
	var previous := state
	state = name
	if not anim: return
	var target := _variant(name)
	if target == "":
		# older rigs without this clip: a flinch, scream or idle just stands in its gait
		if name in ["idle", "hit", "scream"]:
			target = _variant("walk")
			if target == "" or clip == target: return
		elif not anim.has_animation(name):
			return
		else:
			target = name
	clip = target
	_stand_t = 0.0
	match name:
		"attack":
			anim.play(target, 0.08)
			# the strike of the swing lands on the damage tick (hit_pending, 0.35 s after the call; a titan's
			# slam on the end of its wind-up)
			var lead := attack_lead()
			var speed := clampf(_peak(target) / lead, 0.15, 2.4)
			if _peak(target) / speed > lead + 0.05:
				anim.seek(_peak(target) - lead * speed, false)
			anim.speed_scale = speed
		"hit":
			anim.play(target, 0.06)
			anim.speed_scale = 1.4
			_hit_t = HIT_HOLD
		"scream":
			anim.play(target, 0.12)
			anim.speed_scale = 1.0 if bool(type.get("giant", false)) else 1.25
		"death":
			anim.play(target, 0.15)
			anim.speed_scale = 1.0
		_:
			# back from a swing or flinch the arms travel a long way: blend it, do not snap
			anim.play(target, (0.3 if previous in ["attack", "hit", "scream"] else 0.2) if name == "walk" else 0.25)
			if name != "walk": anim.speed_scale = 1.0

# Length of the clip behind a logical state at its playback speed (0 when the rig has none).
func clip_seconds(name: String) -> float:
	if not anim or clip == "" or not anim.has_animation(clip) or state != name: return 0.0
	return anim.get_animation(clip).length / maxf(anim.speed_scale, 0.01)

func damage(n: float, dir: Vector3) -> void:
	if replica or NetSession.is_client(): return
	if not alive:
		return
	if n > 0.0: damage_peers[killer_peer] = true
	hp -= n
	Sfx.play_at(get_parent(), "hit", global_position, -6.0)
	_flash()
	if hp > 0.0: _record_limb_hit(n, dir)
	else: last_hit_bone = ""
	# flinch: short stagger with knockback along the shot direction, scaled by the hit (heavier for big calibres)
	var k := clampf(n / 60.0, 0.3, 1.5)
	_stagger = maxf(_stagger, 0.16 + 0.14 * k)
	_stagger_len = _stagger
	_knock = Vector3(dir.x, 0.0, dir.z).normalized() * (1.4 + 1.6 * k) / type["hp"] * 100.0
	_knock = _knock.limit_length(3.2)
	attack_t = maxf(attack_t, 0.25)
	if hp <= 0.0:
		die(dir)
	elif state == "walk" and (k >= 0.7 or randf() < 0.35) and not bool(type.get("giant", false)):
		# the flinch clip for heavy hits and a third of the light ones; a swing or scream is never interrupted
		play("hit")

# Seconds after play("attack") at which the swing's strike must land: the damage tick of common zombies.
func attack_lead() -> float:
	return 0.35

# Seconds a swing keeps its clip after the call (strike plus the arm coming back), capped by the cadence.
func attack_hold() -> float:
	return minf(float(type["attack_time"]), attack_lead() + 0.45)

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
	if _reveal_t > 0.0 and not on: return   # the lightning glow outlasts the hit flash
	for material in _materials:
		material.emission = Color(0.5, 0.1, 0.1) if on else Color.BLACK

func die(dir: Vector3) -> void:
	if not alive: return
	alive = false
	if anim:
		anim.active = true
		if _anim_lod != 1:
			# a corpse finishes its fall at full rate and never needs the LOD again
			_anim_lod = 1
			anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	for hitbox in _hitboxes:
		hitbox.collision_layer = 0
	hit_pending = 0.0
	velocity = Vector3.ZERO
	_death_dir = dir
	play("death")
	if not is_boss_kind(net_kind): Sfx.play_at(get_parent(), "zombie_death", global_position, -20.0)
	if last_headshot and not bool(type.get("giant", false)) and not bool(type.get("worm", false)):
		_pop_head(dir)
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

# A lethal headshot takes the head off: the Head bone's pose scale collapses (the Meshy clips carry no scale
# tracks, so the death clip leaves it alone - a SkeletonModifier3D was tried first and Godot restores the
# poses after modifiers) and the weapons' pooled blood bursts spray from the neck. Replicas get the same
# call through the co-op death state (snapshot field 13).
var _head_popped := false
# Dismemberment (25 Sep 2026): shots at a limb accumulate per limb (HitVolume.bone_name arrives as
# last_hit_bone); at LIMB_SHARE of the health in total or LIMB_BURST_SHARE in one hit the limb comes off
# (bones scaled away, blood, a burst sound). An arm halves the swing damage, both arms end the attacks, a
# leg brings the body down. "severed" is a bit mask over LIMB_KEYS, replicated as zombie snapshot field 14.
const LIMBS := {
	"LeftArm": ["LeftArm", "LeftForeArm", "LeftHand"],
	"RightArm": ["RightArm", "RightForeArm", "RightHand"],
	"LeftLeg": ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase"],
	"RightLeg": ["RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"],
}
const LIMB_KEYS := ["LeftArm", "RightArm", "LeftLeg", "RightLeg"]
const LIMB_SHARE := 0.4
const LIMB_BURST_SHARE := 0.3
var last_hit_bone := ""
var severed := 0
var _limb_damage := {}
var _gore_overrides := {}          # MeshInstance3D -> override material per original surface
var _gore_parts := {}              # "left_arm" .. "head" -> skinned MeshInstance3D (zombie_gore.gd)
const LIMB_PARTS := {"LeftArm": "left_arm", "RightArm": "right_arm", "LeftLeg": "left_leg", "RightLeg": "right_leg"}

static func limb_of(bone_name: String) -> String:
	for key in LIMBS:
		if bone_name in LIMBS[key]: return key
	return ""

func limb_severed(key: String) -> bool:
	return severed & (1 << LIMB_KEYS.find(key)) != 0

func _record_limb_hit(n: float, dir: Vector3) -> void:
	var key := limb_of(last_hit_bone)
	last_hit_bone = ""
	if key.is_empty() or limb_severed(key) or bool(type.get("giant", false)) or bool(type.get("worm", false)): return
	_limb_damage[key] = float(_limb_damage.get(key, 0.0)) + n
	if float(_limb_damage[key]) >= max_hp * LIMB_SHARE or n >= max_hp * LIMB_BURST_SHARE:
		sever(key, dir)

func sever(key: String, dir: Vector3) -> void:
	if limb_severed(key) or not model: return
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not rig: return
	severed |= 1 << LIMB_KEYS.find(key)
	var root_pos := global_position + Vector3.UP * height * 0.6
	var root_bone := rig.find_bone(LIMBS[key][0])
	if root_bone >= 0: root_pos = rig.global_transform * rig.get_bone_global_pose(root_bone).origin
	_cut_part(rig, LIMB_PARTS[key], key, dir, true)
	var scene := get_tree().current_scene
	if "weapons" in scene and scene.weapons and scene.weapons.has_method("_blood"):
		var away := Vector3(dir.x, 0.3, dir.z).normalized() if dir.length() > 0.01 else Vector3.UP
		scene.weapons._blood(root_pos, away)
		scene.weapons._blood(root_pos, away.rotated(Vector3.UP, 1.2))
	Sfx.play_at(get_parent(), "head_burst", root_pos, -12.0, randf_range(1.15, 1.35), 4.0, 40.0)
	if key.ends_with("Arm"):
		damage_mul *= 0.5
		if limb_severed("LeftArm") and limb_severed("RightArm"): damage_mul = 0.0
	elif alive and not replica and not NetSession.is_client():
		hp = 0.0
		die(dir)

# The part leaves the body: the cut mesh (zombie_gore.gd) when the model was split, else the old bone
# collapse. fly = the chunk tumbles away (limbs); the head bursts instead.
func _cut_part(rig: Skeleton3D, part: String, key: String, dir: Vector3, fly: bool) -> void:
	if _gore_parts.has(part):
		ZombieGore.sever(self, rig, _gore_parts[part], part, dir, fly)
		return
	var bones: Array = LIMBS[key] if LIMBS.has(key) else ["Head"]
	for bone_name in bones:
		var bone := rig.find_bone(bone_name)
		if bone >= 0: rig.set_bone_pose_scale(bone, Vector3(0.001, 0.001, 0.001))

# co-op replicas: apply the host's mask without the physics side effects
func apply_severed(mask: int) -> void:
	if mask == severed or not model: return
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not rig: return
	for i in LIMB_KEYS.size():
		if mask & (1 << i) and not (severed & (1 << i)):
			var key: String = LIMB_KEYS[i]
			_cut_part(rig, LIMB_PARTS[key], key, Vector3.UP, true)
			var scene := get_tree().current_scene
			if "weapons" in scene and scene.weapons: scene.weapons._blood(global_position + Vector3.UP * height * 0.6, Vector3.UP)
	severed = mask

func _pop_head(dir: Vector3) -> void:
	if _head_popped or not model: return
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not rig: return
	var bone := rig.find_bone("Head")
	if bone < 0: return
	_head_popped = true
	var head_pos: Vector3 = rig.global_transform * rig.get_bone_global_pose(bone).origin
	_cut_part(rig, "head", "", dir, false)
	var scene := get_tree().current_scene
	if "weapons" in scene and scene.weapons and scene.weapons.has_method("_blood"):
		var away := Vector3(dir.x, 0.0, dir.z).normalized()
		for spray in [away + Vector3.UP * 0.8, away.rotated(Vector3.UP, 0.9) + Vector3.UP * 0.4, away.rotated(Vector3.UP, -0.9) + Vector3.UP * 0.4]:
			scene.weapons._blood(head_pos, (spray as Vector3).normalized())
	# five baked burst variants (tools/build_head_burst_audio.py), random pick, pitch and level vary per head
	Sfx.play_at(get_parent(), "head_burst", head_pos, randf_range(-9.0, -4.0), randf_range(0.88, 1.14), 4.0, 45.0)

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
			_rare_marker.text = "FIRE + FROST" if burning and frozen else ("FIRE" if burning else "FROST")
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
	_update_animation(delta)
	if _reveal_t > 0.0:
		_reveal_t -= delta
		if _reveal_t <= 0.0:
			for material in _materials: material.emission = Color(0.5, 0.1, 0.1) if _flash_t > 0.0 else Color.BLACK
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0: _set_emission(false)
	if bool(type.get("stalker", false)) and model: _update_cloak(delta)
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
	var marked := _marked_player()
	if marked: player = marked
	elif NetSession.enabled:
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
	if frost_mul <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		agent.velocity = Vector3.ZERO
		hit_pending = 0.0
		if not is_on_floor(): velocity.y -= 20.0 * delta
		move_and_slide()
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
		if model and not clip.begins_with("hit"):
			# rigs without a flinch clip lean back procedurally
			model.rotation.x = -0.4 * sin(t * PI)
			model.position.y = 0.06 * sin(t * PI)
		elif state == "hit" and anim and not anim.is_playing():
			play("walk")   # the flinch is over while sustained fire keeps the body pinned: stand, do not freeze
		return
	if model and model.rotation.x != 0.0:
		model.rotation.x = 0.0
		model.position.y = 0.0
	if state == "scream":
		# rooted for the length of the scream, then back on the way
		_scream_t -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		agent.velocity = Vector3.ZERO
		if not is_on_floor(): velocity.y -= 20.0 * delta
		move_and_slide()
		if _scream_t <= 0.0: play("walk")
		return
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return
	if _special_move(delta): return
	var player_priority := _nearby_player_priority(delta)
	_update_hunt(delta)
	var p := global_position
	var to_player := player.global_position - p
	to_player.y = 0.0
	var dist := to_player.length()
	if _call_t > 0.0: _call_t -= delta
	if _spit_pending > 0.0:
		_spit_pending -= delta
		if _spit_pending <= 0.0: _spit()
	_decision_time -= delta
	if _decision_time <= 0.0 or (not is_instance_valid(_decision_target) and _decision_target != null):
		_decision_time = 0.16 + float(appearance_seed % 7) * 0.01
		_decision_target = _choose_defence(p, player_priority)
	var bar: Node3D = _decision_target if is_instance_valid(_decision_target) else null
	if bar and ((bar is Door and bar.is_open) or (not bar is Door and bar.hp <= 0.0)):
		_decision_target = _choose_defence(p, player_priority)
		_decision_time = 0.16 + float(appearance_seed % 7) * 0.01
		bar = _decision_target
	if player_priority and not bar is AttackDrone: bar = null
	var target: Vector3 = bar.attack_point(p) if bar else player.global_position
	agent.target_desired_distance = 0.25 if bar else 1.0
	var to_target := target - p
	to_target.y = 0.0
	var d := to_target.length()
	if type.has("screamer") and _call_t <= 0.0 and dist < float(type.screamer.range) and state == "walk" and attack_t <= 0.0 and _sees(player.global_position + Vector3.UP):
		_call_horde()
		return
	if type.has("ranged") and attack_t <= 0.0 and state == "walk" and _spit_pending <= 0.0:
		var spit_at := _spit_point(bar)
		var sd := Vector2(spit_at.x - p.x, spit_at.z - p.z).length()
		if sd >= float(type.ranged.min) and sd <= float(type.ranged.range) and _sees(spit_at, bar):
			play("attack")
			attack_t = float(type.ranged.cooldown)
			_spit_pending = 0.45
			_spit_target = spit_at
			velocity.x = 0.0
			velocity.z = 0.0
			agent.velocity = Vector3.ZERO
			rotation.y = lerp_angle(rotation.y, atan2(spit_at.x - p.x, spit_at.z - p.z), 1.0)
			if not is_on_floor(): velocity.y -= 20.0 * delta
			move_and_slide()
			return
	if not _screamed and dist < SCREAM_RANGE and d > 6.0 and not type.has("screamer"):
		# once, on first sight of the player: some of them stop and scream (rigs with the clip only, never
		# with a gate, wall or victim already within a few steps)
		_screamed = true
		if state == "walk" and attack_t <= 0.0 and appearance_seed % 100 < SCREAM_CHANCE and anim and anim.has_animation("scream") and not bool(type.get("giant", false)):
			play("scream")
			_scream_t = minf(clip_seconds("scream"), 1.8)
			attack_t = maxf(attack_t, _scream_t + 0.2)
			velocity = Vector3.ZERO
			agent.velocity = Vector3.ZERO
			return
	var dir := to_target.normalized()
	# face the target
	var yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, delta * 6.0))
	attack_t -= delta
	if _hit_t > 0.0: _hit_t -= delta
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
		elif attack_t < type["attack_time"] - attack_hold() and state == "attack":
			play("walk")
		elif state == "hit" and _hit_t <= 0.0:
			play("walk")
	else:
		if state != "walk" and attack_t < type["attack_time"] - attack_hold() and _hit_t <= 0.0:
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
			var sp: float = type["speed"] * speed_mul * frost_mul * horde_pace
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
			if dd < hit_reach + 0.6:
				if _can_hit(hit_target):
					if hit_target:
						hit_target.damage(type["damage"] * damage_mul)
					elif player.alive:
						player.damage(type["damage"] * damage_mul, global_position)
				elif _blocked_by_wall and not (hit_target is Barricade):
					_hit_palisade(type["damage"] * damage_mul)
	growl_t -= delta
	if growl_t <= 0.0 and dist < 25.0:
		growl_t = randf_range(4.0, 12.0)
		Sfx.play_at(get_parent(), "growl", global_position, -5.0)

# Beasts (zombie_beast.gd) put their charge here; true = the move owned this tick.
func _special_move(_delta: float) -> bool:
	return false

# the player a screamer marked (main.marked_player): every zombie on the map goes for them
func _marked_player() -> Player:
	var scene := get_tree().current_scene
	if scene and scene.has_method("marked_player"):
		var marked = scene.marked_player()
		if marked is Player and marked.alive: return marked
	return null

# a clear line from the eyes to a point; a hit on the very thing aimed at (a gate's body, the hut) counts as clear
func _sees(target: Vector3, aimed: Node3D = null) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * height * 0.8, target, 1 | 8, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return true
	if hit.collider is Node and (hit.collider as Node).is_in_group("hut_body"): return true
	if aimed and "body" in aimed and hit.collider == aimed.body: return true
	return false

# ---- the spitter: a glob of acid at the gate, the hut wall or the player it is walking towards
func _spit_point(bar: Node3D) -> Vector3:
	if bar and is_instance_valid(bar) and bar.has_method("attack_point"):
		var at: Vector3 = bar.attack_point(global_position)
		return at + Vector3.UP * (0.7 if bar is Barricade else 1.2)
	return player.global_position + Vector3.UP * 0.4

func _spit() -> void:
	if not alive or replica or NetSession.is_client() or not _spit_target.is_finite(): return
	var scene := get_tree().current_scene
	if not scene or not scene.has_method("acid_spit"): return
	var mouth := global_position + Vector3.UP * height * 0.78 + global_basis.z * 0.5
	scene.acid_spit(mouth, _spit_target, self)
	_spit_target = Vector3.INF

# ---- the screamer: rooted for its cry, the horde and the map learn where the player is
func _call_horde() -> void:
	_call_t = float(type.screamer.cooldown)
	calls += 1
	play("scream")
	_scream_t = 2.4
	attack_t = maxf(attack_t, 2.7)
	velocity = Vector3.ZERO
	agent.velocity = Vector3.ZERO
	var scene := get_tree().current_scene
	if scene and scene.has_method("horde_call"): scene.horde_call(self, player)

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
	# Nearby exposed towers can be attacked; a blocking fence still takes priority. Roof turrets are
	# out of reach: chasing one left the zombie swinging at the wall below for no damage, not even to the hut.
	if bar == null and not hunting:
		for tower in get_tree().get_nodes_in_group("defence_towers"):
			if tower.rooftop: continue
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
	# Low flying drones are exposed to a real, telegraphed melee strike.
	for drone: AttackDrone in get_tree().get_nodes_in_group("attack_drones"):
		if drone.hp > 0 and drone.global_position.distance_to(p) < float(type["reach"]) + 0.4 and _can_hit(drone):
			bar = drone
			break
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
	if replica or not alive or frost_mul <= 0.0 or not player or (not player.active and not NetSession.enabled) or get_tree().paused:
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
	var target: Vector3 = (bar.global_position if bar is AttackDrone else bar.attack_point(global_position) + Vector3.UP) if bar else player.global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 8)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_blocked_by_wall = false
	if hit.is_empty(): return true
	_blocked_by_wall = hit.collider is Node and (hit.collider as Node).is_in_group("perimeter_wall")
	if bar == null: return false
	return hit.collider == bar.body or (bar is HutHealth and hit.collider.is_in_group("hut_body"))

# A swing that lands on the palisade instead of its target (the player right behind the wall, the hut
# behind it) shakes the ring on its gate posts: the nearest built gate takes WALL_HIT_SHARE of the damage
# and raises its attack alert, so the HUD arrows point there. Before 25 Sep 2026 those swings did nothing.
const WALL_HIT_SHARE := 0.6
var _blocked_by_wall := false
func _hit_palisade(amount: float) -> void:
	var nearest: Barricade = null
	var best := INF
	for b in barricades:
		if not b is Barricade or b.level <= 0 or b.hp <= 0.0 or not b.is_gate(): continue
		var d: float = b.distance_to_line(global_position)
		if d < best:
			best = d
			nearest = b
	if nearest: nearest.damage(amount * WALL_HIT_SHARE)

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

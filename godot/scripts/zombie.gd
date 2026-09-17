# Zombie: navmesh pathing to the player, attacks player or a blocking barricade, plays GLB clips.
class_name Zombie
extends CharacterBody3D

const TYPES := {
	"shambler": { "model": "zombie_shambler", "hp": 100.0, "speed": 1.6, "damage": 12.0, "reach": 1.6, "attack_time": 1.1, "score": 10, "height": 1.8 },
	"runner": { "model": "zombie_runner", "hp": 60.0, "speed": 4.2, "damage": 8.0, "reach": 1.4, "attack_time": 0.7, "score": 15, "height": 1.7 },
	"brute":    { "model": "zombie_bloater", "fallback": "zombie_shambler", "hp": 320.0, "speed": 1.2, "damage": 25.0, "reach": 2.0, "attack_time": 1.6, "score": 40, "height": 2.3, "tint": Color(0.9, 0.85, 0.6) },
	"nurse":    { "model": "zombie_nurse", "fallback": "zombie_runner", "hp": 80.0, "speed": 2.6, "damage": 10.0, "reach": 1.5, "attack_time": 0.9, "score": 15, "height": 1.7 },
	"soldier":  { "model": "zombie_soldier", "fallback": "zombie_shambler", "hp": 180.0, "speed": 1.9, "damage": 16.0, "reach": 1.6, "attack_time": 1.0, "score": 25, "height": 1.85 },
}

var type: Dictionary
var hp: float
var height: float
var alive := true
var player: Player
var barricades: Array = []
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
var _repath := 0.0
var _on_kill: Callable
var _materials: Array[BaseMaterial3D] = []
static var _scenes := {}

static func preload_models() -> void:
	for spec: Dictionary in TYPES.values():
		var path := "res://assets/models/%s.glb" % spec["model"]
		if not ResourceLoader.exists(path) and spec.has("fallback"):
			path = "res://assets/models/%s.glb" % spec["fallback"]
		if not _scenes.has(path):
			_scenes[path] = load(path) if ResourceLoader.exists(path) else null

func setup(type_name: String, p: Player, bars: Array, spd_mul: float, on_kill: Callable) -> void:
	type = TYPES[type_name]
	player = p
	barricades = bars
	speed_mul = spd_mul
	_on_kill = on_kill
	hp = type["hp"]
	height = type["height"]
	growl_t = randf_range(2.0, 8.0)
	_repath = randf_range(0.05, 0.4)

func _ready() -> void:
	collision_layer = 2
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
	agent.avoidance_enabled = true
	agent.neighbor_distance = 6.0
	agent.max_neighbors = 6
	agent.max_speed = float(type["speed"]) * speed_mul
	agent.velocity_computed.connect(_on_velocity_computed)
	add_child(agent)
	var path := "res://assets/models/%s.glb" % type["model"]
	if not ResourceLoader.exists(path) and type.has("fallback"):
		path = "res://assets/models/%s.glb" % type["fallback"]
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
			anim.speed_scale = randf_range(0.85, 1.15)
			anim.play("walk")
		var tint: Color = type.get("tint", Color.from_hsv(randf_range(0.2, 0.3), 0.25, randf_range(0.75, 1.0)))
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
	var scale_var := randf_range(0.94, 1.08)
	if model:
		model.scale *= scale_var

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
	hit_pending = 0.0
	velocity = Vector3.ZERO
	play("death")
	Sfx.play_at(get_parent(), "growl", global_position, -2.0, 0.75)
	collision_layer = 0
	collision_mask = 1
	agent.avoidance_enabled = false
	player.add_score(type["score"])
	if _on_kill.is_valid():
		_on_kill.call(self)
	global_position += Vector3(dir.x, 0.0, dir.z).normalized() * 0.3

func _physics_process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_emission(false)
	if not alive:
		dead_t += delta
		if dead_t > 6.0:
			global_position.y -= delta * 0.4
		if dead_t > 9.0:
			queue_free()
		return
	if not player or not player.active:
		return
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
	var p := global_position
	var to_player := player.global_position - p
	to_player.y = 0.0
	var dist := to_player.length()
	# a barricade between us and the player becomes the target
	var bar = null
	var bd := 1e9
	for b in barricades:
		if b.hp > 0.0 and b.crosses(p, player.global_position):
			var dd: float = b.center.distance_to(p)
			if dd < bd:
				bd = dd
				bar = b
	var target: Vector3 = bar.attack_point(p) if bar else player.global_position
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
					agent.target_position = target
			var next := agent.get_next_path_position()
			var mv := next - p
			mv.y = 0.0
			var sp: float = type["speed"] * speed_mul
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
			var dd: float = hit_target.attack_point(global_position).distance_to(global_position) if hit_target else player.global_position.distance_to(global_position)
			if dd < hit_reach + 0.6 and _can_hit(hit_target):
				if hit_target:
					hit_target.damage(type["damage"] * 2.0)
				elif player.alive:
					player.damage(type["damage"])
	growl_t -= delta
	if growl_t <= 0.0 and dist < 25.0:
		growl_t = randf_range(4.0, 12.0)
		Sfx.play_at(get_parent(), "growl", global_position, -5.0)

func _on_velocity_computed(safe: Vector3) -> void:
	if not alive or not player or not player.active or get_tree().paused:
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
	return hit.is_empty() or (bar != null and hit.collider == bar.body)

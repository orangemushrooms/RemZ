# Deer: graze near the forest edge and bolt when the player (or a zombie) comes close.
class_name Deer
extends CharacterBody3D

var model: Node3D
var player: Player
var kind := "deer"
var state := "graze"
var flee_t := 0.0
var flee_dir := Vector3.ZERO
var speed := 9.0
var _t := 0.0
var _graze_target := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _base_y := 0.0

func setup(p: Player, k: String, scene: PackedScene, seed_v: int) -> void:
	player = p
	kind = k
	_rng.seed = seed_v
	collision_layer = 1
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.2
	cs.shape = cap
	cs.position.y = 0.7
	add_child(cs)
	var h := 1.25 if k == "deer" else 1.6
	if scene:
		model = scene.instantiate()
		add_child(model)
		Weapons._fit_height(model, h)
		model.position.y += h / 2.0
		model.rotation.y = PI   # Meshy animals face +Z, we move along -Z
	else:
		model = Node3D.new()
		add_child(model)
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.6, 1.3)
		body.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.3, 0.18)
		body.material_override = mat
		body.position.y = 0.9
		model.add_child(body)
	_base_y = model.position.y

func _ready() -> void:
	# setup runs before the animal is attached and positioned in the level.
	call_deferred("_set_graze_origin")

func _set_graze_origin() -> void:
	_graze_target = global_position

func _physics_process(delta: float) -> void:
	_t += delta
	if not player:
		return
	var to_p := player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if state == "graze":
		if dist < 26.0:
			state = "flee"
			flee_t = 6.0 + _rng.randf() * 3.0
			var away := -to_p.normalized()
			flee_dir = (away + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))).normalized()
			Sfx.play_at(get_parent(), "hit", global_position, -14.0)
		else:
			# wander slowly between graze spots
			var d := _graze_target - global_position
			d.y = 0.0
			if d.length() < 0.6 or _rng.randf() < 0.002:
				_graze_target = global_position + Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
			var v := d.normalized() * 0.7 if d.length() > 0.6 else Vector3.ZERO
			velocity.x = v.x
			velocity.z = v.z
			if v.length() > 0.1:
				rotation.y = lerp_angle(rotation.y, atan2(-v.x, -v.z), delta * 2.0)
			# head down / up grazing bob
			model.rotation.x = 0.12 * sin(_t * 0.7)
	else:
		flee_t -= delta
		# steer around obstacles by drifting when blocked
		if get_slide_collision_count() > 0:
			flee_dir = flee_dir.rotated(Vector3.UP, _rng.randf_range(-1.2, 1.2)).normalized()
		var sp := speed * (1.2 if kind == "stag" else 1.0)
		# accelerate smoothly, lean into turns, gentle stride bob (no hopping)
		var want := Vector3(flee_dir.x * sp, 0, flee_dir.z * sp)
		velocity.x = lerpf(velocity.x, want.x, minf(1.0, delta * 3.0))
		velocity.z = lerpf(velocity.z, want.z, minf(1.0, delta * 3.0))
		var target_yaw := atan2(-flee_dir.x, -flee_dir.z)
		var turn := wrapf(target_yaw - rotation.y, -PI, PI)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 2.5)
		model.rotation.z = lerpf(model.rotation.z, clampf(-turn * 0.25, -0.2, 0.2), delta * 4.0)
		var stride := Vector2(velocity.x, velocity.z).length() / sp
		model.position.y = _base_y + absf(sin(_t * 6.0)) * 0.05 * stride
		model.rotation.x = sin(_t * 6.0) * 0.03 * stride
		if flee_t <= 0.0 and dist > 55.0:
			state = "graze"
			model.position.y = _base_y
			model.rotation.x = 0.0
			model.rotation.z = 0.0
			_graze_target = global_position
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -1.0
	move_and_slide()
	var b := Map.BOUNDS
	global_position.x = clampf(global_position.x, b.position.x + 5.0, b.end.x - 5.0)
	global_position.z = clampf(global_position.z, b.position.y + 5.0, b.end.y - 5.0)

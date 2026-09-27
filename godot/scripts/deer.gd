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
var animation: AnimationPlayer
var _last_position := Vector3.INF
var _ground_speed := 0.0
var _graze_wait := 3.0
var _avoid_cooldown := 0.0
var net_position := Vector3.INF
var net_rotation := Vector3.ZERO

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
	animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation:
		for clip in ["walk", "run", "graze", "idle"]:
			if animation.has_animation(clip): animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		animation.play("idle")
		animation.seek(float(seed_v % 31) / 10.0)

func _ready() -> void:
	# setup runs before the animal is attached and positioned in the level.
	call_deferred("_set_graze_origin")

func _set_graze_origin() -> void:
	_graze_target = global_position

func _physics_process(delta: float) -> void:
	_t += delta
	_avoid_cooldown = maxf(0, _avoid_cooldown - delta)
	if NetSession.is_host():
		var closest := NetSession.nearest_player(global_position)
		if closest: player = closest
	if not is_instance_valid(player):
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
			Sfx.play_at(get_parent(), "rustle", global_position, -10.0)
		else:
			# wander slowly between graze spots
			var d := _graze_target - global_position
			d.y = 0.0
			if d.length() < 0.6:
				_graze_wait -= delta
				if _graze_wait <= 0:
					_graze_target = global_position + Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
					_graze_wait = _rng.randf_range(3, 8)
			var v := d.normalized() * 0.7 if d.length() > 0.6 else Vector3.ZERO
			velocity.x = move_toward(velocity.x, v.x, delta * 3.0)
			velocity.z = move_toward(velocity.z, v.z, delta * 3.0)
			if v.length() > 0.1:
				rotation.y = lerp_angle(rotation.y, atan2(-v.x, -v.z), delta * 2.0)
	else:
		flee_t -= delta
		if global_position.x < Map.BOUNDS.position.x + 10: flee_dir.x = absf(flee_dir.x)
		if global_position.x > Map.BOUNDS.end.x - 10: flee_dir.x = -absf(flee_dir.x)
		if global_position.z < Map.BOUNDS.position.y + 10: flee_dir.z = absf(flee_dir.z)
		if global_position.z > Map.BOUNDS.end.y - 10: flee_dir.z = -absf(flee_dir.z)
		flee_dir = flee_dir.normalized()
		# steer around obstacles by drifting when blocked
		# Floor contact is present every frame: only steer at actual walls/trees.
		if _avoid_cooldown <= 0:
			for i in get_slide_collision_count():
				var normal := get_slide_collision(i).get_normal()
				if normal.y > 0.55: continue
				flee_dir = (flee_dir.slide(normal) + normal * 0.7).normalized()
				_avoid_cooldown = 0.7
				break
		var sp := speed * (1.2 if kind == "stag" else 1.0)
		# accelerate smoothly, lean into turns, gentle stride bob (no hopping)
		var want := Vector3(flee_dir.x * sp, 0, flee_dir.z * sp)
		velocity.x = lerpf(velocity.x, want.x, minf(1.0, delta * 3.0))
		velocity.z = lerpf(velocity.z, want.z, minf(1.0, delta * 3.0))
		var target_yaw := atan2(-flee_dir.x, -flee_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * 2.5)
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

func _process(delta: float) -> void:
	if not model or not visible: return
	if NetSession.is_client() and net_position.is_finite():
		global_position = global_position.lerp(net_position, 1.0 - exp(-delta * 14))
		rotation.y = lerp_angle(rotation.y, net_rotation.y, 1.0 - exp(-delta * 14))
	var moved := 0.0 if not _last_position.is_finite() else Vector2(global_position.x - _last_position.x, global_position.z - _last_position.z).length() / maxf(0.001, delta)
	_last_position = global_position
	_ground_speed = lerpf(_ground_speed, moved if moved < 25 else 0, 1.0 - exp(-delta * 8))
	if animation:
		var clip := "run" if _ground_speed > 2.5 else ("walk" if _ground_speed > 0.15 else "graze")
		if animation.current_animation != clip: animation.play(clip, 0.28)
		var natural := (5.22 if clip == "run" else 0.483) * model.scale.y
		animation.speed_scale = clampf(_ground_speed / natural, 0.2, 2.8) if clip != "graze" else 0.8
	# Follow the slope with a restrained body lean; individual hoof motion is skeletal.
	var normal := Map.ground_normal(global_position.x, global_position.z)
	var forward := -global_basis.z
	var pitch := atan2(normal.dot(forward), normal.y)
	model.rotation.x = lerpf(model.rotation.x, clampf(pitch, -0.18, 0.18), 1.0 - exp(-delta * 5))

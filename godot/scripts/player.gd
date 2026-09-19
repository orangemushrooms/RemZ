# First-person player: movement, mouse look, flashlight, health.
class_name Player
extends CharacterBody3D

signal died

const WALK_SPEED := 4.4
const SPRINT_SPEED := 7.2
const VAULT_SPEED := 9.4              # clears a 1.55 m barricade with 0.6 m to spare at gravity 20
const EYE := 1.7
const SENS := 0.0022

var camera: Camera3D
var head: Node3D
var flashlight: SpotLight3D
var hud: Hud
var hp := 100.0
var max_hp := 100.0
var score := 0
var alive := true
var active := false
var pitch := 0.0
var bob := 0.0
var regen_timer := 0.0
var wobble := 0.0
var tremor_scale := 1.0
var _tremor := 0.0
var _tremor_left := 0.0
var _tremor_duration := 1.0
var _tremor_phase := 0.0
var _gravity := 20.0
var speed_mul := 1.0
var regen_mul := 1.0
var recoil_offset := Vector2.ZERO   # (pitch, yaw) radians of visual recoil still settling
var mouse_sensitivity := 1.0
var _step_t := 0.0
var _step_side := 1.0
var _heart_t := 0.0
var _was_on_floor := true
var peer_id := 1
var remote_actor := false

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 8
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 600.0
	head.add_child(camera)
	if not remote_actor:
		camera.make_current()
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.95, 0.84)
	flashlight.light_energy = 6.0
	flashlight.spot_range = 45.0
	flashlight.spot_angle = 26.0
	flashlight.spot_attenuation = 0.9
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.15, -0.1, -0.2)
	camera.add_child(flashlight)
	rotation.y = PI

func _unhandled_input(event: InputEvent) -> void:
	if remote_actor or not active or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.screen_relative.x * SENS * mouse_sensitivity)
		pitch = clampf(pitch - event.screen_relative.y * SENS * mouse_sensitivity, -1.45, 1.45)
		head.rotation.x = clampf(pitch + recoil_offset.x, -1.48, 1.48)
	if event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible

func _physics_process(delta: float) -> void:
	if remote_actor:
		if NetSession.is_host() and alive:
			_regenerate(delta)
		return
	if not active or not alive:
		_clear_tremor()
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprint := Input.is_action_pressed("sprint")
	var speed := (SPRINT_SPEED if sprint else WALK_SPEED) * speed_mul
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var target := dir * speed
	velocity.x = lerpf(velocity.x, target.x, minf(1.0, delta * 12.0))
	velocity.z = lerpf(velocity.z, target.z, minf(1.0, delta * 12.0))
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_key_pressed(KEY_SPACE):
		# a built gate barricade right in front: climb over it (zombies cannot)
		velocity.y = VAULT_SPEED if _barricade_ahead() else 6.5
	else:
		velocity.y = -1.0
	move_and_slide()
	# keep inside the map
	global_position.x = clampf(global_position.x, Map.BOUNDS.position.x, Map.BOUNDS.end.x)
	global_position.z = clampf(global_position.z, Map.BOUNDS.position.y, Map.BOUNDS.end.y)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	_footsteps(delta, moving, sprint)
	bob += delta * ((13.0 if sprint else 9.0) if moving else 0.0)
	head.position.y = EYE + (sin(bob) * 0.04 if moving else 0.0)
	wobble = maxf(0.0, wobble - delta * 3.0)
	camera.rotation.z = (sin(bob * 0.5) * 0.004 if moving else 0.0) + sin(wobble * 30.0) * 0.02 * wobble
	head.rotation.x = clampf(pitch + recoil_offset.x, -1.48, 1.48)
	camera.rotation.y = recoil_offset.y
	_update_tremor(delta)
	if not NetSession.is_client():
		_regenerate(delta)

# Slow, damped soil vibration; separate from hit feedback and mouse/recoil state.
# Multiple nearby giants cannot accumulate an unbounded shake.
func add_tremor(strength: float, duration: float) -> void:
	if remote_actor or not active or not alive or tremor_scale <= 0: return
	if not is_finite(strength) or not is_finite(duration) or strength <= 0: return
	var remaining := _tremor * pow(_tremor_left / _tremor_duration, 2)
	_tremor = clampf(maxf(remaining, strength) + minf(remaining, strength) * 0.15, 0, 1)
	_tremor_duration = clampf(duration, 0.15, 3.0)
	_tremor_left = _tremor_duration

func _clear_tremor() -> void:
	_tremor = 0
	_tremor_left = 0
	if camera:
		camera.position = Vector3.ZERO
		camera.rotation.x = 0
		camera.rotation.z = 0

func _update_tremor(delta: float) -> void:
	_tremor_left = maxf(0, _tremor_left - delta)
	_tremor_phase += delta
	var envelope := pow(_tremor_left / _tremor_duration, 2)
	var attack := clampf((_tremor_duration - _tremor_left) / 0.075, 0, 1)
	var amount := _tremor * envelope * attack * tremor_scale
	var t := _tremor_phase
	camera.position = Vector3(sin(t * 24.7) * 0.012, (sin(t * 31.0) + sin(t * 47.0) * 0.25) * 0.035, 0) * amount
	camera.rotation.x = (sin(t * 23.0) + sin(t * 39.0) * 0.3) * 0.006 * amount
	camera.rotation.z += sin(t * 19.0) * 0.004 * amount

func _regenerate(delta: float) -> void:
	if regen_timer > 0.0:
		regen_timer -= delta
	elif hp < max_hp:
		hp = minf(max_hp, hp + delta * 4.0 * regen_mul)
		hud.set_health(hp)

# from: world position of the attacker (Vector3.INF = unknown) for the HUD direction indicator
func _barricade_ahead() -> bool:
	var fwd := -transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		return false
	var from := global_position + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd.normalized() * 1.5, 8)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func damage(n: float, from: Vector3 = Vector3.INF) -> void:
	if NetSession.is_client():
		return
	if not alive:
		return
	hp -= n
	var scene := get_tree().current_scene
	if "achievements" in scene and scene.achievements:
		scene.achievements.player_hurt()
	if "stats" in scene and scene.stats:
		scene.stats.damage_taken += n
	regen_timer = 5.0
	wobble = 1.0
	hud.set_health(hp)
	if from.is_finite():
		var local := global_transform.basis.inverse() * (from - global_position)
		hud.damage_flash(atan2(local.x, -local.z))
	else:
		hud.damage_flash()
	if not remote_actor:
		Sfx.play(self, "hurt", -3.0, 0.85)
		Sfx.play(self, "hurt_thud", -10.0)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		died.emit()

func add_score(n: int) -> void:
	score += n
	hud.set_score(score)

# Footsteps on the surface under the player (gravel, grass or leaf litter), a landing thud, heartbeat when low.
func _footsteps(delta: float, moving: bool, sprint: bool) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		Sfx.footstep(self, _surface_step(), -8.0, 0.8)
	_was_on_floor = on_floor
	if moving and on_floor:
		_step_t -= delta * (1.0 if not sprint else 1.35) * speed_mul
		if _step_t <= 0.0:
			_step_t = 0.48
			_step_side = -_step_side
			Sfx.footstep(self, _surface_step(), -13.0 if not sprint else -10.0, 1.0 + 0.05 * _step_side)
	else:
		_step_t = minf(_step_t, 0.12)
	if alive and hp < max_hp * 0.35:
		_heart_t -= delta
		if _heart_t <= 0.0:
			_heart_t = lerpf(0.55, 1.1, clampf(hp / (max_hp * 0.35), 0.0, 1.0))
			Sfx.play(self, "heartbeat", -6.0, 1.0)
			get_tree().create_timer(0.22, false).timeout.connect(func():
				if is_instance_valid(self):
					Sfx.play(self, "heartbeat", -10.0, 1.15))

# "hard" (asphalt, concrete), "gravel" (tracks and the fire plaza), "grass" (meadow), "leaves" (forest floor)
# or "wood" (the hut's upper floor). Asphalt has no cover weight at all in ground.png.
func _surface_step() -> String:
	var x := global_position.x
	var z := global_position.z
	if Map.in_building(x, z):
		# the Waldhuette's upper room has a plank floor 2.65 m above the garage slab; everything else is concrete
		var hut: Dictionary = Map.BUILDINGS["waldhuette"]
		var hp: Vector2 = hut["pos"]
		if Vector2(x, z).distance_to(hp) < 7.0 and global_position.y > Map.ground_height(hp.x - 4.5, hp.y) + 1.5:
			return "wood"
		return "hard"
	var c := Map.cover(x, z)
	if c.r < 0.3 and c.g < 0.3 and c.b < 0.3:
		return "hard"
	if c.b > 0.5:
		return "gravel"
	if c.g > 0.5:
		return "grass"
	return "leaves"

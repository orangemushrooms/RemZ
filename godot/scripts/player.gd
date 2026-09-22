# First-person player: movement, mouse look, flashlight, health.
class_name Player
extends CharacterBody3D

signal died

const WALK_SPEED := 4.4
const SPRINT_SPEED := 7.2
const VAULT_SPEED := 9.4              # clears a 1.55 m barricade with 0.6 m to spare at gravity 20
const CROUCH_SPEED := 2.2
const CROUCH_EYE := 1.05
const CROUCH_HEIGHT := 1.2
const STAND_HEIGHT := 1.8
const EYE := 1.7
const SENS := 0.0022

var crouching := false
var body_shape: CollisionShape3D
var stance_eye := EYE
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
var mushroom_effects: Dictionary = {}
var relic := ""
const RareItems = preload("res://scripts/rare_items.gd")

func relic_multiplier(attribute: String) -> float:
	return RareItems.multiplier(relic, attribute)

const Mushrooms = preload("res://scripts/mushrooms.gd")

func mushroom_multiplier(attribute: String) -> float:
	return Mushrooms.multiplier(mushroom_effects, attribute)

func effective_speed_mul() -> float:
	return speed_mul * mushroom_multiplier("speed") * relic_multiplier("speed")
var recoil_offset := Vector2.ZERO   # (pitch, yaw) radians of visual recoil still settling
var mouse_sensitivity := 1.0
var _step_t := 0.0
var _step_side := 1.0
var _heart_t := 0.0
var _was_on_floor := true
var peer_id := 1
var remote_actor := false
var cash_cooldown := 0.0
var mounted_tower := 0
var _motion_from := Vector3.ZERO
var _motion_to := Vector3.ZERO
var _motion_ready := false
var _camera_motion_offset := Vector3.ZERO

func _ready() -> void:
	# Update the view before weapon alignment and HUD projection each render frame.
	process_priority = -20
	collision_layer = 4
	collision_mask = 1 | 8
	var shape := CollisionShape3D.new()
	body_shape = shape
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

# Keep the feet fixed; only the upper capsule and eye height change.
func set_crouching(wanted: bool, check_ceiling: bool = true) -> void:
	if not body_shape: return
	if wanted == crouching: return
	if not wanted and crouching and check_ceiling:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.39
		cap.height = STAND_HEIGHT - 0.02
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = cap
		query.transform = Transform3D(global_basis, global_position + Vector3.UP * (STAND_HEIGHT * 0.5 + 0.02))
		query.collision_mask = collision_mask
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return
	crouching = wanted
	var height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	body_shape.shape.height = height
	body_shape.position.y = height * 0.5
	if remote_actor:
		stance_eye = CROUCH_EYE if crouching else EYE
		head.position.y = stance_eye

func stance_precision() -> float:
	# No stability bonus while falling/jumping or moving faster than a crouch.
	return 0.7 if crouching and absf(velocity.y) < 2.0 and Vector2(velocity.x, velocity.z).length() <= CROUCH_SPEED * effective_speed_mul() + 0.2 else 1.0

func _unhandled_input(event: InputEvent) -> void:
	if remote_actor or not active or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var zoom_scale := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(75.0) * 0.5) if mounted_tower else 1.0
		rotate_y(-event.screen_relative.x * SENS * mouse_sensitivity * zoom_scale)
		pitch = clampf(pitch - event.screen_relative.y * SENS * mouse_sensitivity * zoom_scale, -1.45, 1.45)
		head.rotation.x = clampf(pitch + recoil_offset.x, -1.48, 1.48)
	if event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
		Sfx.play(self, "flashlight", -12.0)
	if event.is_action_pressed("drop_cash") and not event.is_echo():
		if NetSession.enabled: NetSession.command("drop_cash")
		else:
			var message := Pickup.throw_cash(self)
			if not message.is_empty(): hud.message(message, 1.4)
		get_viewport().set_input_as_handled()

func _restore_camera_motion() -> void:
	if camera and _camera_motion_offset != Vector3.ZERO:
		camera.position -= _camera_motion_offset
	_camera_motion_offset = Vector3.ZERO

func _process(_delta: float) -> void:
	_update_camera_motion(Engine.get_physics_interpolation_fraction())

func _update_camera_motion(fraction: float) -> void:
	_restore_camera_motion()
	if remote_actor or not active or not alive or mounted_tower or not is_physics_processing() or not _motion_ready: return
	# Teleports/network corrections must snap, never sweep through the map.
	if not global_position.is_equal_approx(_motion_to):
		_motion_ready = false
		return
	# Blend translation between physics ticks. Mouse look remains immediate and
	# collision, movement speed, hit timing and recoil retain their original tick.
	var position_on_frame := _motion_from.lerp(_motion_to, fraction)
	_camera_motion_offset = head.global_basis.inverse() * (position_on_frame - global_position)
	camera.position += _camera_motion_offset

func _physics_process(delta: float) -> void:
	_restore_camera_motion()
	_motion_ready = false
	_motion_from = global_position
	cash_cooldown = maxf(0.0, cash_cooldown - delta)
	if not NetSession.is_client() and alive and not get_tree().paused:
		Mushrooms.tick(mushroom_effects, delta)
	if not alive: mushroom_effects.clear()
	if remote_actor:
		if NetSession.is_host() and alive:
			_regenerate(delta)
		return
	if not active or not alive:
		_clear_tremor()
		return
	if mounted_tower:
		velocity = Vector3.ZERO
		pitch = clampf(pitch,-1.1,0.85)
		head.rotation.x = pitch
		head.position.y = CROUCH_EYE
		if not NetSession.is_client(): _regenerate(delta)
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	set_crouching(Input.is_action_pressed("crouch"))
	var sprint := Input.is_action_pressed("sprint") and not crouching
	var speed := (CROUCH_SPEED if crouching else SPRINT_SPEED if sprint else WALK_SPEED) * effective_speed_mul()
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var target := dir * speed
	velocity.x = lerpf(velocity.x, target.x, minf(1.0, delta * 12.0))
	velocity.z = lerpf(velocity.z, target.z, minf(1.0, delta * 12.0))
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_key_pressed(KEY_SPACE) and not crouching:
		# a built gate barricade right in front: climb over it (zombies cannot)
		velocity.y = VAULT_SPEED if _barricade_ahead() else 6.5
	else:
		velocity.y = -1.0
	move_and_slide()
	# keep inside the map
	global_position.x = clampf(global_position.x, Map.BOUNDS.position.x, Map.BOUNDS.end.x)
	global_position.z = clampf(global_position.z, Map.BOUNDS.position.y, Map.BOUNDS.end.y)
	_motion_to = global_position
	_motion_ready = true
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	_footsteps(delta, moving, sprint)
	bob += delta * ((13.0 if sprint else 9.0) if moving else 0.0)
	stance_eye = move_toward(stance_eye, CROUCH_EYE if crouching else EYE, delta * 5.0)
	head.position.y = stance_eye + (sin(bob) * (0.015 if crouching else 0.04) if moving else 0.0)
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
		hp = minf(max_hp, hp + delta * 4.0 * regen_mul * mushroom_multiplier("regen"))
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
	n *= mushroom_multiplier("guard") * relic_multiplier("guard")
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
		Sfx.play(self, "hurt", -4.0)
		Sfx.play(self, "hurt_thud", -10.0)
	if hp <= 0.0:
		if "progression" in scene and scene.progression and scene.progression.rare_market.prevent_death(self): return
		hp = 0.0
		alive = false
		if "stats" in scene and scene.stats: scene.stats.record_death(peer_id)
		if mounted_tower and "defences" in scene and scene.defences.towers.has(mounted_tower):
			scene.defences.release_tower(scene.defences.towers[mounted_tower])
		mushroom_effects.clear()
		if not remote_actor: Sfx.play(self, "player_death", -2.0)
		died.emit()

func add_score(n: int) -> void:
	score += n
	hud.set_score(score)

# Footsteps on the surface under the player (gravel, grass or leaf litter), a landing thud, heartbeat when low.
func _footsteps(delta: float, moving: bool, sprint: bool) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		Sfx.footstep(self, _surface_step(), -8.0, 0.8)
		Sfx.play(self, "land", -14.0)
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
			# one recorded lub-dub (1.5 s clip) per interval, faster and a little higher when close to death
			var urgency := clampf(hp / (max_hp * 0.35), 0.0, 1.0)
			_heart_t = lerpf(0.9, 1.5, urgency)
			Sfx.play(self, "heartbeat", -6.0, lerpf(1.25, 1.0, urgency))

# "hard" (asphalt, concrete), "gravel" (tracks and the fire plaza), "grass" (meadow), "leaves" (forest floor),
# "corn" (standing maize) or "wood" (the hut's upper floor). Asphalt has no cover weight at all in ground.png.
func _surface_step() -> String:
	var x := global_position.x
	var z := global_position.z
	var field = get_tree().current_scene.get("cornfield") if get_tree().current_scene else null
	if field and field.in_corn(Vector2(x, z)):
		return "corn"
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

class_name ForestSpirit
extends Zombie

# The source Meshy mesh was rigged locally with weighted limbs and eight clips.
# The root hover and warning ring add to the skeletal motion.
const PULSE_RADIUS := 5.5
const PULSE_WINDUP := 1.5
const PULSE_COOLDOWN := 11.0
const PULSE_DAMAGE := 32.0

var _hover_time := 0.0
var _model_y := 0.0
var _pulse_cool := 4.0
var _pulse_t := 0.0
var _pulse_serial := 0
var _pulse_ring: MeshInstance3D
var _flinch_cool := 0.0

func _fit_model() -> void:
	# The locally authored bind pose is 1.899 m tall and centred on the origin.
	model.scale = Vector3.ONE * (height / 1.899)
	model.position.y = height * 0.5
	_model_y = model.position.y

func _build_hitboxes() -> void:
	# Simple bone-following volumes keep the large rig inexpensive to load.
	# The movement capsule remains a bullet fallback for the torso and legs.
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not rig: return
	for entry in [
		["Head", Vector3(0, 0.06, 0), 0.34, 0.17, true],
		["LeftForeArm", Vector3(0, -0.22, 0), 0.54, 0.14, false],
		["RightForeArm", Vector3(0, -0.22, 0), 0.54, 0.14, false],
		["LeftHand", Vector3(0, -0.19, 0), 0.58, 0.17, false],
		["RightHand", Vector3(0, -0.19, 0), 0.58, 0.17, false],
	]:
		if rig.find_bone(entry[0]) < 0: continue
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = entry[0]
		rig.add_child(attachment)
		var area := Area3D.new()
		area.collision_layer = HITBOX_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_meta("zombie", self)
		area.set_meta("headshot", entry[4])
		attachment.add_child(area)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.height = entry[2]
		capsule.radius = entry[3]
		shape.shape = capsule
		shape.position = entry[1]
		area.add_child(shape)
		_hitboxes.append(area)

func _build_head_look() -> void:
	pass

func _ready() -> void:
	super._ready()
	_set_emission(false)
	# _ready disables capsule shots when bone volumes exist; retain torso coverage.
	collision_layer = 2 | HITBOX_LAYER
	# Navigation and bullet collision follow the same large, unrigged body.
	for child in get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			child.shape.radius = 0.75
	agent.radius = 0.75
	agent.target_desired_distance = 1.5
	var torus := TorusMesh.new()
	torus.inner_radius = PULSE_RADIUS - 0.12
	torus.outer_radius = PULSE_RADIUS + 0.12
	torus.rings = 48
	torus.ring_segments = 8
	_pulse_ring = MeshInstance3D.new()
	_pulse_ring.mesh = torus
	_pulse_ring.position.y = 0.12
	_pulse_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var warning := StandardMaterial3D.new()
	warning.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warning.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning.albedo_color = Color(0.28, 0.95, 0.5, 0.8)
	warning.no_depth_test = true
	warning.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pulse_ring.material_override = warning
	add_child(_pulse_ring)
	_pulse_ring.hide()

func _set_emission(on: bool) -> void:
	if _reveal_t > 0.0 and not on: return
	for material in _materials:
		material.emission = Color(0.85, 1.0, 0.7) if on else Color(0.2, 0.55, 0.28)

func _update_animation(delta: float) -> void:
	if not model: return
	if anim: super._update_animation(delta)
	_flinch_cool = maxf(0.0, _flinch_cool - delta)
	if not alive:
		_pulse_ring.hide()
		return
	# It glides rather than planting its feet; keep the gait slow and deliberate.
	if anim and state == "walk" and anim.current_animation.begins_with("walk"):
		anim.speed_scale = lerpf(anim.speed_scale, clampf(_ground_speed / 3.0, 0.65, 1.3), minf(1.0, delta * 6.0))
	_hover_time += delta
	var drifting := clampf(Vector2(velocity.x, velocity.z).length() / 3.0, 0.0, 1.0)
	model.position.y = _model_y + sin(_hover_time * 2.2) * 0.08 + drifting * 0.035
	model.position.z = 0.12 * sin(_hover_time * 8.0) if state == "attack" else 0.0
	model.rotation.z = sin(_hover_time * 1.7) * 0.045
	if _pulse_t > 0.0:
		_pulse_ring.show()
		_pulse_ring.scale = Vector3.ONE * (0.94 + 0.06 * sin(_hover_time * 14.0))
	else:
		_pulse_ring.hide()

func damage(amount: float, direction: Vector3) -> void:
	super.damage(amount, direction)
	if alive:
		_stagger = 0.0
		_knock = Vector3.ZERO
		if state == "hit":
			if _flinch_cool > 0.0:
				play("walk")
			else:
				_hit_t = minf(_hit_t, 0.22)
				_flinch_cool = 2.5

func shove(_impulse: Vector3) -> void:
	pass

func _pulse_clear(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, target + Vector3.UP, 1 | 8, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _special_move(delta: float) -> bool:
	_pulse_cool = maxf(0.0, _pulse_cool - delta)
	if _pulse_t > 0.0:
		_pulse_t -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		agent.velocity = Vector3.ZERO
		if not is_on_floor(): velocity.y -= 20.0 * delta
		move_and_slide()
		if _pulse_t <= 0.0:
			_pulse_t = 0.0
			_pulse_serial += 1
			_pulse_cool = PULSE_COOLDOWN
			_pulse_hit()
		return true
	if _pulse_cool > 0.0 or not is_instance_valid(player) or not player.alive: return false
	var distance := Vector2(global_position.x - player.global_position.x, global_position.z - player.global_position.z).length()
	if distance < 3.5 or distance > 10.0 or not _pulse_clear(player.global_position): return false
	_pulse_t = PULSE_WINDUP
	play("pulse")
	Sfx.play_at(get_parent(), "growl", global_position, -2.0, 0.75)
	return true

func _pulse_hit() -> void:
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() and NetSession.world else [player]
	for actor in actors:
		if not is_instance_valid(actor) or not actor.alive: continue
		var offset: Vector3 = actor.global_position - global_position
		offset.y = 0.0
		if offset.length() > PULSE_RADIUS or not _pulse_clear(actor.global_position): continue
		actor.damage(PULSE_DAMAGE * damage_mul, global_position)
		if actor.has_method("shove"):
			actor.shove(offset.normalized() * 5.0 + Vector3.UP * 1.8)
	play("walk")

func boss_state() -> Array:
	return [_pulse_t, _pulse_serial]

func apply_boss_state(data: Array, _initial: bool) -> void:
	if data.size() < 2: return
	_pulse_t = float(data[0])
	_pulse_serial = int(data[1])

func die(direction: Vector3) -> void:
	super.die(direction)
	_pulse_t = 0.0
	if _pulse_ring: _pulse_ring.hide()
	if model and not anim:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(model, "rotation:z", 1.35, 0.65)
		tween.tween_property(model, "position:y", _model_y - height * 0.3, 0.65)

# Rig-less Meshy animals of the horde (26 Sep 2026): the farm dog and the zombie stag. Meshy rigs only
# humanoids, so the animal GLBs are static meshes fitted by height (Weapons._fit_height) and moved
# procedurally: a gallop bob and pitch scaled by the real ground speed, a lean into turns, a lunge on
# every bite, and a fall onto the side when they die. The dog runs the ordinary zombie loop (a fast melee
# body with a short reach); the stag adds a charge through _special_move: from 6 to charge_range metres
# with a clear line it lowers its head and runs straight at the player, rams whoever it reaches
# (ram damage plus a shove), rams gates and the hut for structure damage, and stands stunned for a
# moment after every charge. Bullets hit the movement capsule (no skinned hit volumes): no headshots on
# animals. Replicas run the same animation from the host's position.
# The model turns about its centre (the fitted mesh is centred on the node), so every pitch (gallop,
# lunge, the head-down charge) and roll (the lean into turns) would push one end of the body through the
# ground - the stag "sank into the ground" on every charge. _update_animation lifts the body by exactly
# the dip of the lowest end (sin of the tilt times the half length / width), so the hooves stay on the
# terrain and the far end rises instead.
class_name ZombieBeast
extends Zombie

var _gallop := 0.0
var _base_y := 0.0
var _half_length := 1.0    # half of the body's long horizontal extent, in metres at the current scale
var _half_width := 0.4
var _unit_bottom := 0.0    # the fitted mesh's extents per unit of model scale (the size variation
var _unit_half_length := 1.0   # of zombie.gd rescales the model after the fit)
var _unit_half_width := 0.4
var _lunge := 0.0
var _charge_t := 0.0
var _charge_dir := Vector3.ZERO
var _charge_cool := 0.4
var _stun_t := 0.0
var _fallen := false
var _turn := 0.0
var charges := 0        # statistics / tests
var rams := 0

func _fit_model() -> void:
	Weapons._fit_height(model, height)
	model.position.y += height * 0.5
	_base_y = model.position.y
	var bounds := _mesh_bounds()
	if bounds.size.y > 0.0:
		_unit_bottom = -bounds.position.y
		_unit_half_length = maxf(bounds.size.x, bounds.size.z) * 0.5
		_unit_half_width = minf(bounds.size.x, bounds.size.z) * 0.5
		_refit_scale()

# The resting height (the mesh's bottom exactly on the body's origin) and the half extents at the
# model's current scale.
func _refit_scale() -> void:
	var s := model.scale.y
	_half_length = _unit_half_length * s
	_half_width = _unit_half_width * s
	if _unit_bottom > 0.0:
		_base_y = _unit_bottom * s
		model.position.y = _base_y

# The model's AABB in its own space (the meshes hang directly under the GLB root, but walk the chain
# anyway so a nested export cannot shift the fit).
func _mesh_bounds() -> AABB:
	var merged := AABB()
	var first := true
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var n: Node = m
		while n != model and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var b: AABB = t * (m as MeshInstance3D).get_aabb()
		merged = b if first else merged.merge(b)
		first = false
	return merged

func play(name: String) -> void:
	if name == "attack": _lunge = 0.32
	super.play(name)

func attack_lead() -> float:
	return 0.18

func _build_head_look() -> void:
	pass

func _update_animation(delta: float) -> void:
	if not model: return
	if _unit_bottom > 0.0 and absf(_unit_bottom * model.scale.y - _base_y) > 0.001: _refit_scale()
	var p := global_position
	var moved := Vector2(p.x - _anim_last_pos.x, p.z - _anim_last_pos.z).length() / maxf(delta, 0.001)
	_anim_last_pos = p
	if moved > 40.0: moved = 0.0
	_ground_speed = lerpf(_ground_speed, moved, 1.0 - exp(-delta * 10.0))
	if not alive: return
	var pace: float = maxf(float(type.speed) * speed_mul, 0.1)
	var stride := clampf(_ground_speed / pace, 0.0, 1.4)
	_gallop += delta * (7.0 + 6.0 * stride)
	var bob := absf(sin(_gallop)) * 0.05 * stride * height
	var pitch := sin(_gallop) * 0.08 * stride
	var lunge := 0.0
	if _lunge > 0.0:
		_lunge = maxf(0.0, _lunge - delta)
		lunge = sin(clampf(1.0 - _lunge / 0.32, 0.0, 1.0) * PI)
	if _charge_t > 0.0: pitch -= 0.12   # head down for the ram
	var tilt := pitch - lunge * 0.22
	model.position.z = lunge * float(type.beast.get("lunge", 0.4))
	model.rotation.x = tilt
	# lean into turns: the yaw change per tick, smoothed
	var yaw := rotation.y
	var turn := wrapf(yaw - _turn, -PI, PI) / maxf(delta, 0.001)
	_turn = yaw
	model.rotation.z = lerpf(model.rotation.z, clampf(-turn * 0.06, -0.25, 0.25), minf(1.0, delta * 5.0))
	# lift the body by the dip of its lowest end: no hoof below the terrain, whatever the tilt
	model.position.y = _base_y + bob + sin(absf(tilt)) * _half_length + sin(absf(model.rotation.z)) * _half_width

func die(dir: Vector3) -> void:
	super.die(dir)
	if _fallen or not model: return
	_fallen = true
	_charge_t = 0.0
	var side := 1.0 if randf() < 0.5 else -1.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(model, "rotation:z", PI * 0.5 * side, 0.45).set_ease(Tween.EASE_IN)
	tween.tween_property(model, "rotation:x", 0.0, 0.45)
	# on its side the body rests on its flank: the centre ends up half a body width above the ground
	# (the legs stick out sideways, the way a fallen animal lies)
	tween.tween_property(model, "position:y", maxf(_half_width * 0.6, height * 0.16), 0.45).set_ease(Tween.EASE_IN)

# ---------------------------------------------------------------- the stag's charge (host only)
func _special_move(delta: float) -> bool:
	if not type.beast.has("charge"): return false
	if _stun_t > 0.0:
		_stun_t -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		agent.velocity = Vector3.ZERO
		if not is_on_floor(): velocity.y -= 20.0 * delta
		move_and_slide()
		return true
	if _charge_t > 0.0:
		_charge_t -= delta
		var speed := float(type.beast.charge) * horde_pace * frost_mul
		velocity.x = _charge_dir.x * speed
		velocity.z = _charge_dir.z * speed
		if not is_on_floor(): velocity.y -= 20.0 * delta
		rotation.y = atan2(_charge_dir.x, _charge_dir.z)
		move_and_slide()
		var actors: Array = NetSession.world.actors.values() if NetSession.is_host() and NetSession.world else [player]
		for actor in actors:
			if is_instance_valid(actor) and actor.alive and actor.global_position.distance_to(global_position) < float(type.reach) * 0.85:
				_ram_player(actor)
				return true
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			if collision.get_normal().y > 0.5: continue          # the ground
			var collider := collision.get_collider() as Node
			if collider == null: continue
			if collider.is_in_group("barricade"):
				var line := collider.get_parent()
				if line is Barricade and line.hp > 0.0:
					line.damage(float(type.beast.ram_structure) * damage_mul)
					rams += 1
				_end_charge(2.0)
				return true
			if collider.is_in_group("hut_body") and is_instance_valid(hut):
				hut.damage(float(type.beast.ram_structure) * damage_mul * 1.4)
				rams += 1
				_end_charge(2.2)
				return true
			if collider is Zombie: continue
			_end_charge(1.2)                                     # a wall, a tree, a tower
			return true
		if _charge_t <= 0.0: _end_charge(0.5)
		return true
	_charge_cool -= delta
	if not is_instance_valid(player) or not player.alive: return false
	var to := player.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if _charge_cool > 0.0:
		# between charges the stag wheels away to get a run-up instead of standing at the player's feet
		if d < 9.0 and state == "walk" and attack_t <= 0.0:
			var away := -to.normalized()
			var pace := float(type.speed) * speed_mul * frost_mul * horde_pace
			velocity.x = away.x * pace
			velocity.z = away.z * pace
			if not is_on_floor(): velocity.y -= 20.0 * delta
			rotation.y = lerp_angle(rotation.y, atan2(away.x, away.z), minf(1.0, delta * 4.0))
			move_and_slide()
			return true
		return false
	if state != "walk" or attack_t > 0.0: return false
	if d < 4.0 or d > float(type.beast.charge_range) or not _sees(player.global_position + Vector3.UP): return false
	_charge_dir = to.normalized()
	_charge_t = clampf(d / float(type.beast.charge) + 0.45, 0.8, 3.4)
	charges += 1
	play("attack")
	Sfx.play_at(get_parent(), "growl", global_position, -2.0, 0.72)
	return true

func _ram_player(actor: Player) -> void:
	actor.damage(float(type.beast.ram) * damage_mul, global_position)
	if actor.has_method("shove"): actor.shove(_charge_dir * 7.5 + Vector3.UP * 2.6)
	rams += 1
	_end_charge(1.4)

func _end_charge(stun: float) -> void:
	_charge_t = 0.0
	_stun_t = stun
	_charge_cool = float(type.beast.cooldown) + randf() * 2.0
	velocity.x = 0.0
	velocity.z = 0.0
	agent.velocity = Vector3.ZERO
	play("walk")

func charging() -> bool:
	return _charge_t > 0.0

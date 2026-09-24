class_name Titan
extends Zombie

const WINDUP := 2.4                     # long enough to run out of the ring
const BLAST_RADIUS := 8.5
const RAGE_THRESHOLD := 0.55
const RECOVERY := 1.6
const RAGE_RECOVERY := 1.0
var strike_point := Vector3.ZERO
var strike_phase := "arrival"
var strike_time := 2.8
var impact_serial := 0
var _shown_impact := 0
var _step_time := 0.0
var _stride_distance := 0.0
var _step_side := 1.0
var _cue_serial := 0
var _roar_time := 20.0
var _foot_heights: Array[float] = []
var _rage_announced := false
var warning: MeshInstance3D
var warning_material: StandardMaterial3D
var skeleton: Skeleton3D
var foot_bones: Array[int] = []
var _last_position := Vector3.ZERO
var _warning_center := Vector3.INF

func blast_radius() -> float:
	return float(type.get("blast_radius", BLAST_RADIUS))

func windup() -> float:
	return float(type.get("windup", WINDUP))

func recovery(rage: bool) -> float:
	return float(type.get("recovery", RECOVERY)) * (RAGE_RECOVERY / RECOVERY if rage else 1.0)

func _ready() -> void:
	super._ready()
	if model:
		model.scale = Vector3.ONE * height / 1.7
		for child in model.find_children("*", "Skeleton3D", true, false):
			skeleton = child
			for bone in ["LeftToeBase", "RightToeBase"]:
				var index := skeleton.find_bone(bone)
				if index >= 0: foot_bones.append(index)
			break
	for child in get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			child.shape.radius = clampf(height * 0.06, 0.65, 1.6)
	agent.radius = clampf(height * 0.065, 0.75, 1.7)
	agent.neighbor_distance = 16
	agent.avoidance_priority = 0.9
	agent.target_desired_distance = float(type.reach) * 0.4
	agent.path_desired_distance = 2.5
	# a 27 m body moves in slow motion: the walk cycle is stretched, the stride is what makes it look colossal
	if anim: anim.speed_scale = clampf(8.1 / height, 0.3, 0.85)
	warning_material = Barricade._marker_material(type.get("warning_color", Color(1, 0.22, 0.045)), 0.8)
	# Tactical warning stays legible through dense meadow grass.
	warning_material.no_depth_test = true
	warning_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := TorusMesh.new()
	ring.inner_radius = blast_radius() - 0.12
	ring.outer_radius = blast_radius() + 0.12
	ring.rings = 64
	ring.ring_segments = 8
	warning = DefenceTower.piece(self, ring, Vector3.ZERO, warning_material)
	warning.top_level = true
	warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warning.hide()
	# a dull red glow under the hood, visible across the whole meadow at night
	var glow := OmniLight3D.new()
	glow.light_color = type.get("warning_color", Color(1.0, 0.24, 0.1))
	glow.light_energy = 5.0
	glow.omni_range = height * 0.55
	glow.omni_attenuation = 1.5
	glow.shadow_enabled = false
	glow.position = Vector3(0, height * 0.9, height * 0.05)
	add_child(glow)
	# main places the actor after add_child; never roar from the world's origin.
	if not replica: call_deferred("_announce_arrival")

func _announce_arrival() -> void:
	if not alive or not is_inside_tree(): return
	_last_position = global_position
	_roar_time = 18.0 + float(appearance_seed % 9)
	emit_cue("arrival")

func emit_cue(kind: String, origin: Vector3 = Vector3.INF) -> void:
	if replica: return
	_cue_serial += 1
	var point := global_position if not origin.is_finite() else origin
	TitanPresence.for_scene(get_tree().current_scene).receive(kind, point, height, appearance_seed, _cue_serial)
	NetSession.titan_cue(kind, point, height, appearance_seed, _cue_serial)

func _process(delta: float) -> void:
	if not alive: return
	var contact := false
	# Contact correction is essential at this scale: a small rig offset becomes
	# a metre of floating feet when a human animation is applied to a giant.
	if skeleton and not foot_bones.is_empty():
		var lowest := INF
		if _foot_heights.size() != foot_bones.size(): _foot_heights.resize(foot_bones.size())
		for i in foot_bones.size():
			var index := foot_bones[i]
			var foot := skeleton.to_global(skeleton.get_bone_global_pose(index).origin)
			var above := foot.y - Map.ground_height(foot.x, foot.z)
			if above <= 0.25 and _foot_heights[i] > 0.25: contact = true
			_foot_heights[i] = above
			lowest = minf(lowest, above)
		model.position.y += clampf(0.08 - lowest, -height * 0.12, height * 0.12) * minf(1, delta * 12)
	var moved := Vector2(global_position.x - _last_position.x, global_position.z - _last_position.z).length()
	_last_position = global_position
	if replica: return # only the host creates footsteps; every peer hears the same event
	if not is_instance_valid(player) or (not player.active and not NetSession.enabled): return
	_step_time -= delta
	if strike_phase != "walk":
		_stride_distance = 0
		return
	if moved > 0.001 and moved < 2.0:
		_stride_distance += moved
		if _step_time <= 0 and ((contact and _stride_distance > 1.8) or _stride_distance > 6.2):
			_step_time = 1.0
			_stride_distance = 0
			_step_side *= -1
			var foot := global_position + global_basis.x * _step_side * 1.1
			emit_cue("step", Map.ground_pos(foot.x, foot.z))

func damage(amount: float, direction: Vector3) -> void:
	super.damage(amount, direction)
	# A giant cannot be stun-locked or pushed around by automatic fire.
	_stagger = 0
	_knock = Vector3.ZERO

func shove(_impulse: Vector3) -> void:
	pass

func _on_velocity_computed(safe: Vector3) -> void:
	if strike_phase != "walk": return
	super._on_velocity_computed(safe)

func die(direction: Vector3) -> void:
	if not alive: return
	emit_cue("death")
	super.die(direction)
	warning.hide()
	if anim: anim.speed_scale = 0.4
	# The body lands after the death animation starts, not at the killing bullet.
	if not replica:
		get_tree().create_timer(1.7, false).timeout.connect(func():
			if is_inside_tree(): emit_cue("collapse"))

func _physics_process(delta: float) -> void:
	update_rare_visual()
	if replica or not alive:
		super._physics_process(delta)
		update_warning()
		if impact_serial > _shown_impact:
			_shown_impact = impact_serial
			impact_effect()
		return
	if _flash_t > 0:
		_flash_t -= delta
		if _flash_t <= 0: _set_emission(false)
	if NetSession.enabled:
		var nearest := NetSession.nearest_player(global_position)
		if nearest: player = nearest
	if not is_instance_valid(player) or not player.alive or (not player.active and not NetSession.enabled): return
	_roar_time -= delta
	if strike_phase == "walk" and _roar_time <= 0:
		emit_cue("roar")
		_roar_time = 20.0 + float((appearance_seed + _cue_serial) % 11)
	var rage := hp < max_hp * RAGE_THRESHOLD
	if rage and not _rage_announced:
		_rage_announced = true
		emit_cue("rage")
		_roar_time = 22.0
	if strike_phase != "walk":
		velocity.x = 0
		velocity.z = 0
		agent.velocity = Vector3.ZERO
		if not is_on_floor(): velocity.y -= 20 * delta
		move_and_slide()
		strike_time -= delta
		if strike_time <= 0:
			if strike_phase == "windup":
				resolve_strike()
				strike_phase = "recovery"
				strike_time = recovery(rage)
			else:
				strike_phase = "walk"
				play("walk")
		update_warning()
		return
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0: return
	var player_priority := _nearby_player_priority(delta)
	_update_hunt(delta)
	var obstruction: Node3D
	var best := INF
	var path := _hunt_path if hunting else agent.get_current_navigation_path().slice(agent.get_current_navigation_path_index())
	if not hunting and is_instance_valid(siege_target) and siege_target.hp > 0:
		obstruction = siege_target
		best = obstruction.attack_point(global_position).distance_squared_to(global_position)
	for b in barricades:
		var blocking: bool = _blocks_hunt(b, path) if hunting else (b.intercepts(global_position, player.global_position, path) or (b == lane_bar and b.hp > 0 and b._local(global_position).y * b._local(player.global_position).y < 0))
		if blocking:
			var d: float = b.attack_point(global_position).distance_squared_to(global_position)
			if d < best:
				best = d
				obstruction = b
	for tower in get_tree().get_nodes_in_group("defence_towers"):
		# A roof turret sits behind the hut wall, where no slam reaches it: committed to one, the giant hammered forever.
		if tower.rooftop: continue
		var d: float = tower.global_position.distance_squared_to(global_position)
		if not hunting and tower.hp > 0 and d < 100 and d < best and obstruction == null:
			obstruction = tower
			best = d
	siege_target = obstruction
	if player_priority: obstruction = null
	var destination: Vector3 = obstruction.attack_point(global_position) if obstruction else player.global_position
	var direction := destination - global_position
	direction.y = 0
	rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(1, delta * 1.6))
	if direction.length() < float(type.reach):
		begin_strike(destination)
		return
	_repath -= delta
	if _repath <= 0:
		_repath = 0.6
		agent.target_position = destination
	var next := agent.get_next_path_position() - global_position
	next.y = 0
	var speed: float = type.speed * minf(speed_mul, 1.35) * frost_mul * (1.25 if rage else 1.0)
	agent.max_speed = speed
	agent.velocity = next.normalized() * speed
	if not is_on_floor(): velocity.y -= 20 * delta
	update_warning()

func begin_strike(destination: Vector3) -> void:
	var offset := destination - global_position
	offset.y = 0
	offset = offset.limit_length(float(type.reach) * 0.8)
	strike_point = Map.ground_pos(global_position.x + offset.x, global_position.z + offset.z)
	# Anchor an obstructed slam outside the first wall/defence, so a target in
	# the cabin cannot make the shockwave originate inside a closed building.
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, strike_point + Vector3.UP, 1 | 8, [get_rid()])
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty():
		var contact: Vector3 = obstruction.position - offset.normalized() * 0.15
		strike_point = Map.ground_pos(contact.x, contact.z)
	strike_phase = "windup"
	strike_time = windup()
	play("attack")
	velocity = Vector3.ZERO
	agent.velocity = Vector3.ZERO
	emit_cue("windup")
	update_warning()

func clear_strike_line(target_position: Vector3, target_body: CollisionObject3D = null, through_perimeter := false) -> bool:
	var q := PhysicsRayQueryParameters3D.create(strike_point + Vector3.UP * 1.0, target_position + Vector3.UP * 1.0, 1 | 8, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty(): return true
	if target_body != null and hit.collider == target_body: return true
	# A gate is part of the palisade. The slam lands at reach * 0.8, so unless the giant stands
	# exactly square to the gate the line grazes the neighbouring wall - which used to shield the
	# gate from every angled approach. Players, towers and huts stay protected by the wall.
	return through_perimeter and hit.collider.is_in_group("perimeter_wall")

func resolve_strike() -> void:
	impact_serial += 1
	_shown_impact = impact_serial
	emit_cue("slam", strike_point)
	impact_effect()
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() else [player]
	for actor: Player in actors:
		if actor.alive and actor.global_position.distance_to(strike_point) < blast_radius() and clear_strike_line(actor.global_position):
			actor.damage(float(type.damage) * damage_mul, strike_point)
	for b in barricades:
		if b.hp > 0 and b.attack_point(strike_point).distance_to(strike_point) < blast_radius() and clear_strike_line(b.attack_point(strike_point), b.body, true):
			b.damage(230.0 * damage_mul * float(type.get("structure_mul", 1.0)))
	for tower in get_tree().get_nodes_in_group("defence_towers"):
		if tower.hp > 0 and tower.attack_point(strike_point).distance_to(strike_point) < blast_radius() and clear_strike_line(tower.attack_point(strike_point), tower.body):
			tower.damage(240.0 * damage_mul * float(type.get("structure_mul", 1.0)))
	for drone: AttackDrone in get_tree().get_nodes_in_group("attack_drones"):
		if drone.hp > 0 and drone.global_position.distance_to(strike_point) < blast_radius() and clear_strike_line(drone.global_position,drone):
			drone.damage(float(type.damage)*damage_mul)
	for door: Door in hut_doors:
		if door.hp > 0 and door.attack_point(strike_point).distance_to(strike_point) < blast_radius() and clear_strike_line(door.attack_point(strike_point), door.body):
			door.damage(230.0 * damage_mul * float(type.get("structure_mul", 1.0)))
	if is_instance_valid(hut) and hut.hp > 0 and hut.attack_point(strike_point).distance_to(strike_point) < blast_radius():
		hut.damage(440.0 * damage_mul * float(type.get("structure_mul", 1.0)))

func update_warning() -> void:
	if not warning: return
	warning.visible = alive and strike_phase == "windup"
	if warning.visible:
		if not strike_point.is_equal_approx(_warning_center):
			_warning_center = strike_point
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in 72:
				var corners: Array[Vector3] = []
				for sample in [[i, -0.13], [i + 1, -0.13], [i + 1, 0.13], [i, 0.13]]:
					var angle := float(sample[0]) / 72.0 * TAU
					var radius := blast_radius() + float(sample[1])
					var x := strike_point.x + cos(angle) * radius
					var z := strike_point.z + sin(angle) * radius
					corners.append(Map.ground_pos(x, z) - strike_point + Vector3.UP * 0.15)
				for index in [0, 1, 2, 0, 2, 3]:
					surface.set_normal(Vector3.UP)
					surface.add_vertex(corners[index])
			warning.mesh = surface.commit()
		warning.global_position = strike_point
		warning_material.albedo_color.a = 0.5 + 0.45 * (1 - clampf(strike_time / windup(), 0, 1))

func impact_effect() -> void:
	var dust := CPUParticles3D.new()
	dust.amount = 48
	dust.lifetime = 1.5
	dust.one_shot = true
	dust.explosiveness = 1
	dust.direction = Vector3.UP
	dust.spread = 80
	dust.initial_velocity_min = 2
	dust.initial_velocity_max = 7
	dust.gravity = Vector3(0, -4, 0)
	dust.scale_amount_min = 0.15
	dust.scale_amount_max = 0.6
	var mesh := SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = DefenceTower.material(Color(0.27, 0.23, 0.16))
	dust.mesh = mesh
	get_parent().add_child(dust)
	dust.global_position = strike_point + Vector3.UP * 0.15
	dust.emitting = true
	get_tree().create_timer(2.0, false).timeout.connect(dust.queue_free)

func boss_state() -> Array:
	return [strike_phase, strike_time, strike_point, impact_serial]

func apply_boss_state(data: Array, initial: bool) -> void:
	strike_phase = data[0]
	strike_time = data[1]
	strike_point = data[2]
	impact_serial = data[3]
	if initial: _shown_impact = impact_serial

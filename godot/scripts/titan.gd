class_name Titan
extends Zombie

const WINDUP := 2.4                     # long enough to run out of the ring
const BLAST_RADIUS := 8.5
const RAGE_THRESHOLD := 0.55
const RECOVERY := 1.6
const RAGE_RECOVERY := 1.0
# Phases (26 Sep 2026): below ARM_LOSS of its health the giant loses its right arm (bones collapse, a stump,
# blood) and from then on tears trees out of the ground and throws them (thrown_tree.gd) every THROW_MIN..
# THROW_MAX seconds at a player THROW_RANGE metres away; below LEG_LOSS it loses its left leg and crawls:
# the rig plays its "crawl" clip (Meshy library 340, hands and knees; every titan skin carries it since
# 26 Sep 2026), the ground contact keeps hands and knees on the terrain the way the feet are kept while
# walking, it moves at CRAWL_SPEED of its pace, and its slam becomes a shorter, quicker sweep. A rig
# without the clip keeps its walk cycle at crawl pace. (The first version tilted the whole model forward
# and dropped it by a third of its height, which read as the giant sinking into the ground.) Both phases
# are replicated through boss_state (lost mask) and the throw RPC.
const ARM_LOSS := 0.65
const LEG_LOSS := 0.35
const LOST_ARM := 1
const LOST_LEG := 2
const THROW_MIN := 9.0
const THROW_MAX := 15.0
const THROW_RANGE := Vector2(14.0, 80.0)
const THROW_WINDUP := 1.3
const CRAWL_SPEED := 0.5
const CRAWL_BONES := ["LeftToeBase", "RightToeBase", "LeftHand", "RightHand", "LeftLeg", "RightLeg"]
var lost := 0
var crawling := false
var throw_serial := 0
var _shown_throw := 0
var throw_from := Vector3.ZERO
var throw_to := Vector3.ZERO
var _throw_t := 12.0
var throws := 0
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
var crawl_bones: Array[int] = []   # feet, hands and knees: whatever touches the ground on all fours
var _last_position := Vector3.ZERO
var _warning_center := Vector3.INF

func blast_radius() -> float:
	return float(type.get("blast_radius", BLAST_RADIUS)) * (0.75 if crawling else 1.0)

func windup() -> float:
	return float(type.get("windup", WINDUP)) * (0.6 if crawling else 1.0)

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
			for bone in CRAWL_BONES:
				var index := skeleton.find_bone(bone)
				if index >= 0: crawl_bones.append(index)
			break
	for child in get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			child.shape.radius = clampf(height * 0.06, 0.65, 1.6)
	agent.radius = clampf(height * 0.065, 0.75, 1.7)
	agent.neighbor_distance = 16
	agent.avoidance_priority = 0.9
	agent.target_desired_distance = float(type.reach) * 0.4
	agent.path_desired_distance = 2.5
	# a 27 m body moves in slow motion: the stride matching in Zombie scales the walk cycle by the model
	# scale, so the feet of a giant cover real ground and the stride is what makes it look colossal
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
	# a metre of floating feet when a human animation is applied to a giant. On all fours the
	# hands and knees are the contact, so the crawl neither floats nor sinks.
	var contact_bones := crawl_bones if crawling and not crawl_bones.is_empty() else foot_bones
	if skeleton and not contact_bones.is_empty():
		var lowest := INF
		if _foot_heights.size() != contact_bones.size(): _foot_heights.resize(contact_bones.size())
		for i in contact_bones.size():
			var index := contact_bones[i]
			var foot := skeleton.to_global(skeleton.get_bone_global_pose(index).origin)
			var above := foot.y - Map.ground_height(foot.x, foot.z)
			if above <= 0.25 and _foot_heights[i] > 0.25: contact = true
			_foot_heights[i] = above
			lowest = minf(lowest, above)
		# walking, the correction is smoothed (the feet take turns); on all fours the lowest of toes, knees
		# and hands changes from frame to frame, and a smoothed correction let the giant dip up to 0.8 m
		# into the ground or float at the start of the crawl - it follows exactly instead
		var follow := 1.0 if crawling and contact_bones == crawl_bones else minf(1, delta * 12)
		model.position.y += clampf(0.08 - lowest, -height * 0.12, height * 0.12) * follow
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
	if alive and not replica:
		if hp <= max_hp * ARM_LOSS and not (lost & LOST_ARM): _lose(LOST_ARM, direction)
		if hp <= max_hp * LEG_LOSS and not (lost & LOST_LEG): _lose(LOST_LEG, direction)

# ---------------------------------------------------------------- phases
func _lose(bit: int, direction: Vector3) -> void:
	lost |= bit
	_apply_lost(bit, direction)
	_roar("rage")
	_roar_time = 22.0
	if bit == LOST_ARM: _throw_t = 3.5
	var scene := get_tree().current_scene
	if scene and scene.has_method("titan_phase"): scene.titan_phase(self, bit)

# the visible side of a lost limb, host and replicas alike: bones collapse, a dark stump, blood
func _apply_lost(bit: int, direction: Vector3) -> void:
	if not model: return
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if not rig: return
	var key := "RightArm" if bit == LOST_ARM else "LeftLeg"
	var part := "right_arm" if bit == LOST_ARM else "left_leg"
	var root := rig.find_bone(LIMBS[key][0])
	var joint: Vector3 = rig.global_transform * rig.get_bone_global_pose(root).origin if root >= 0 else global_position + Vector3.UP * height * 0.7
	_cut_part(rig, part, key, direction, false)
	if root >= 0:
		var attachment := BoneAttachment3D.new()
		attachment.name = "Stump_" + part
		attachment.bone_name = rig.get_bone_name(root)
		rig.add_child(attachment)
		var cap := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var world_scale: float = maxf(rig.global_transform.basis.get_scale().y, 0.0001)
		sphere.radius = height * 0.028 / world_scale
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		cap.mesh = sphere
		cap.material_override = ZombieGore.stump_material()
		attachment.add_child(cap)
	var scene := get_tree().current_scene
	if scene and "weapons" in scene and scene.weapons and scene.weapons.has_method("_blood"):
		for i in 8:
			var spurt := get_tree().create_timer(0.1 + i * 0.3)
			spurt.timeout.connect(func():
				if not is_instance_valid(self) or not is_instance_valid(rig): return
				var at: Vector3 = rig.global_transform * rig.get_bone_global_pose(root).origin if root >= 0 else joint
				scene.weapons._blood(at, Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)).normalized()))
	Sfx.play_at(get_parent(), "head_burst", joint, 0.0, 0.55, 12.0, 120.0)
	if bit == LOST_LEG: _begin_crawl()

func _begin_crawl() -> void:
	crawling = true
	_foot_heights.clear()
	if model: model.rotation.x = 0.0
	# the gait re-picks itself on the next walk tick (_gait -> "crawl"); a swing in progress finishes first
	if anim and alive and state == "walk" and has_crawl_clip():
		clip = "crawl"
		anim.play("crawl", 0.35)
		anim.speed_scale = 0.6
	if warning: warning.hide()

# On all fours there is no standing idle and no standing roar: a still crawler slows its crawl instead.
func _may_idle() -> bool:
	return not (crawling and has_crawl_clip())

func _fixed_gait_speed(name: String) -> float:
	var base := super._fixed_gait_speed(name)
	if name == "crawl": return base * clampf(_ground_speed / 1.6, 0.15, 1.0)
	return base

func has_crawl_clip() -> bool:
	return anim != null and anim.has_animation("crawl")

# On all fours the locomotion clip is the crawl; everything else (slam, roar, death) keeps its clip.
func _gait() -> String:
	if crawling and has_crawl_clip(): return "crawl"
	return super._gait()

# The crawl clip carries hardly any foot travel, so the stride matching of the walk would race it:
# a crawl plays at a fixed, heavy pace scaled by the giant's size.
func _natural_speed(name: String) -> float:
	if name == "crawl": return 0.0
	return super._natural_speed(name)

func can_throw() -> bool:
	return alive and (lost & LOST_ARM) != 0

# The throw: a wind-up, then the tree leaves the hand towards where the player will be.
func _begin_throw(target: Player) -> void:
	strike_phase = "throw"
	strike_time = THROW_WINDUP
	play("attack")
	velocity = Vector3.ZERO
	agent.velocity = Vector3.ZERO
	var to := target.global_position - global_position
	to.y = 0.0
	rotation.y = atan2(to.x, to.z)
	emit_cue("windup")
	throw_to = target.global_position + Vector3(target.velocity.x, 0.0, target.velocity.z) * 1.4

func _release_tree() -> void:
	throw_serial += 1
	throws += 1
	throw_from = global_position + Vector3.UP * height * (0.45 if crawling else 0.78) + global_basis.x * -height * 0.16 + global_basis.z * height * 0.12
	var scene := get_tree().current_scene
	if scene and scene.has_method("titan_throw"): scene.titan_throw(self, throw_from, throw_to)
	_throw_t = randf_range(THROW_MIN, THROW_MAX)

# The slam of the attack clip lands exactly when the wind-up ends and the strike resolves.
func attack_lead() -> float:
	return windup()

# Roar and rage: the scream clip roots the giant for its length, the strike loop resumes afterwards.
func _roar(cue: String) -> void:
	emit_cue(cue)
	# the scream clip is a standing roar; on all fours only the voice carries it
	if crawling and has_crawl_clip(): return
	if not anim or not anim.has_animation("scream") or strike_phase != "walk": return
	play("scream")
	strike_phase = "roar"
	strike_time = clampf(clip_seconds("scream"), 1.0, 3.5)
	velocity.x = 0
	velocity.z = 0
	agent.velocity = Vector3.ZERO

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
	_update_animation(delta)
	_roar_time -= delta
	if strike_phase == "walk" and _roar_time <= 0:
		_roar("roar")
		_roar_time = 20.0 + float((appearance_seed + _cue_serial) % 11)
	var rage := hp < max_hp * RAGE_THRESHOLD
	if rage and not _rage_announced:
		_rage_announced = true
		_roar("rage")
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
			elif strike_phase == "throw":
				_release_tree()
				strike_phase = "recovery"
				strike_time = 1.1
			else:
				strike_phase = "walk"
				play("walk")
		update_warning()
		return
	if lost & LOST_ARM:
		_throw_t -= delta
		if _throw_t <= 0.0:
			var to := player.global_position - global_position
			to.y = 0.0
			if to.length() >= THROW_RANGE.x and to.length() <= THROW_RANGE.y and _sees(player.global_position + Vector3.UP):
				_begin_throw(player)
				return
			_throw_t = 2.0
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
	var speed: float = type.speed * minf(speed_mul, 1.35) * frost_mul * (1.25 if rage else 1.0) * horde_pace * (CRAWL_SPEED if crawling else 1.0)
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
	return [strike_phase, strike_time, strike_point, impact_serial, lost, throw_serial]

func apply_boss_state(data: Array, initial: bool) -> void:
	strike_phase = data[0]
	strike_time = data[1]
	strike_point = data[2]
	impact_serial = data[3]
	if initial: _shown_impact = impact_serial
	if data.size() > 4 and int(data[4]) != lost:
		var mask := int(data[4])
		for bit in [LOST_ARM, LOST_LEG]:
			if mask & bit and not (lost & bit):
				lost |= bit
				_apply_lost(bit, Vector3.UP)
	if data.size() > 5:
		throw_serial = int(data[5])
		if initial: _shown_throw = throw_serial

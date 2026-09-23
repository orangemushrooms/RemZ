class_name Earthworm
extends Zombie

# Host owns movement, target locking and damage. Clients render the same phase
# and clip time; joining a running encounter never replays old impacts or roars.
const WARNING_TIME := 3.0
const EMERGE_TIME := 1.8
const EXPOSED_TIME := 7.0
const WINDUP_TIME := 2.6
const RECOVERY_TIME := 3.5
const DIVE_TIME := 1.8
const BURROW_TIME := 9.0
const TRAIL_COUNT := 18
var phase := "arrival"
var phase_time := WARNING_TIME
var phase_length := WARNING_TIME
var strike_point := Vector3.ZERO
var destination := Vector3.ZERO
var impact_serial := 0
var cue_serial := 0
var _shown_impact := 0
var _heard_cue := 0
var _roar_time := 21.0
var _trail_time := 0.0
var _trail_index := 0
var _trail: Array[MeshInstance3D] = []
var _trail_age: Array[float] = []
var warning: MeshInstance3D
var warning_material: StandardMaterial3D
var _warning_center := Vector3.INF
var _hitbox_enabled := true
var _voice: AudioStreamPlayer3D
var _crater: Node3D

func radius() -> float:
	return 6.0 if net_kind == "earthworm_ancient" else 4.8

func burial_depth() -> float:
	# The ancient's curved tail stays below the surface; only the continuous
	# rising body is exposed. Its silhouette must not read as an extra limb.
	return height * (0.24 if net_kind == "earthworm_ancient" else 0.12)

func targetable() -> bool:
	return alive and phase in ["emerge", "exposed", "windup", "recovery", "dive"]

func status_label() -> String:
	if not targetable(): return "UNDERGROUND"
	return "ATTACKING" if phase == "windup" else "VULNERABLE"

func aim_point() -> Vector3:
	# The tail is buried even while attacking; towers aim at exposed mid-body.
	for volume in _shot_volumes:
		if volume.bone_name == "spine_10": return volume.to_global(volume.center)
	return global_position + Vector3.UP * height * 0.55

func _ready() -> void:
	super._ready()
	agent.avoidance_enabled = false
	collision_layer = 0
	collision_mask = 0
	if model: model.scale = Vector3.ONE * height / 1.7
	if anim: anim.speed_scale = 1.0
	warning_material = Barricade._marker_material(Color(1.0, 0.52, 0.12), 0.85)
	warning_material.no_depth_test = true
	warning_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	warning = MeshInstance3D.new()
	warning.material_override = warning_material
	warning.top_level = true
	warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(warning)
	var soil := DefenceTower.material(Color(0.16, 0.105, 0.055))
	soil.roughness = 1.0
	var clod := SphereMesh.new()
	clod.radial_segments = 10
	clod.rings = 5
	clod.material = soil
	for i in TRAIL_COUNT:
		var mound := MeshInstance3D.new()
		mound.mesh = clod
		mound.top_level = true
		mound.hide()
		add_child(mound)
		_trail.append(mound)
		_trail_age.append(10.0)
	_crater = Node3D.new()
	add_child(_crater)
	for i in 16:
		var clump := MeshInstance3D.new()
		clump.mesh = clod
		var angle := TAU * i / 16.0
		var spread := height * 0.13
		clump.position = Vector3(cos(angle) * spread, 0.1, sin(angle) * spread)
		clump.scale = Vector3(1.6, 0.7 + 0.3 * sin(i * 2.5), 1.3)
		_crater.add_child(clump)
	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = 48.0
	_voice.max_distance = 240.0
	_voice.volume_db = -7.0
	# Use the existing compressed/limited boss bus when the main scene owns it.
	if AudioServer.get_bus_index("Titans") >= 0: _voice.bus = "Titans"
	add_child(_voice)
	_sync_visuals()
	if not replica: call_deferred("_arrival")

func _arrival() -> void:
	if not alive: return
	strike_point = global_position
	destination = global_position
	_roar_time = 20.0 + float(appearance_seed % 9)
	_emit_cue()
	_sync_visuals()

func _emit_cue() -> void:
	cue_serial += 1
	_play_cue()

func _play_cue() -> void:
	_heard_cue = cue_serial
	# A voice belongs to its worm: long samples cannot pile up on the same actor.
	if not _voice or _voice.playing: return
	_voice.stream = Sfx._file("Earthworm_%d" % (1 + (appearance_seed + cue_serial) % 3))
	_voice.pitch_scale = 0.92 if net_kind == "earthworm_ancient" else 1.0
	_voice.play()

func _set_phase(next: String, duration: float) -> void:
	phase = next
	phase_time = duration
	phase_length = duration
	var clip := "walk"
	match phase:
		"burrow": clip = "burrow"
		"emerge": clip = "emerge"
		"windup": clip = "attack"
		"recovery": clip = "recovery"
		"dive": clip = "dive"
		"death": clip = "death"
	play(clip)
	if anim and anim.has_animation(clip):
		anim.speed_scale = anim.get_animation(clip).length / duration if phase in ["emerge", "windup", "recovery", "dive"] else 1.0
	_sync_visuals()

func _physics_process(delta: float) -> void:
	if not alive:
		super._physics_process(delta)
		if model: model.position.y = -burial_depth() - minf(height, dead_t * 0.18)
		return
	update_rare_visual()
	if _flash_t > 0:
		_flash_t -= delta
		if _flash_t <= 0: _set_emission(false)
	if replica:
		global_position = global_position.lerp(net_position, 1.0 - exp(-delta * 16))
		rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-delta * 16))
		phase_time = maxf(0, phase_time - delta)
	else:
		if NetSession.is_host():
			var nearest := NetSession.nearest_player(global_position)
			if nearest: player = nearest
		if not is_instance_valid(player) or not player.alive or (not player.active and not NetSession.enabled): return
		_roar_time -= delta
		if _roar_time <= 0:
			_emit_cue()
			_roar_time = 24.0 + float((appearance_seed + cue_serial) % 12)
		phase_time -= delta
		if phase == "burrow":
			var direction := destination - global_position
			direction.y = 0
			var step := minf(direction.length(), float(type.speed) * speed_mul * maxf(0.65, frost_mul) * delta)
			if direction.length() > 0.05:
				global_position += direction.normalized() * step
				global_position.y = Map.ground_height(global_position.x, global_position.z) + 0.05
				rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(1, delta * 3))
			if direction.length() < 0.5: phase_time = 0
		if phase_time <= 0: _advance_phase()
	_sync_visuals()
	_update_trail(delta)

func _advance_phase() -> void:
	match phase:
		"arrival", "warning":
			# Emerging is spectacle, not an unannounced damaging strike.
			_set_phase("emerge", EMERGE_TIME)
			impact_serial += 1
			_impact_effect()
		"emerge": _set_phase("exposed", EXPOSED_TIME)
		"exposed":
			strike_point = _choose_strike()
			_set_phase("windup", WINDUP_TIME)
		"windup":
			resolve_strike()
			_set_phase("recovery", RECOVERY_TIME)
		"recovery": _set_phase("dive", DIVE_TIME)
		"dive":
			destination = _choose_destination()
			_set_phase("burrow", BURROW_TIME)
		"burrow":
			# A timed burrow always surfaces, even if the target is far away.
			strike_point = global_position
			_set_phase("warning", WARNING_TIME)

func safe_surface(point: Vector3) -> bool:
	return surface_clear(self, perimeter, point)

static func surface_clear(context: Node3D, ring: Perimeter, point: Vector3) -> bool:
	var p := Vector2(point.x, point.z)
	if not Map.BOUNDS.grow(-6).has_point(p) or Map.in_building(p.x, p.y, 5.0): return false
	if ring and ring.excludes_spawn(p): return false
	if Map.ground_normal(p.x, p.y).y < 0.82: return false
	# Check the girth above terrain, including trees, towers, doors and walls.
	var shape := SphereShape3D.new()
	shape.radius = 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = Map.ground_pos(p.x, p.y) + Vector3.UP * 2.8
	query.collision_mask = 1 | 8 | 16
	if context is CollisionObject3D: query.exclude = [context.get_rid()]
	return context.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _choose_destination() -> Vector3:
	var desired := player.global_position
	if perimeter and perimeter.contains(Vector2(desired.x, desired.z)):
		var best := INF
		for b: Barricade in barricades:
			var center := Vector2(b.center.x, b.center.z)
			var outward := (center - perimeter.centroid()).normalized()
			var p := Map.ground_pos(center.x + outward.x * 6.0, center.y + outward.y * 6.0)
			var score := global_position.distance_squared_to(p)
			if score < best and safe_surface(p):
				best = score
				desired = p
	for ring in [0.0, 6.0, 12.0, 20.0]:
		for i in 12:
			var angle := TAU * float(i) / 12.0 + float(appearance_seed % 6)
			var p := Map.ground_pos(desired.x + cos(angle) * ring, desired.z + sin(angle) * ring)
			if safe_surface(p) and _safe_tunnel(p): return p
	return global_position

func _safe_tunnel(end: Vector3) -> bool:
	# Never tunnel under the hut/camp and surface through their far side. The
	# validated samples also guarantee the timeout can emerge safely en route.
	var steps := maxi(1, ceili(global_position.distance_to(end) / 2.0))
	for i in range(1, steps + 1):
		if not safe_surface(global_position.lerp(end, float(i) / steps)): return false
	return true

func _choose_strike() -> Vector3:
	var target := player.global_position
	if target.distance_to(global_position) > float(type.reach):
		var best := INF
		for b: Barricade in barricades:
			if b.hp <= 0: continue
			var point := b.attack_point(global_position)
			var distance := point.distance_squared_to(global_position)
			if distance < best:
				best = distance
				target = point
	var offset := target - global_position
	offset.y = 0
	offset = offset.limit_length(float(type.reach))
	if offset.length() > 0.1: rotation.y = atan2(offset.x, offset.z)
	return Map.ground_pos(global_position.x + offset.x, global_position.z + offset.z)

func _clear_line(target: Vector3, body: CollisionObject3D = null, gate := false) -> bool:
	# Cast from the worm, not the far side of a wall at the marked strike point.
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, target + Vector3.UP, 1 | 8, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (body != null and hit.collider == body) or (gate and hit.collider.is_in_group("perimeter_wall"))

func resolve_strike() -> void:
	if replica or not alive: return
	impact_serial += 1
	_impact_effect()
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() else [player]
	for actor: Player in actors:
		if actor.alive and actor.global_position.distance_to(strike_point) < radius() and _clear_line(actor.global_position):
			actor.damage(float(type.damage) * damage_mul, strike_point)
	for b: Barricade in barricades:
		var point := b.attack_point(strike_point)
		if b.hp > 0 and point.distance_to(strike_point) < radius() and _clear_line(point, b.body, true): b.damage(140.0 * damage_mul)
	for tower in get_tree().get_nodes_in_group("defence_towers"):
		var point: Vector3 = tower.attack_point(strike_point)
		if tower.hp > 0 and point.distance_to(strike_point) < radius() and _clear_line(point, tower.body): tower.damage(140.0 * damage_mul)
	if is_instance_valid(hut) and hut.hp > 0:
		var point := hut.attack_point(strike_point)
		if point.distance_to(strike_point) < radius() and _clear_line(point): hut.damage(200.0 * damage_mul)

func _sync_visuals() -> void:
	var exposed := targetable()
	if exposed != _hitbox_enabled:
		_hitbox_enabled = exposed
		for area in _hitboxes: area.collision_layer = HITBOX_LAYER if exposed else 0
	if model:
		model.visible = exposed or not alive
		var fraction := clampf(phase_time / maxf(0.01, phase_length), 0, 1)
		model.position.y = -burial_depth() + (-height * fraction if phase == "emerge" else (-height * (1.0 - fraction) if phase == "dive" else 0.0))
	if _crater: _crater.visible = phase != "burrow"
	if not warning: return
	warning.visible = alive and phase in ["arrival", "warning", "windup"]
	if not warning.visible: return
	if not strike_point.is_equal_approx(_warning_center):
		_warning_center = strike_point
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 64:
			var corners: Array[Vector3] = []
			for pair in [[i, -0.16], [i + 1, -0.16], [i + 1, 0.16], [i, 0.16]]:
				var angle := TAU * float(pair[0]) / 64.0
				var r := radius() + float(pair[1])
				corners.append(Map.ground_pos(strike_point.x + cos(angle) * r, strike_point.z + sin(angle) * r) - strike_point + Vector3.UP * 0.2)
			for vertex in [0, 1, 2, 0, 2, 3]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(corners[vertex])
		warning.mesh = surface.commit()
	warning.global_position = strike_point
	warning_material.albedo_color = Color(1, 0.16 if phase == "windup" else 0.6, 0.04, 0.65 + 0.3 * sin(phase_time * 8))

func _update_trail(delta: float) -> void:
	_trail_time -= delta
	for i in _trail.size():
		_trail_age[i] += delta
		_trail[i].visible = _trail_age[i] < 3.5
		if _trail[i].visible: _trail[i].scale.y = maxf(0.04, 1.0 - _trail_age[i] / 3.5)
	if phase not in ["burrow", "warning", "arrival"] or _trail_time > 0: return
	_trail_time = 0.14
	var mound := _trail[_trail_index]
	_trail_age[_trail_index] = 0
	var side := sin(float(_trail_index) * 2.3) * 1.3
	mound.global_position = global_position + global_basis.x * side
	mound.global_position.y = Map.ground_height(mound.global_position.x, mound.global_position.z) + 0.12
	mound.scale = Vector3(2.4, 0.9, 2.2)
	mound.show()
	_trail_index = (_trail_index + 1) % TRAIL_COUNT

func _impact_effect() -> void:
	_shown_impact = impact_serial
	var dust := CPUParticles3D.new()
	dust.amount = 50
	dust.lifetime = 1.5
	dust.one_shot = true
	dust.explosiveness = 1
	dust.direction = Vector3.UP
	dust.spread = 70
	dust.initial_velocity_min = 4
	dust.initial_velocity_max = 11
	dust.gravity = Vector3(0, -10, 0)
	dust.scale_amount_min = 0.15
	dust.scale_amount_max = 0.65
	dust.mesh = _trail[0].mesh
	get_parent().add_child(dust)
	dust.global_position = strike_point + Vector3.UP * 0.3
	dust.emitting = true
	get_tree().create_timer(2.0, false).timeout.connect(dust.queue_free)
	Sfx.play_at(get_parent(), "crash", strike_point, -10, 0.75, 25, 110)
	if is_instance_valid(player):
		player.add_tremor(0.35 * maxf(0, 1.0 - player.global_position.distance_to(strike_point) / 65.0), 1.2)

func damage(amount: float, direction: Vector3) -> void:
	if not targetable(): return
	super.damage(amount, direction)
	_stagger = 0
	_knock = Vector3.ZERO

func shove(_impulse: Vector3) -> void:
	pass

func _on_velocity_computed(_safe: Vector3) -> void:
	pass

func die(direction: Vector3) -> void:
	if not alive: return
	super.die(direction)
	phase = "death"
	if anim: anim.speed_scale = 1.0
	if warning: warning.hide()
	if model:
		model.show()
		model.position.y = -burial_depth()
	for mound in _trail: mound.hide()
	if _voice: _voice.stop()

func boss_state() -> Array:
	return [phase, phase_time, phase_length, strike_point, destination, impact_serial, cue_serial]

func apply_boss_state(data: Array, initial: bool) -> void:
	if data.size() < 7: return
	var changed := phase != str(data[0])
	phase = data[0]
	phase_time = data[1]
	phase_length = data[2]
	strike_point = data[3]
	destination = data[4]
	impact_serial = data[5]
	cue_serial = data[6]
	if initial:
		_shown_impact = impact_serial
		_heard_cue = cue_serial
	elif alive:
		if cue_serial > _heard_cue: _play_cue()
		if impact_serial > _shown_impact: _impact_effect()
	if changed or initial:
		var remaining := phase_time
		_set_phase(phase, phase_length)
		phase_time = remaining
		if anim and anim.current_animation != "": anim.seek((phase_length - phase_time) * anim.speed_scale, true)
	_sync_visuals()

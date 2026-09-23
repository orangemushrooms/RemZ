# Hand grenade: thrown RigidBody3D, explodes after a fuse with damage falloff, flash, smoke and shake.
class_name Grenade
extends RigidBody3D

const FUSE := 2.6
const RADIUS := 7.0
const DAMAGE := 260.0

var zombies_root: Node3D
var player: Player
var _t := 0.0
var _done := false
var replica := false
var owner_peer := 1

func setup(scene: PackedScene, zr: Node3D, p: Player) -> void:
	zombies_root = zr
	player = p
	if is_instance_valid(p): owner_peer = p.peer_id
	mass = 0.4
	continuous_cd = true
	collision_layer = 1
	collision_mask = 1 | 2 | 8
	if replica:
		freeze = true
		collision_layer = 0
		collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.06
	cs.shape = sph
	add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	physics_material_override = pm
	if not replica:
		# metallic tick on every bounce (rate limited)
		contact_monitor = true
		max_contacts_reported = 2
		body_entered.connect(_on_bounce)
	if scene:
		var model: Node3D = scene.instantiate()
		add_child(model)
		Weapons._fit_height(model, 0.12)
	else:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.32, 0.18)
		mi.material_override = mat
		add_child(mi)

var _bounce_t := 0.0

func _on_bounce(_body: Node) -> void:
	if _done or _t - _bounce_t < 0.15: return
	_bounce_t = _t
	Sfx.play_at(get_tree().current_scene, "grenade_bounce", global_position, -12.0)

func _physics_process(delta: float) -> void:
	if replica: return
	_t += delta
	if _t >= FUSE and not _done:
		_explode()

func _explode() -> void:
	_done = true
	var pos := global_position
	# damage
	if not replica:
		get_tree().current_scene.hunting.blast(pos, RADIUS, DAMAGE, owner_peer)
		for z in zombies_root.get_children():
			if z is Zombie and z.alive:
				var d: float = z.global_position.distance_to(pos)
				if d < RADIUS and _visible_from(pos, z.global_position + Vector3.UP):
					var f := 1.0 - (d / RADIUS) * 0.8
					z.last_headshot = false
					z.killer_weapon = "grenade"
					z.killer_peer = owner_peer
					z.damage(DAMAGE * f, (z.global_position - pos).normalized())
		if NetSession.enabled: NetSession.explosion(pos)
	if is_instance_valid(player):
		var pd := player.global_position.distance_to(pos)
		if not replica and pd < RADIUS * 0.7 and _visible_from(pos, player.global_position + Vector3.UP):
			player.damage(40.0 * (1.0 - pd / (RADIUS * 0.7)), pos)
	var viewer: Player = NetSession.game.player if NetSession.enabled and is_instance_valid(NetSession.game) else player
	if is_instance_valid(viewer):
		var distance := viewer.global_position.distance_to(pos)
		viewer.wobble = maxf(viewer.wobble, clampf(1.6 - distance / 20.0, 0.0, 1.5))
	Sfx.play_at(get_tree().current_scene, "boom", pos, 2.0)
	explosion_visuals(get_tree().current_scene, pos)
	queue_free()

# Fireball and smoke materials, built once. Fresh ParticleProcessMaterials and StandardMaterial3Ds
# per explosion made Godot regenerate and recompile all four shaders whenever no other explosion was
# still burning - a hitch on every grenade and every graviton shot.
static var _parts: Dictionary = {}

static func _explosion_parts() -> Dictionary:
	if not _parts.is_empty(): return _parts
	var fm := ParticleProcessMaterial.new()
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fm.emission_sphere_radius = 0.5
	fm.direction = Vector3(0, 1, 0)
	fm.spread = 180.0
	fm.initial_velocity_min = 3.0
	fm.initial_velocity_max = 9.0
	fm.gravity = Vector3(0, 1.0, 0)
	fm.damping_min = 4.0
	fm.damping_max = 8.0
	fm.scale_min = 1.5
	fm.scale_max = 3.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	grad.add_point(0.3, Color(1.0, 0.4, 0.05, 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(0.2, 0.2, 0.2, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	fm.color_ramp = gt
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Foliage._soft_dot()
	q.material = mat
	var smm := ParticleProcessMaterial.new()
	smm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smm.emission_sphere_radius = 1.0
	smm.direction = Vector3(0, 1, 0)
	smm.spread = 60.0
	smm.initial_velocity_min = 1.0
	smm.initial_velocity_max = 4.0
	smm.gravity = Vector3(0, 0.6, 0)
	smm.damping_min = 1.0
	smm.damping_max = 2.0
	smm.scale_min = 2.0
	smm.scale_max = 4.0
	var sg := Gradient.new()
	sg.set_color(0, Color(0.25, 0.22, 0.2, 0.7))
	sg.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	smm.color_ramp = sgt
	var sq := QuadMesh.new()
	sq.size = Vector2(1, 1)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_texture = Foliage._soft_dot()
	sq.material = smat
	_parts = {"fire": fm, "fire_quad": q, "smoke": smm, "smoke_quad": sq}
	return _parts

static func explosion_visuals(parent: Node3D, pos: Vector3) -> void:
	var parts := _explosion_parts()
	# fireball
	var fire := GPUParticles3D.new()
	fire.process_material = parts.fire
	fire.draw_pass_1 = parts.fire_quad
	fire.amount = 80
	fire.lifetime = 0.9
	fire.one_shot = true
	fire.explosiveness = 0.95
	parent.add_child(fire)
	fire.global_position = pos
	fire.emitting = true
	# smoke
	var smoke := GPUParticles3D.new()
	smoke.process_material = parts.smoke
	smoke.draw_pass_1 = parts.smoke_quad
	smoke.amount = 40
	smoke.lifetime = 4.0
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	parent.add_child(smoke)
	smoke.global_position = pos
	smoke.emitting = true
	# flash light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.4)
	light.light_energy = 40.0
	light.omni_range = 25.0
	parent.add_child(light)
	light.global_position = pos + Vector3(0, 0.8, 0)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_callback(light.queue_free)
	parent.get_tree().create_timer(5.0, false).timeout.connect(fire.queue_free)
	parent.get_tree().create_timer(6.0, false).timeout.connect(smoke.queue_free)

func _visible_from(origin: Vector3, target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.08, target, 1 | 8)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

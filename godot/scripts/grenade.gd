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

func setup(scene: PackedScene, zr: Node3D, p: Player) -> void:
	zombies_root = zr
	player = p
	mass = 0.4
	collision_layer = 1
	collision_mask = 1 | 2 | 8
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.06
	cs.shape = sph
	add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	physics_material_override = pm
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

func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= FUSE and not _done:
		_explode()

func _explode() -> void:
	_done = true
	var pos := global_position
	# damage
	for z in zombies_root.get_children():
		if z is Zombie and z.alive:
			var d: float = z.global_position.distance_to(pos)
			if d < RADIUS:
				var f := 1.0 - (d / RADIUS) * 0.8
				z.damage(DAMAGE * f, (z.global_position - pos).normalized())
	var pd := player.global_position.distance_to(pos)
	if pd < RADIUS * 0.7:
		player.damage(40.0 * (1.0 - pd / (RADIUS * 0.7)))
	player.wobble = maxf(player.wobble, clampf(1.6 - pd / 20.0, 0.3, 1.5))
	Sfx.play_at(get_tree().current_scene, "boom", pos, 2.0)
	# fireball
	var fire := GPUParticles3D.new()
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
	fire.process_material = fm
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
	fire.draw_pass_1 = q
	fire.amount = 80
	fire.lifetime = 0.9
	fire.one_shot = true
	fire.explosiveness = 0.95
	get_tree().current_scene.add_child(fire)
	fire.global_position = pos
	fire.emitting = true
	# smoke
	var smoke := GPUParticles3D.new()
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
	smoke.process_material = smm
	var sq := QuadMesh.new()
	sq.size = Vector2(1, 1)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_texture = Foliage._soft_dot()
	sq.material = smat
	smoke.draw_pass_1 = sq
	smoke.amount = 40
	smoke.lifetime = 4.0
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	get_tree().current_scene.add_child(smoke)
	smoke.global_position = pos
	smoke.emitting = true
	# flash light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.4)
	light.light_energy = 40.0
	light.omni_range = 25.0
	get_tree().current_scene.add_child(light)
	light.global_position = pos + Vector3(0, 0.8, 0)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_callback(light.queue_free)
	get_tree().create_timer(5.0).timeout.connect(fire.queue_free)
	get_tree().create_timer(6.0).timeout.connect(smoke.queue_free)
	queue_free()

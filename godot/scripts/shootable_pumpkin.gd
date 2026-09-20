extends StaticBody3D

var broken := false
var model: Node3D
var lamp: OmniLight3D

func setup(prop: Node3D) -> void:
	model = prop
	model.add_to_group("render_dynamic")
	collision_layer = 32
	collision_mask = 0
	set_meta("shootable_pumpkin", true)
	var bounds := ViewmodelHands.weapon_bounds(model)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bounds.size
	shape.shape = box
	shape.position = bounds.get_center()
	add_child(shape)

func shoot() -> bool:
	if broken or NetSession.is_client(): return false
	shatter()
	get_tree().current_scene.achievements.event("pumpkins")
	return true

func shatter(effects: bool = true) -> void:
	if broken: return
	broken = true
	collision_layer = 0
	model.hide()
	if lamp:
		lamp.remove_from_group("day_night_lamps")
		lamp.hide()
	if not effects: return
	var particles := CPUParticles3D.new()
	particles.amount = 18
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 80.0
	particles.initial_velocity_min = 1.4
	particles.initial_velocity_max = 3.0
	particles.gravity = Vector3(0, -9.8, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.04, 0.07)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.32, 0.025)
	mesh.material = material
	particles.mesh = mesh
	get_tree().current_scene.add_child(particles)
	particles.global_position = global_position + Vector3.UP * 0.2
	particles.emitting = true
	Sfx.play_at(self, "wood", particles.global_position, -8.0, 1.4)
	get_tree().create_timer(1.2).timeout.connect(particles.queue_free)

extends Node
# Bounded surface-attached decals. No extra collision geometry or gameplay damage.
const LIMIT := 192
var marks: Array[Decal] = []
var next := 0
var texture: ImageTexture

static func hit(scene: Node, result: Dictionary) -> void:
	if result.is_empty(): return
	var surface = result.get("collider")
	if not surface is StaticBody3D and not surface is RigidBody3D: return
	if surface is Breakable or surface.get_meta("hunt_id", -1) != -1: return
	var normal: Vector3 = result.normal
	if normal.length_squared() < 0.5: return
	NetSession.bullet_impact(result.position, normal)

static func show(scene: Node, position: Vector3, normal: Vector3) -> void:
	if not is_instance_valid(scene) or not scene is Node3D: return
	var query := PhysicsRayQueryParameters3D.create(position + normal * 0.06, position - normal * 0.08, 1)
	var surface_hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(query)
	if surface_hit.is_empty(): return
	var surface = surface_hit.collider
	if not surface is StaticBody3D and not surface is RigidBody3D: return
	var manager = scene.get_node_or_null("BulletImpacts")
	if not manager:
		manager = load("res://scripts/bullet_impacts.gd").new()
		manager.name = "BulletImpacts"
		scene.add_child(manager)
	manager.place(surface, position, normal.normalized())

func place(surface: Node3D, position: Vector3, normal: Vector3) -> void:
	if not texture: texture = make_texture()
	var mark := Decal.new()
	if marks.size() < LIMIT:
		marks.append(mark)
	else:
		if is_instance_valid(marks[next]): marks[next].queue_free()
		marks[next] = mark
		next = (next + 1) % LIMIT
	surface.add_child(mark)
	mark.texture_albedo = texture
	mark.cull_mask = 1
	mark.albedo_mix = 1.0
	mark.normal_fade = 0.65
	mark.upper_fade = 0.15
	mark.lower_fade = 0.15
	mark.distance_fade_enabled = true
	mark.distance_fade_begin = 45.0
	mark.distance_fade_length = 15.0
	var width := randf_range(0.085, 0.135)
	mark.size = Vector3(width, 0.045, width)
	var tangent := normal.cross(Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP).normalized()
	mark.global_transform = Transform3D(Basis(tangent, normal, tangent.cross(normal)).rotated(normal, randf() * TAU), position + normal * 0.008)

static func make_texture() -> ImageTexture:
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 83017
	for y in 96:
		for x in 96:
			var p := (Vector2(x, y) - Vector2(47.5, 47.5)) / 47.5
			var angle := p.angle()
			var radius := p.length() / (0.78 + 0.07 * sin(angle * 7.0) + 0.045 * sin(angle * 13.0))
			var grain := rng.randf_range(0.75, 1.2)
			var alpha := (1.0 - smoothstep(0.65, 1.0, radius)) * 0.85
			var shade := 0.27 * grain
			if radius < 0.34:
				shade = 0.025 * grain
				alpha = 0.98
			elif radius < 0.55:
				shade = (0.4 + p.y * 0.32) * grain
				alpha = 0.9
			image.set_pixel(x, y, Color(shade, shade * 0.94, shade * 0.84, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

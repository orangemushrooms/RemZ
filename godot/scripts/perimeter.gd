# Each gate builds its nearest palisade runs. Unbuilt or destroyed sections have
# neither visible wood nor collision; only built sections enter the navigation bake.
class_name Perimeter
extends Node3D

# ring corners between the gates, clockwise seen from above (x east, z south). ["gate", id, "a" / "b"] is a gate
# endpoint: "a" = centre + dir * half_len, "b" = centre - dir * half_len of the barricade slot with that id.
# Keep tools/plot_perimeter.py (overlay on roads and terrain) in sync when moving a corner.
const CORNERS: Array = [
	["gate", "w", "a"], [-2, -37], [12, -34], [24, -22], [32, -6], [36, 12], [38, 30], [39, 42],
	["gate", "ne", "b"], ["gate", "ne", "a"], [22, 64],
	["gate", "e", "a"], ["gate", "e", "b"], [-6, 69],
	["gate", "s", "a"], ["gate", "s", "b"], [-26, 56], [-30, 40], [-30, 20], [-31, 0], [-30, -18],
	["gate", "w", "b"],
]
const LOG_SPACING := 0.3
const LOG_RADIUS := 0.14
const LOG_HEIGHT := 2.5
const POST_RADIUS := 0.24
const POST_HEIGHT := 3.1
const WALL_HEIGHT := 2.6          # collision box height
const PIECE := 4.0                # collision box length along the wall
const SPAWN_CLEARANCE := 2.0      # keep an entire enemy outside walls and gate openings

var points: PackedVector2Array     # ring polygon in the xz plane, gate endpoints included
var gate_edge: Array[bool] = []    # edge i (points[i] -> points[i + 1]) is a gate opening
var walls: Array = []              # [Vector2 a, Vector2 b] per wall run
var length := 0.0                  # metres of wall (gates excluded)
var body: StaticBody3D
var log_count := 0
var sections: Array[Node3D] = []
var _section_bodies: Array[StaticBody3D] = []
var _barriers: Array = []
var _section: Node3D
var _gate_filter := -1
var _wall_sections: Dictionary = {}
signal layout_changed

func setup(barricades: Array) -> void:
	var by_id := {}
	for b in barricades:
		by_id[str(b.slot["id"])] = b
	points = PackedVector2Array()
	var kinds: Array[String] = []
	for e in CORNERS:
		if e[0] is String:
			var b: Barricade = by_id[str(e[1])]
			var s := 1.0 if str(e[2]) == "a" else -1.0
			points.append(Vector2(b.center.x, b.center.z) + b.dir2 * b.half_len * s)
			kinds.append("gate:" + str(e[1]))
		else:
			points.append(Vector2(float(e[0]), float(e[1])))
			kinds.append("corner")
	gate_edge.resize(points.size())
	for i in points.size():
		var j := (i + 1) % points.size()
		gate_edge[i] = kinds[i] != "corner" and kinds[i] == kinds[j]
		if not gate_edge[i]:
			walls.append([points[i], points[j]])
			length += points[i].distance_to(points[j])
	_barriers = barricades
	var all_walls := walls.duplicate()
	for barrier: Barricade in barricades:
		_section = Node3D.new()
		_section.name = "Palisade_" + str(barrier.slot.id)
		add_child(_section)
		sections.append(_section)
		walls = []
		for wall in all_walls:
			var midpoint: Vector2 = (wall[0] + wall[1]) * 0.5
			var closest: Barricade = barricades[0]
			for candidate: Barricade in barricades:
				if candidate.distance_to_line(Map.ground_pos(midpoint.x, midpoint.y)) < closest.distance_to_line(Map.ground_pos(midpoint.x, midpoint.y)):
					closest = candidate
			if closest == barrier:
				walls.append(wall)
				_wall_sections[wall[0]] = sections.size() - 1
		_gate_filter = -1
		for i in points.size():
			if gate_edge[i] and kinds[i] == "gate:" + str(barrier.slot.id): _gate_filter = i
		_build_collision()
		_section_bodies.append(body)
		_build_visuals()
		barrier.changed.connect(_sync_sections)
	walls = all_walls
	_sync_sections()

func is_wall_built(start: Vector2) -> bool:
	return _wall_sections.has(start) and sections[_wall_sections[start]].visible

func _sync_sections() -> void:
	var changed := false
	for i in sections.size():
		var built: bool = _barriers[i].level > 0 and _barriers[i].hp > 0.0
		var collider := _section_bodies[i]
		if sections[i].visible == built and collider.is_in_group("navsource") == built: continue
		sections[i].visible = built
		collider.collision_layer = 1 if built else 0
		if built: collider.add_to_group("navsource")
		else: collider.remove_from_group("navsource")
		changed = true
	if changed: layout_changed.emit()

func contains(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, points)

func excludes_spawn(p: Vector2) -> bool:
	# The camp stays free of surprise spawns even before construction or after a breach.
	# Enemies may enter through gaps, but must originate outside the complete ring.
	if contains(p): return true
	for i in points.size():
		var closest := Geometry2D.get_closest_point_to_segment(p, points[i], points[(i + 1) % points.size()])
		if p.distance_squared_to(closest) <= SPAWN_CLEARANCE * SPAWN_CLEARANCE: return true
	return false

func centroid() -> Vector2:
	var c := Vector2.ZERO
	for p in points:
		c += p
	return c / maxf(1.0, points.size())

# inward unit normal of the wall run a -> b
func inside_normal(a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	if (centroid() - (a + b) * 0.5).dot(n) < 0.0:
		n = -n
	return n

func _build_collision() -> void:
	body = StaticBody3D.new()
	body.name = "PalisadeBody"
	# The gates sit inside this wall, so a boss slam against it must reach them (titan.gd).
	body.add_to_group("perimeter_wall")
	body.collision_layer = 1
	body.collision_mask = 0
	_section.add_child(body)
	for w in walls:
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		var n := ceili(a.distance_to(b) / PIECE)
		for k in n:
			var pa := a.lerp(b, float(k) / n)
			var pb := a.lerp(b, float(k + 1) / n)
			_box(Map.ground_pos(pa.x, pa.y), Map.ground_pos(pb.x, pb.y), 0.5, WALL_HEIGHT)
	# gate posts narrow the opening a little on both ends
	for i in points.size():
		if gate_edge[i] and i == _gate_filter:
			for p in [points[i], points[(i + 1) % points.size()]]:
				var g := Map.ground_pos(p.x, p.y)
				_box(g + Vector3(0, 0, -0.25), g + Vector3(0, 0, 0.25), 0.5, POST_HEIGHT)

func _box(a: Vector3, b: Vector3, width: float, height: float) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, a.distance_to(b) + 0.1)
	shape.shape = box
	var dir := (b - a).normalized()
	shape.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), (a + b) * 0.5 + Vector3.UP * (height * 0.5 - 0.15))
	body.add_child(shape)

func _build_visuals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bark := Foliage.pbr("bark", 1.0)
	bark.uv1_scale = Vector3(1.0, 3.0, 1.0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.26, 0.16)
	wood.roughness = 0.92
	# trees standing in the wall line plug the gap themselves: no log within 0.6 m of a trunk
	var bbox := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bbox = bbox.expand(p)
	bbox = bbox.grow(2.0)
	var trunks: PackedVector2Array = []
	for t in Map.TREES:
		var tp := Vector2(float(t[0]), float(t[1]))
		if bbox.has_point(tp):
			trunks.append(tp)
	var logs: Array[Transform3D] = []
	var tips: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	for w in walls:
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		var run := a.distance_to(b)
		var d := (b - a) / run
		var n := inside_normal(a, b)
		var count := int(run / LOG_SPACING)
		for k in count + 1:
			var p := a + d * minf(run, k * LOG_SPACING + LOG_SPACING * 0.5) + n * rng.randf_range(-0.02, 0.02)
			var blocked := false
			for tp in trunks:
				if tp.distance_squared_to(p) < 0.36:
					blocked = true
					break
			if blocked:
				continue
			var h := LOG_HEIGHT + rng.randf_range(-0.14, 0.14)
			var g := Map.ground_pos(p.x, p.y)
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			basis = Basis(Vector3(d.x, 0, d.y), rng.randf_range(-0.03, 0.03)) * Basis(Vector3(n.x, 0, n.y), rng.randf_range(-0.02, 0.02)) * basis
			var foot := g - Vector3.UP * 0.08
			logs.append(Transform3D(basis * Basis.from_scale(Vector3(1, h, 1)), foot + basis.y * h * 0.5))
			tips.append(Transform3D(basis, foot + basis.y * (h + 0.15)))
		# two rails on the inside face, one per <= 3 m piece
		var pieces := ceili(run / 3.0)
		for k in pieces:
			var pa := a.lerp(b, float(k) / pieces)
			var pb := a.lerp(b, float(k + 1) / pieces)
			var ga := Map.ground_pos(pa.x, pa.y)
			var gb := Map.ground_pos(pb.x, pb.y)
			var inset := Vector3(n.x, 0, n.y) * LOG_RADIUS * 0.7
			for y in [1.0, 1.9]:
				rails.append(beam_transform(ga + inset + Vector3.UP * y, gb + inset + Vector3.UP * y, 0.09, 0.14, 0.05))
	log_count += logs.size()
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = LOG_RADIUS * 0.82
	log_mesh.bottom_radius = LOG_RADIUS
	log_mesh.height = 1.0
	log_mesh.radial_segments = 9
	log_mesh.rings = 1
	_multimesh("Logs", log_mesh, logs, bark, true)
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = LOG_RADIUS * 0.82
	tip_mesh.height = 0.32
	tip_mesh.radial_segments = 9
	tip_mesh.rings = 1
	_multimesh("Tips", tip_mesh, tips, bark, true)
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3.ONE
	_multimesh("Rails", rail_mesh, rails, wood, false)
	# gate posts and lintels
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = POST_RADIUS * 0.9
	post_mesh.bottom_radius = POST_RADIUS
	post_mesh.height = 1.0
	post_mesh.radial_segments = 12
	post_mesh.rings = 1
	var posts: Array[Transform3D] = []
	var lintels: Array[Transform3D] = []
	for i in points.size():
		if not gate_edge[i] or i != _gate_filter:
			continue
		var ga := Map.ground_pos(points[i].x, points[i].y)
		var gb := Map.ground_pos(points[(i + 1) % points.size()].x, points[(i + 1) % points.size()].y)
		for g in [ga, gb]:
			posts.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, POST_HEIGHT, 1)), g + Vector3.UP * (POST_HEIGHT * 0.5 - 0.1)))
		var la := ga + Vector3.UP * (POST_HEIGHT - 0.35)
		var lb := gb + Vector3.UP * (POST_HEIGHT - 0.35)
		lintels.append(beam_transform(la, lb, 0.28, 0.28, 0.5))
	_multimesh("Posts", post_mesh, posts, bark, true)
	_multimesh("Lintels", rail_mesh, lintels, wood, true)

static func beam_transform(a: Vector3, b: Vector3, width: float, height: float, extra_length := 0.0) -> Transform3D:
	# Scale the box in its own axes before rotating it along the endpoints.
	var basis := Basis.looking_at((b - a).normalized(), Vector3.UP) * Basis.from_scale(Vector3(width, height, a.distance_to(b) + extra_length))
	return Transform3D(basis, (a + b) * 0.5)

func _multimesh(name: String, mesh: Mesh, transforms: Array[Transform3D], material: Material, shadows: bool) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = name
	inst.multimesh = mm
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_section.add_child(inst)

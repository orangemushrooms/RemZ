# Torn conifer roots: shared, deterministic geometry for the titan's projectile.
# Three merged material surfaces keep the branched silhouette cheap to render.
class_name TreeRootBall
extends RefCounted

const VARIANTS := 4
static var _meshes: Dictionary = {}
static var _bark: StandardMaterial3D
static var _earth: StandardMaterial3D
static var _wood: StandardMaterial3D

static func variant(origin: Vector3) -> int:
	return posmod(int(round(origin.x * 7.0)) + int(round(origin.z * 11.0)), VARIANTS)

static func make(origin: Vector3) -> MeshInstance3D:
	var id := variant(origin)
	if not _meshes.has(id): _meshes[id] = _build(id)
	var roots := MeshInstance3D.new()
	roots.name = "TornRoots"
	roots.mesh = _meshes[id]
	roots.set_meta("root_variant", id)
	return roots

static func _materials() -> void:
	if _bark: return
	_bark = Foliage.pbr("bark", 1.0, Color(0.64, 0.49, 0.34))
	_bark.vertex_color_use_as_albedo = true
	_bark.metallic_specular = 0.1
	_earth = Foliage.pbr("ph_forestfloor", 1.7, Color(0.40, 0.29, 0.19))
	_earth.vertex_color_use_as_albedo = true
	_earth.uv1_triplanar = true
	_earth.metallic_specular = 0.05
	_wood = Foliage.pbr("planks", 2.0, Color(0.68, 0.48, 0.27))
	_wood.vertex_color_use_as_albedo = true
	_wood.metallic_specular = 0.08
	_wood.cull_mode = BaseMaterial3D.CULL_DISABLED

static func _surface(material: Material) -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	return surface

static func _build(id: int) -> ArrayMesh:
	_materials()
	var rng := RandomNumberGenerator.new()
	rng.seed = 80231 + id * 3191
	var bark := _surface(_bark)
	var earth := _surface(_earth)
	var wood := _surface(_wood)
	var noise := FastNoiseLite.new()
	noise.seed = 9001 + id
	noise.frequency = 3.8
	noise.fractal_octaves = 3
	# Soil caught between the roots, with broken clods along the torn underside.
	_clod(earth, Vector3(0, -0.58, 0), Vector3(1.00, 0.56, 0.94), noise, rng, 32, 16)
	for i in 17:
		var angle := rng.randf() * TAU
		var spread := rng.randf_range(0.5, 1.0)
		var center := Vector3(cos(angle) * spread, rng.randf_range(-0.95, -0.40), sin(angle) * spread)
		var size := Vector3(rng.randf_range(0.20, 0.40), rng.randf_range(0.15, 0.32), rng.randf_range(0.20, 0.37))
		_clod(earth, center, size, noise, rng, 10, 6)
	# The buttress meets the tree's trunk and spreads into unequal root arms.
	_root(bark, wood, [Vector3(0, 0.45, 0), Vector3(0.04, 0.04, 0), Vector3(-0.04, -0.40, 0)], [0.22, 0.38, 0.50], 14, rng, false)
	for i in 9:
		var angle := TAU * i / 9.0 + rng.randf_range(-0.20, 0.20)
		var out := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-out.z, 0, out.x)
		var length := rng.randf_range(1.65, 2.35)
		var start := out * 0.16 + Vector3.UP * rng.randf_range(-0.05, 0.2)
		var shoulder := out * 0.70 + Vector3.DOWN * rng.randf_range(0.24, 0.42)
		var bend := out * length * 0.72 + Vector3.DOWN * rng.randf_range(0.5, 0.9) + side * rng.randf_range(-0.25, 0.25)
		var tip := out * length + Vector3.DOWN * rng.randf_range(0.8, 1.3) + side * rng.randf_range(-0.3, 0.3)
		var points := _curve(start, shoulder, bend, tip, 11)
		var radius := rng.randf_range(0.20, 0.31)
		var radii: Array = []
		for j in points.size(): radii.append(lerpf(radius, 0.055, pow(float(j) / (points.size() - 1), 0.75)))
		_root(bark, wood, points, radii, 10, rng, true)
		for fork in 3:
			var at := 4 + fork * 2
			var base: Vector3 = points[at]
			var dir := (out * 0.45 + side * (-1.0 if fork % 2 == 0 else 1.0)).normalized()
			var reach := rng.randf_range(0.45, 0.9)
			var end := base + dir * reach + Vector3.DOWN * rng.randf_range(0.25, 0.5)
			var branch := _curve(base, base + dir * 0.2, end - dir * 0.12 + Vector3.UP * 0.16, end, 7)
			var widths: Array = []
			for j in branch.size(): widths.append(lerpf(float(radii[at]) * 0.52, 0.018, float(j) / (branch.size() - 1)))
			_root(bark, wood, branch, widths, 7, rng, fork == 1)
			# Thin torn fibers curl from the secondary roots instead of forming a
			# regular star or a solid disk around the soil.
			var fiber_start: Vector3 = branch[4]
			var fiber_end := fiber_start + dir * rng.randf_range(0.2, 0.5) + Vector3.DOWN * rng.randf_range(0.35, 0.65)
			var fiber := _curve(fiber_start, fiber_start + side * 0.1, fiber_end - dir * 0.15, fiber_end, 6)
			_root(bark, wood, fiber, [0.022, 0.020, 0.016, 0.012, 0.007, 0.002], 5, rng, false)
	# The torn underside faces the player once the tree falls. Exposed rootlets
	# cross the soil there, breaking up the otherwise bare central earth mass.
	for i in 14:
		var angle := rng.randf() * TAU
		var out := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-out.z, 0, out.x)
		var offset := rng.randf_range(-0.45, 0.45)
		var points: Array = []
		var radii: Array = []
		for j in 13:
			var t := float(j) / 12.0
			var point := out * lerpf(-0.88, 0.98, t) + side * (offset + sin(t * TAU + angle) * 0.09)
			point.y = -0.62 - 0.61 * sqrt(maxf(0.04, 1.0 - point.length_squared())) - sin(t * PI) * 0.06
			points.append(point)
			radii.append(lerpf(rng.randf_range(0.035, 0.065), 0.008, t))
		_root(bark, wood, points, radii, 6, rng, false)
	var mesh := ArrayMesh.new()
	for surface in [earth, bark, wood]:
		surface.generate_tangents()
		surface.commit(mesh)
	return mesh

static func _curve(a: Vector3, b: Vector3, c: Vector3, d: Vector3, count: int) -> Array:
	var points: Array = []
	for i in count:
		var t := float(i) / (count - 1)
		var u := 1.0 - t
		points.append(a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t)
	return points

static func _root(bark: SurfaceTool, wood: SurfaceTool, points: Array, radii: Array, sides: int, rng: RandomNumberGenerator, torn: bool) -> void:
	var tone := rng.randf_range(0.72, 1.15)
	bark.set_color(Color(tone, tone, tone))
	Trees._tube(bark, points, radii, sides, 0.65, rng.randf() * 2.0)
	if not torn: return
	var end: Vector3 = points.back()
	var direction: Vector3 = (end - points[-2]).normalized()
	var across := direction.cross(Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := across.cross(direction).normalized()
	var radius := float(radii.back())
	wood.set_color(Color(1.0, 0.91, 0.76))
	# Uneven exposed end grain plus a few torn splinters, never a flat saw cut.
	for i in sides:
		var a := TAU * i / sides
		var b := TAU * (i + 1) / sides
		var p := end + (across * cos(a) + up * sin(a)) * radius
		var q := end + (across * cos(b) + up * sin(b)) * radius
		_triangle(wood, end - direction * radius * 0.35, p, q, direction)
	for i in 3:
		var angle := rng.randf() * TAU
		var offset := (across * cos(angle) + up * sin(angle)) * radius * 0.65
		var splinter := end + offset + direction * radius * rng.randf_range(0.8, 2.2)
		_triangle(wood, end + offset - across * radius * 0.18, end + offset + across * radius * 0.18, splinter, up)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.set_uv(Vector2(point.x, point.z))
		surface.add_vertex(point)

static func _clod(surface: SurfaceTool, center: Vector3, size: Vector3, noise: FastNoiseLite, rng: RandomNumberGenerator, sides: int, rings: int) -> void:
	var rows: Array = []
	var tone := rng.randf_range(0.70, 1.20)
	for row in rings + 1:
		var latitude := PI * row / rings
		var vertices: Array = []
		for column in sides + 1:
			var longitude := TAU * column / sides
			var unit := Vector3(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude))
			var point := center + unit * size
			var warp := 1.0 + noise.get_noise_3dv(point * 2.5) * 0.32 + sin(longitude * 5.0 + center.x * 8.0) * sin(latitude) * 0.09
			vertices.append(center + unit * size * warp)
		rows.append(vertices)
	for row in rings:
		for column in sides:
			var a: Vector3 = rows[row][column]
			var b: Vector3 = rows[row][column + 1]
			var c: Vector3 = rows[row + 1][column]
			var d: Vector3 = rows[row + 1][column + 1]
			for tri in [[a, b, c], [b, d, c]]:
				var normal: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if normal.is_zero_approx(): continue
				# Godot's front face is clockwise. Keep normals pointing out.
				surface.set_color(Color(tone, tone, tone))
				if normal.dot((tri[0] + tri[1] + tri[2]) / 3.0 - center) > 0:
					_triangle(surface, tri[0], tri[2], tri[1], normal)
				else:
					_triangle(surface, tri[0], tri[1], tri[2], -normal)

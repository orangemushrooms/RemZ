# Local tactical overlay. Ground-following ribbons remain legible over grass and uneven terrain.
extends Node3D

var drawing: MeshInstance3D
var caption: Label3D
var _signature := ""
var shown_radius := 0.0

func _ready() -> void:
	add_to_group("render_dynamic")
	drawing = MeshInstance3D.new()
	drawing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drawing)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	drawing.material_override = mat
	caption = Label3D.new()
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.no_depth_test = true
	caption.font_size = 42
	caption.outline_size = 10
	caption.pixel_size = 0.009
	add_child(caption)
	hide()

func display(center: Vector3, radius: float, yaw: float, manual: bool, invalid := false) -> void:
	show()
	caption.visible = not manual
	var signature := str([center.snapped(Vector3.ONE * 0.1), radius, snappedf(yaw, 0.01), manual, invalid])
	if signature == _signature: return
	_signature = signature
	shown_radius = radius
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var color := Color(1, 0.28, 0.15, 0.8) if invalid else Color(0.95, 0.74, 0.3, 0.85)
	# Bright automatic sector, dashed remainder for manual 360-degree operation. A yaw turns -Z to
	# (-sin, -cos), the way DefenceTower.can_see measures it; with +sin the sector showed mirrored.
	for i in 180:
		var a := -PI + TAU * i / 180.0
		var b := -PI + TAU * (i + 1) / 180.0
		var in_sector := absf((a + b) * 0.5) <= DefenceTower.HALF_ARC
		if not manual and not in_sector and i % 3 != 0: continue
		var tint := color
		if not manual and not in_sector: tint.a = 0.23
		_strip(mesh, center + Vector3(-sin(a + yaw), 0, -cos(a + yaw)) * radius,
			center + Vector3(-sin(b + yaw), 0, -cos(b + yaw)) * radius, 0.18, tint)
	if not manual:
		for angle in [-DefenceTower.HALF_ARC, DefenceTower.HALF_ARC]:
			var forward := Vector3(-sin(angle + yaw), 0, -cos(angle + yaw))
			for i in ceili(radius):
				_strip(mesh, center + forward * i, center + forward * minf(i + 1, radius), 0.09, color)
	for angle in [0.0, -PI * 0.5, PI * 0.5, PI]:
		var forward := Vector3(-sin(angle + yaw), 0, -cos(angle + yaw))
		_strip(mesh, center + forward * (radius - 0.7), center + forward * (radius + 0.7), 0.12, color)
	mesh.surface_end()
	drawing.mesh = mesh
	var front := center + Vector3(-sin(yaw), 0, -cos(yaw)) * radius
	caption.position = Map.ground_pos(front.x, front.z) + Vector3.UP * 1.2
	caption.text = "MAX. %d m" % roundi(radius)
	caption.modulate = color

func _strip(mesh: ImmediateMesh, a: Vector3, b: Vector3, width: float, tint: Color) -> void:
	var side := Vector3(b.z - a.z, 0, a.x - b.x).normalized() * width * 0.5
	for point in [a-side, a+side, b+side, a-side, b+side, b-side]:
		mesh.surface_set_color(tint)
		mesh.surface_add_vertex(Map.ground_pos(point.x, point.z) + Vector3.UP * 0.14)

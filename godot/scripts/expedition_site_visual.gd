extends Node3D
## Reuse shipped textured props; discovery sites have no floating title or beacon.

func build(kind: String, index: int) -> void:
	add_to_group("render_dynamic")
	if kind == "outpost":
		prop("workbench", Vector3(0, 0, -1.8), 0.85)
		prop("ammo_crate", Vector3(-1.15, 0, -1.2), 0.65)
		prop("medkit", Vector3(0.4, 0.85, -1.8), 0.2)
		for x in [-1.9, 1.9]:
			for z in [-1.8, -0.9, 0.0]:
				for level in 2:
					var bag := prop("sandbag", Vector3(x, level*0.25, z+level*0.12), 0.29)
					bag.rotation.y = PI*0.5
		for x in [-0.95, 0.0, 0.95]:
			for level in 2:
				prop("sandbag", Vector3(x+level*0.1, level*0.25, -2.8), 0.29)
		radio(Vector3(1.55, 0, -2.2), index)
	elif kind == "signal":
		prop("ammo_crate", Vector3(-0.55, 0, 0.15), 0.55)
		radio(Vector3(0.35, 0, 0), index-5)
	else:
		var crate := prop("ammo_crate", Vector3.ZERO, 0.75)
		crate.rotation.y = float(index)*0.73

func prop(id: String, offset: Vector3, height: float) -> Node3D:
	var at := global_position+offset
	offset.y += Map.ground_height(at.x, at.z)-global_position.y
	var model := WorldModels.attach(self, id, offset, height)
	if model and id != "medkit":
		var bounds := Barricade._bounds(model, model.transform.affine_inverse())
		var body := StaticBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 0
		model.add_child(body)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = bounds.size*Vector3(0.85, 0.9, 0.85)
		collision.shape = shape
		collision.position = bounds.get_center()
		body.add_child(collision)
	return model

func set_available(available: bool) -> void:
	visible = available
	for body in find_children("*", "StaticBody3D", true, false):
		body.collision_layer = 8 if available else 0

func radio(offset: Vector3, index: int) -> void:
	var body := prop("tower_siren", offset, 1.15)
	var metal := DefenceTower.material(Color(0.19, 0.23, 0.18))
	var mast := CylinderMesh.new()
	mast.top_radius = 0.018
	mast.bottom_radius = 0.035
	mast.height = 2.6
	DefenceTower.piece(self, mast, body.position+Vector3(0, 1.3, 0), metal)
	var crossbar := BoxMesh.new()
	crossbar.size = Vector3(0.8, 0.025, 0.025)
	DefenceTower.piece(self, crossbar, body.position+Vector3(0, 2.3, 0), metal)
	var number := Label3D.new()
	number.text = str(index+1)
	number.font_size = 40
	number.pixel_size = 0.004
	number.position = body.position+Vector3(0, 0.85, 0.4)
	number.no_depth_test = false
	add_child(number)

class_name WorldModels
extends RefCounted

# Shared imported resources keep repeated props cheap; fitting never edits mesh data.
static var _scenes: Dictionary = {}

static func create(id: String, size := 0.0, axis := 1, dynamic := true) -> Node3D:
	if not _scenes.has(id):
		var path := "res://assets/models/%s.glb" % id
		_scenes[id] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _scenes[id]
	if not scene: return null
	var holder := Node3D.new()
	holder.name = "Model_" + id
	holder.set_meta("model_id", id)
	if dynamic: holder.add_to_group("render_dynamic")
	var model: Node3D = scene.instantiate()
	holder.add_child(model)
	if size > 0.0:
		var bounds := Barricade._bounds(model)
		var factor := size / maxf(bounds.size[axis], 0.001)
		model.scale *= factor
		model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	return holder

static func attach(parent: Node3D, id: String, at := Vector3.ZERO, size := 0.0, axis := 1, dynamic := true) -> Node3D:
	var model := create(id, size, axis, dynamic)
	if model:
		parent.add_child(model)
		model.position = at
	return model

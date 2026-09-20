extends RefCounted
# Actual Meshy geometry with imported PBR materials, shared by first person and coop.
const SCENES = {
	"knife": preload("res://assets/models/knife_real.glb"),
	"hatchet": preload("res://assets/models/hatchet_real.glb")
}
static func build(id: String) -> Node3D:
	var model: Node3D = SCENES[id].instantiate()
	model.name = "Knife" if id == "knife" else "Hatchet"
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return model

# Two-leaf door in a wall opening. Closed (with collision) until the player opens it with E; leaves swing outwards.
# Same interface as Loot so main.gd can list it as an interactable.
class_name Door
extends Node3D

var taken := false
var label := "Tor"
var width := 2.6
var height := 2.1
var leaves: Array = []
var body: StaticBody3D

# local frame: the door sits in the x = 0 plane, opening spans z in [-width/2, width/2], outside is -x
func setup(w: float, h: float, text: String, mat: Material) -> void:
	width = w
	height = h
	label = text
	body = StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.12, height, width)
	cs.shape = box
	cs.position = Vector3(0, height / 2.0, 0)
	body.add_child(cs)
	add_child(body)
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(0, 0, side * width / 2.0)
		add_child(hinge)
		var leaf := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, height - 0.04, width / 2.0 - 0.02)
		leaf.mesh = bm
		leaf.material_override = mat
		leaf.position = Vector3(0, height / 2.0, -side * width / 4.0)
		hinge.add_child(leaf)
		# hinge straps and a handle
		var strap := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.1, 0.05, width / 2.0 - 0.1)
		strap.mesh = sm
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.2, 0.2, 0.22)
		iron.metallic = 0.7
		iron.roughness = 0.4
		strap.material_override = iron
		strap.position = Vector3(-0.05, height * 0.75, -side * width / 4.0)
		hinge.add_child(strap)
		leaves.append([hinge, side])

func prompt_text() -> String:
	return "[E] %s öffnen" % label

func take(_weapons, _hud) -> void:
	if taken:
		return
	taken = true
	body.get_child(0).set_deferred("disabled", true)
	Sfx.play_at(get_parent(), "wood", global_position, -6.0, 0.7)
	for l in leaves:
		var hinge: Node3D = l[0]
		var side: float = l[1]
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(hinge, "rotation:y", side * 1.75, 1.4)

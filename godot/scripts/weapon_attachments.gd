# Hangs the weapon mod models on a weapon: muzzle devices on the measured bore axis, magazines in
# the well, the bolt on the receiver. Every offset comes from weapon_mount_data.gd, which
# tools/weapon_geometry.mjs measures out of the GLBs themselves, so a re-rolled Meshy part or a
# changed "height" in Weapons.DEFS needs no hand tuning here.
#
# The node is added to the weapon holder AFTER the hands and the aim position are derived from the
# bare weapon bounds (weapons.gd), so mounting a suppressor never moves a grip or the sights.
class_name WeaponAttachments
extends Node3D

const Data = preload("res://scripts/weapon_mount_data.gd")

# mount: which anchor on the gun carries the part.
# radius: [multiple of the weapon's own bore radius, minimum m, maximum m] - a 9 mm barrel still
#         has to carry a believable can, a .50 gets a fat one. That radius sets the part's
#         thickness; only its length is trimmed to fit the gun.
# max:    longest the part may become, as a fraction of the weapon's own length. A wide shotgun
#         muzzle would otherwise scale a slender barrel into a lance.
# sink:   how far the part slides back over the weapon, as a fraction of its own length. That
#         overlap is what removes the seam between gun and mod.
const MOUNTS := {
	"suppressor": {"model": "mod_suppressor", "mount": "muzzle", "radius": [1.6, 0.0135, 0.030], "max": 0.82, "sink": 0.16},
	"ghost": {"model": "mod_ghost", "mount": "muzzle", "radius": [1.5, 0.0125, 0.027], "max": 0.78, "sink": 0.14,
		"glow": Color(0.16, 0.72, 0.95), "glow_energy": 0.4},
	"compensator": {"model": "mod_compensator", "mount": "muzzle", "radius": [1.45, 0.011, 0.023], "max": 0.3, "sink": 0.2},
	"match_barrel": {"model": "mod_match_barrel", "mount": "barrel", "radius": [1.2, 0.0075, 0.020], "max": 0.4, "sink": 0.58},
	"titan_core": {"model": "mod_titan_core", "mount": "barrel", "radius": [1.4, 0.009, 0.026], "max": 0.45, "sink": 0.5,
		"glow": Color(1.0, 0.42, 0.1), "glow_energy": 0.3},
	"extended": {"model": "mod_extended_mag", "mount": "magazine", "tube": "mod_mag_tube", "width": 1.04, "sink": 0.42, "reach": 0.42},
	"endless": {"model": "mod_endless", "mount": "magazine", "tube": "mod_mag_tube", "drum": 0.085, "width": 2.4, "sink": 0.3, "reach": 0.62},
	"quick_action": {"model": "mod_quick_action", "mount": "bolt", "radius": [0.9, 0.006, 0.012], "max": 0.3, "sink": 0.35},
}
# Mounted in this order: the barrel extends the bore first, a muzzle device then rides on its tip.
const AXIAL := ["match_barrel", "titan_core", "suppressor", "ghost", "compensator"]

# What the weapon actually feeds from. A tube fed shotgun gets a longer magazine tube under the
# barrel instead of a box magazine; a revolver shows nothing, its cylinder cannot be extended.
const MAGAZINE := {
	"pistol": "box", "revolver": "", "smg": "box", "ak47": "box", "rifle": "tube",
	"marksman": "box", "lmg": "box", "breacher": "tube", "titanbreaker": "box",
}

var weapon := ""
var layer := 2  # 2 = the view model render layer; a co-op avatar sets 1 for the world
var shadows := false  # the view model never casts, a weapon out in the world does
var _to_holder := Transform3D.IDENTITY
var _scale := 1.0
var _forward := Vector3.FORWARD
var _up := Vector3.UP
var _right := Vector3.RIGHT
var _parts := {}
var _tip := Vector3.ZERO
var _tip_valid := false

static func supported(weapon_id: String) -> bool:
	return Data.WEAPONS.has(weapon_id)

# model is the instantiated weapon GLB; its own transform carries the -90 degree turn and the
# _fit_height scale, which is exactly what maps raw model coordinates onto the gun. The chain is
# walked up to the node this mount hangs from, so the same code serves the view model (holder ->
# inner -> model) and a co-op avatar (gun -> model).
func setup(weapon_id: String, model: Node3D, parent: Node3D = null) -> void:
	name = "Mods"
	weapon = weapon_id
	var stop: Node3D = parent if parent else (model.get_parent().get_parent() as Node3D)
	_to_holder = Transform3D.IDENTITY
	var node: Node3D = model
	while node != null and node != stop:
		_to_holder = node.transform * _to_holder
		node = node.get_parent() as Node3D
	_scale = _to_holder.basis.get_scale().x
	_forward = (_to_holder.basis * Vector3.LEFT).normalized()  # the barrel runs along raw -X
	_up = (_to_holder.basis * Vector3.UP).normalized()
	_right = _forward.cross(_up).normalized()

func weapon_data() -> Dictionary:
	return Data.WEAPONS.get(weapon, {})

# Holder-local muzzle: the front of the mounted barrel or muzzle device, so the flash, the smoke
# and the tracers leave the suppressor instead of the bare barrel underneath it. With nothing
# mounted it is the measured bore, which beats the bounding box estimate the caller falls back to:
# that one puts the titanbreaker's flash 8 cm high, inside its scope.
func muzzle_tip(fallback: Vector3) -> Vector3:
	return _tip if _tip_valid else fallback

# The bare muzzle of this weapon, 6 mm clear of the barrel face like the old estimate.
func bore_tip() -> Vector3:
	var w := weapon_data()
	if w.is_empty(): return Vector3.ZERO
	return _to_holder * (w.bore as Vector3) + _forward * 0.006

# Holder-local geometry of a mounted part, so tests can measure the fit instead of eyeballing it.
func part_node(id: String) -> Node3D:
	return _parts.get(id)

func part_point(id: String, end: String) -> Vector3:
	var node := part_node(id)
	if node == null: return Vector3.ZERO
	return node.transform * _anchor(Data.PARTS[_model_for(id)], end)

func part_axis(id: String) -> Vector3:
	var node := part_node(id)
	if node == null: return Vector3.ZERO
	return (node.transform.basis * (Data.PARTS[_model_for(id)].forward as Vector3)).normalized()

func part_radius(id: String) -> float:
	var node := part_node(id)
	if node == null: return 0.0
	var part: Dictionary = Data.PARTS[_model_for(id)]
	return float(part.radius) * node.transform.basis.get_scale().y

func mounted() -> Array:
	var ids := []
	for id in _parts:
		if (_parts[id] as Node3D).visible: ids.append(id)
	return ids

func refresh(loadout: Dictionary) -> void:
	if weapon_data().is_empty(): return
	var wanted := {}
	for slot in loadout:
		var id: String = loadout[slot]
		if MOUNTS.has(id) and _model_for(id) != "": wanted[id] = true
	for id in wanted:
		if not _parts.has(id): _build(id)
	for id in _parts:
		(_parts[id] as Node3D).visible = wanted.has(id)
	_place()

func _model_for(id: String) -> String:
	var spec: Dictionary = MOUNTS[id]
	if spec.mount != "magazine": return spec.model
	match MAGAZINE.get(weapon, ""):
		"box": return spec.model
		"tube": return spec.get("tube", "")
	return ""

func _build(id: String) -> void:
	var model := _model_for(id)
	var path := "res://assets/models/%s.glb" % model
	if not Data.PARTS.has(model) or not ResourceLoader.exists(path): return
	var node := Node3D.new()
	node.name = id
	var scene: PackedScene = load(path)
	node.add_child(scene.instantiate())
	add_child(node)
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.layers = layer
	var spec: Dictionary = MOUNTS[id]
	if spec.has("glow"): _glow(node, spec.glow, float(spec.glow_energy))
	_parts[id] = node

# Legendary parts came back from Meshy without their glow; multiplying the albedo into the emission
# keeps the dark body dark and only lifts the bright edges.
func _glow(node: Node3D, colour: Color, energy: float) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(i)
			if not source is StandardMaterial3D: continue
			var mat: StandardMaterial3D = (source as StandardMaterial3D).duplicate()
			mat.emission_enabled = true
			mat.emission = colour
			mat.emission_energy_multiplier = energy
			mat.emission_texture = mat.albedo_texture
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			mesh.set_surface_override_material(i, mat)

func _visible(id: String) -> bool:
	return _parts.has(id) and (_parts[id] as Node3D).visible

func _place() -> void:
	var w := weapon_data()
	var bore: Vector3 = _to_holder * (w.bore as Vector3)
	var bore_radius: float = float(w.bore_radius) * _scale
	_tip = bore + _forward * 0.006
	_tip_valid = true
	var tip := bore
	for id in AXIAL:
		if not _visible(id): continue
		tip = _mount_axial(id, tip, bore_radius)
		_tip = tip
	for id in _parts:
		if not _visible(id) or id in AXIAL: continue
		match MOUNTS[id].mount:
			"magazine": _mount_magazine(id, bore, bore_radius)
			"bolt": _mount_bolt(id, bore_radius)

# Threads a barrel or a muzzle device onto the bore and returns the new tip for the next one.
func _mount_axial(id: String, tip: Vector3, bore_radius: float) -> Vector3:
	var spec: Dictionary = MOUNTS[id]
	var part: Dictionary = Data.PARTS[spec.model]
	var k := _axial_scale(spec, part, bore_radius)
	var length := float(part.length) * k.x
	var sink := float(spec.sink) * length
	var basis := _basis(part, _forward, _up, k.x, k.y)
	var node: Node3D = _parts[id]
	node.transform = Transform3D(basis, tip - _forward * sink - basis * _anchor(part, "rear"))
	return tip + _forward * (length - sink)

# The calibre comes from the bore, the length from what the gun can carry: a slender rifle barrel
# scaled uniformly onto a pistol would be either a lance or a wire, so the part keeps its measured
# diameter and is only shortened along its axis. On a plain cylinder that is invisible.
func _axial_scale(spec: Dictionary, part: Dictionary, bore_radius: float) -> Vector2:
	var factors: Array = spec.radius
	var target := clampf(float(factors[0]) * bore_radius, float(factors[1]), float(factors[2]))
	var across := target / float(part.radius)
	var longest := float(spec.max) * float(weapon_data().length) * _scale
	return Vector2(minf(across, longest / float(part.length)), across)

func _mount_magazine(id: String, bore: Vector3, bore_radius: float) -> void:
	var spec: Dictionary = MOUNTS[id]
	var w := weapon_data()
	var node: Node3D = _parts[id]
	var part: Dictionary = Data.PARTS[_model_for(id)]
	if MAGAZINE.get(weapon, "") == "tube":
		# A shotgun's magazine sits under the barrel, so the tube is stretched along the barrel
		# rather than scaled uniformly - it is a plain cylinder, nothing to distort.
		var radius := bore_radius * 0.78
		var reach := (bore - _to_holder * Vector3((w.receiver as Vector3).x, 0.0, 0.0)).length() * float(spec.reach)
		var across := radius / float(part.radius)
		var along := maxf(reach, radius * 4.0) / float(part.length)
		var tube := _basis(part, _forward, _up, along, across)
		node.transform = Transform3D(tube, bore - _up * (bore_radius + radius * 1.05) - tube * _anchor(part, "front"))
		return
	var mount := _magwell()
	var width := _magazine_width(float(spec.width))
	if part.shape == "disc":
		# A drum hangs on the well with its face across the gun; only the top disappears inside.
		var radius := clampf(float(spec.drum) * float(w.length) * _scale, 0.012, 0.045)
		var drum := radius / float(part.radius)
		var basis := _basis(part, _right, _up, drum, drum)
		node.transform = Transform3D(basis, mount - _up * (radius * (1.0 - float(spec.sink))) - basis * (part.centre as Vector3))
		return
	# A box magazine goes in narrow side out: its wide face looks forward, the feed lips sit inside.
	var k := width / float(part.side_span)
	var length := float(part.length) * k
	var basis := _basis(part, _up, _forward, k, k)
	node.transform = Transform3D(basis, mount + _up * (float(spec.sink) * length) - basis * _anchor(part, "front"))

# The magazine well: the lowest point of the weapon's own magazine. On the MG the lowest point is
# the belt box hanging off one side, so an anchor that far out of line is pulled back to centre.
func _magwell() -> Vector3:
	var w := weapon_data()
	var mag: Vector3 = w.mag
	if absf(mag.z) > float(w.width) * 0.25: mag.z = 0.0
	return _to_holder * mag

# Measured on the weapon, but held to what a magazine can look like next to that gun.
func _magazine_width(factor: float) -> float:
	var w := weapon_data()
	var ceiling := minf(0.035, float(w.width) * _scale * 0.55)
	return clampf(float(w.mag_width) * _scale * factor, 0.010, ceiling)

func _mount_bolt(id: String, bore_radius: float) -> void:
	var spec: Dictionary = MOUNTS[id]
	var w := weapon_data()
	var part: Dictionary = Data.PARTS[spec.model]
	var k := _axial_scale(spec, part, bore_radius)
	var target := float(part.radius) * k.y
	var length := float(part.length) * k.x
	var basis := _basis(part, _forward, _up, k.x, k.y)
	# On the shooter's side of the receiver, level with its upper half: the one place on every one
	# of these guns that neither hand and no sight line occupies.
	var seat: Vector3 = _to_holder * (w.receiver as Vector3)
	seat += _right * (float(w.receiver_width) * _scale * 0.5 + target * 0.85)
	seat += _up * (float(w.receiver_top) * _scale * 0.3)
	seat -= _forward * (length * float(spec.sink))
	var node: Node3D = _parts[id]
	node.transform = Transform3D(basis, seat - basis * (part.centre as Vector3))

# Rotates a part out of its own principal frame onto the gun: its forward onto tf, its up onto tu.
# along/across scale the part down the mounted axis and across it (equal for everything but the
# stretched magazine tube).
func _basis(part: Dictionary, tf: Vector3, tu: Vector3, along: float, across: float) -> Basis:
	var f: Vector3 = (part.forward as Vector3).normalized()
	var u: Vector3 = (part.up as Vector3)
	u = (u - f * u.dot(f)).normalized()  # the measured axes are close to orthogonal, not exactly
	var source := Basis(f, u, f.cross(u))
	var forward := tf.normalized()
	var up := (tu - forward * tu.dot(forward)).normalized()
	var target := Basis(forward * along, up * across, forward.cross(up) * across)
	return target * source.transposed()

# The centre of the part's front or rear face, in raw part coordinates.
func _anchor(part: Dictionary, end: String) -> Vector3:
	var f: Vector3 = part.forward
	var u: Vector3 = part.up
	var offset: Vector2 = part[end + "_centre"]
	var distance := float(part[end]) * (1.0 if end == "front" else -1.0)
	return (part.centre as Vector3) + f * distance + u * offset.x + f.cross(u) * offset.y

# The spitter's glob (26 Sep 2026): a lump of glowing acid on a fixed arc from the mouth to the point it
# was aimed at (a gate, the hut wall or the player). When it lands, main.acid_land puts an AcidPool
# there (host) and hits anyone standing right under it. Clients only ever see the flight
# (NetSession._acid_glob) and the pool (NetSession._acid_pool); the damage is the host's.
class_name AcidGlob
extends Node3D

var from := Vector3.ZERO
var to := Vector3.ZERO
var flight := 1.0
var spec: Dictionary = {}
var replica := false
var spitter: Zombie
var _t := 0.0
static var _material: StandardMaterial3D
static var _mesh: SphereMesh

static func _shared() -> void:
	if _material: return
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.45, 0.95, 0.2)
	_material.emission_enabled = true
	_material.emission = Color(0.35, 1.0, 0.2)
	_material.emission_energy_multiplier = 2.2
	_material.roughness = 0.25
	_mesh = SphereMesh.new()
	_mesh.radius = 0.2
	_mesh.height = 0.4
	_mesh.radial_segments = 10
	_mesh.rings = 5

func setup(a: Vector3, b: Vector3, ranged_spec: Dictionary, is_replica: bool, thrower: Zombie = null) -> void:
	_shared()
	from = a
	to = b
	spec = ranged_spec
	replica = is_replica
	spitter = thrower
	var speed := float(spec.get("speed", 15.0))
	flight = clampf(a.distance_to(b) / speed, 0.45, 1.6)
	var visual := MeshInstance3D.new()
	visual.mesh = _mesh
	visual.material_override = _material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.scale = Vector3(1.0, 0.8, 1.3)
	add_child(visual)
	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 1.0, 0.25)
	light.light_energy = 1.4
	light.omni_range = 3.5
	light.shadow_enabled = false
	add_child(light)
	global_position = a

func _process(delta: float) -> void:
	_t += delta
	var k := _t / flight
	if k >= 1.0:
		_land()
		return
	var apex := maxf(1.2, from.distance_to(to) * 0.2)
	global_position = from.lerp(to, k) + Vector3.UP * 4.0 * apex * k * (1.0 - k)
	# face along the arc so the flattened blob streaks
	var ahead := from.lerp(to, minf(k + 0.05, 1.0)) + Vector3.UP * 4.0 * apex * minf(k + 0.05, 1.0) * (1.0 - minf(k + 0.05, 1.0))
	if ahead.distance_squared_to(global_position) > 0.0001: look_at(ahead, Vector3.UP)

func _land() -> void:
	var scene := get_tree().current_scene
	if not replica and scene and scene.has_method("acid_land"):
		scene.acid_land(to, spec, spitter)
	queue_free()

# A pool of the spitter's acid (26 Sep 2026): a green splat on the ground that eats gates, sandbag lines,
# towers and the hut wall it touches (structure damage per second) and burns players standing in it, for
# "seconds", then dries up. Only the host applies damage; replicas (clients) show the same pool from the
# host's RPC. One shared decal texture and one shared bubble material for every pool.
class_name AcidPool
extends Node3D

const RADIUS := 2.2
const PLAYER_DPS := 9.0

var seconds := 6.5
var structure_dps := 90.0
var replica := false
var owner_peer := 0
var _life := 0.0
var _tick := 0.0
var _light: OmniLight3D
var _decal: Decal
var _bubbles: CPUParticles3D
var structure_dealt := 0.0     # statistics / tests
static var _bubble_mesh: SphereMesh
static var _bubble_material: StandardMaterial3D

static func _shared() -> void:
	if _bubble_mesh: return
	_bubble_mesh = SphereMesh.new()
	_bubble_mesh.radius = 0.06
	_bubble_mesh.height = 0.12
	_bubble_mesh.radial_segments = 6
	_bubble_mesh.rings = 3
	_bubble_material = StandardMaterial3D.new()
	_bubble_material.albedo_color = Color(0.5, 1.0, 0.3, 0.8)
	_bubble_material.emission_enabled = true
	_bubble_material.emission = Color(0.3, 0.9, 0.15)
	_bubble_material.emission_energy_multiplier = 1.5
	_bubble_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bubble_mesh.material = _bubble_material

func setup(spec: Dictionary, is_replica: bool) -> void:
	_shared()
	seconds = float(spec.get("acid", 6.5))
	structure_dps = float(spec.get("structure", 90.0))
	replica = is_replica
	var scene := get_tree().current_scene if is_inside_tree() else null
	var splat: Texture2D = scene.weapons._splat_tex if scene and "weapons" in scene and scene.weapons and scene.weapons._splat_tex else null
	if splat:
		_decal = Decal.new()
		_decal.texture_albedo = splat
		_decal.albedo_mix = 1.0
		_decal.modulate = Color(0.35, 0.95, 0.15, 0.85)
		_decal.size = Vector3(RADIUS * 2.0, 1.2, RADIUS * 1.8)
		_decal.cull_mask = 1
		add_child(_decal)
		_decal.rotation.y = randf() * TAU
	_light = OmniLight3D.new()
	_light.light_color = Color(0.4, 1.0, 0.25)
	_light.light_energy = 1.3
	_light.omni_range = RADIUS * 2.2
	_light.shadow_enabled = false
	_light.position.y = 0.6
	add_child(_light)
	_bubbles = CPUParticles3D.new()
	_bubbles.amount = 26
	_bubbles.lifetime = 1.4
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_bubbles.emission_sphere_radius = RADIUS * 0.8
	_bubbles.direction = Vector3.UP
	_bubbles.spread = 12.0
	_bubbles.initial_velocity_min = 0.3
	_bubbles.initial_velocity_max = 0.9
	_bubbles.gravity = Vector3(0, -0.3, 0)
	_bubbles.scale_amount_min = 0.6
	_bubbles.scale_amount_max = 1.4
	_bubbles.mesh = _bubble_mesh
	_bubbles.position.y = 0.05
	add_child(_bubbles)
	_bubbles.emitting = true
	Sfx.play_at(scene if scene else self, "acid_splash", global_position, -6.0, randf_range(0.9, 1.1), 5.0, 45.0)

func _process(delta: float) -> void:
	_life += delta
	var left := seconds - _life
	if _light: _light.light_energy = (1.1 + 0.35 * sin(_life * 13.0)) * clampf(left, 0.0, 1.0)
	if _decal: _decal.modulate.a = 0.85 * clampf(left / 1.5, 0.0, 1.0)
	if left <= 0.0:
		if _bubbles: _bubbles.emitting = false
		queue_free()
		return
	if replica or NetSession.is_client(): return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_apply(0.5)

func _apply(dt: float) -> void:
	var scene := get_tree().current_scene
	if not scene: return
	var lines: Array = scene.defence_lines() if scene.has_method("defence_lines") else scene.get("barricades")
	for line in lines:
		if not is_instance_valid(line) or line.hp <= 0.0: continue
		if line.distance_to_line(global_position) < RADIUS + 0.7:
			var amount := structure_dps * dt
			line.damage(amount)
			structure_dealt += amount
	var hut = scene.get("hut")
	if hut and hut.hp > 0.0 and hut.distance(global_position) < RADIUS + 0.9:
		hut.damage(structure_dps * 0.6 * dt)
		structure_dealt += structure_dps * 0.6 * dt
	for tower in get_tree().get_nodes_in_group("defence_towers"):
		if tower.hp > 0.0 and not tower.rooftop and tower.global_position.distance_to(global_position) < RADIUS + 0.8:
			tower.damage(structure_dps * 0.5 * dt)
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() and NetSession.world else [scene.player]
	for actor in actors:
		if not is_instance_valid(actor) or not actor.alive: continue
		var flat := Vector2(actor.global_position.x - global_position.x, actor.global_position.z - global_position.z).length()
		if flat < RADIUS and absf(actor.global_position.y - global_position.y) < 1.6:
			actor.damage(PLAYER_DPS * dt, global_position)

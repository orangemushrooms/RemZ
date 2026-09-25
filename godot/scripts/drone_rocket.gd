# A rocket from an attack drone (26 Sep 2026, right mouse button while flying, attack_drone.fire_rocket):
# a fast straight dart from the drone's muzzle along its aim, swept by a ray every physics tick like the
# mortar shell, that bursts on the first thing it meets or after `reach` metres. The burst is a blast of
# RADIUS metres with a falloff to EDGE at the rim on every zombie in sight, credited to the pilot like
# the drone's gun. The host owns the damage and tells the clients through NetSession.drone_rocket; their
# replica only flies and vanishes where it would burst, the burst itself arrives as the host's explosion
# RPC (coop_world.show_explosion).
class_name DroneRocket
extends Node3D

const SPEED := 58.0
const RADIUS := 5.0
const EDGE := 0.3

var origin := Vector3.ZERO
var direction := Vector3.FORWARD
var reach := 90.0
var damage := 300.0
var owner_peer := 1
var kind := "scout"
var replica := false
var game: Node
var excluded: Array[RID] = []
var travelled := 0.0
var burst := false
var _trail: CPUParticles3D
static var _body_material: StandardMaterial3D

func setup(scene: Node, from: Vector3, dir: Vector3, range_m: float, amount: float, peer: int, drone_kind: String, is_replica: bool) -> void:
	game = scene
	origin = from
	direction = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	reach = range_m
	damage = amount
	owner_peer = peer
	kind = drone_kind
	replica = is_replica

func _ready() -> void:
	global_position = origin
	look_at(origin + direction, Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT)
	if not _body_material:
		_body_material = DefenceTower.material(Color(0.34, 0.32, 0.27), 0.55)
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.55
	mesh.radial_segments = 8
	body.mesh = mesh
	body.rotation.x = PI * 0.5
	body.material_override = _body_material
	add_child(body)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.25)
	glow.light_energy = 2.2
	glow.omni_range = 4.0
	glow.shadow_enabled = false
	glow.position.z = 0.35
	add_child(glow)
	_trail = AttackDrone.Effects.cloud(1, 40, 0.7, Vector2(0.35, 0.35), false)
	_trail.direction = Vector3.BACK
	_trail.spread = 8.0
	_trail.initial_velocity_min = 1.0
	_trail.initial_velocity_max = 2.0
	_trail.gravity = Vector3.UP * 0.4
	_trail.position.z = 0.3
	add_child(_trail)
	_trail.emitting = true
	Sfx.play_at(game if game else self, "flare", origin, -4.0, 0.7, 6.0, 90.0)

func _physics_process(delta: float) -> void:
	if burst: return
	if game and ("over" in game) and game.over:
		queue_free()
		return
	var step := SPEED * delta
	var next := global_position + direction * step
	travelled += step
	var query := PhysicsRayQueryParameters3D.create(global_position, next, Zombie.SHOT_MASK, excluded)
	query.collide_with_areas = true
	var hit := Zombie.cast_ray(self, query)
	if not hit.is_empty(): next = hit.position
	global_position = next
	if not hit.is_empty() or travelled >= reach: _burst(hit)

func _burst(hit: Dictionary) -> void:
	burst = true
	set_physics_process(false)
	if replica or NetSession.is_client() or game == null:
		queue_free()
		return
	var at := global_position
	AttackDrone.Effects.explosion(game, at)
	Sfx.play_at(game, "boom", at, -5.0)
	NetSession.explosion(at)
	if "hunting" in game and game.hunting: game.hunting.blast(at, RADIUS, damage, owner_peer)
	var direct := Zombie.from_hit(hit)
	var space := get_world_3d().direct_space_state
	for node in game.zombies_root.get_children():
		var enemy := node as Zombie
		if enemy == null or not enemy.alive: continue
		var centre: Vector3 = enemy.global_position + Vector3.UP * enemy.height * 0.5
		var distance := at.distance_to(centre)
		if enemy != direct:
			if distance > RADIUS + enemy.height * 0.25: continue
			var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.15, centre, 1 | 8, excluded)
			if not space.intersect_ray(ray).is_empty(): continue
		var share := 1.0 if enemy == direct else lerpf(1.0, EDGE, clampf(distance / RADIUS, 0.0, 1.0))
		enemy.killer_peer = owner_peer
		enemy.killer_weapon = "drone"
		enemy.last_headshot = false
		enemy.damage(damage * share, (centre - at).normalized())
		if not enemy.alive and "progression" in game and game.progression: game.progression.record_drone_kill(kind)
	queue_free()

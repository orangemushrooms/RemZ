extends SceneTree
const Classes = preload("res://scripts/character_classes.gd")
const Profile = preload("res://scripts/character_profile.gd")
const Combat = preload("res://scripts/class_combat.gd")
var checks := 0
var failures := 0

class Arena extends Node3D:
	var started := true
	var over := false
	var intro: Node
	var player: Player
	var navigation_ready := true
	var nav_region: NavigationRegion3D
	var field_trials: Node

class QuietTeleport extends AssassinTeleport:
	func local_effect() -> void: pass

class Trial extends Node:
	func permits(point: Vector3) -> bool: return point.x < 15.0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func box(parent: Node3D, at: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var volume := BoxShape3D.new()
	volume.size = size
	shape.shape = volume
	body.add_child(shape)
	parent.add_child(body)
	body.position = at
	return body

func configure(actor: Player, mode: String, level: int = 15) -> void:
	actor.class_combat.configure(Classes.loadout("assassin", Classes.threshold(level), [], mode))
	actor.teleport_cooldown = 0.0
	actor.position = Vector3(0, 0.08, 0)
	actor.rotation = Vector3.ZERO

func run() -> void:
	var profile := Profile.new()
	profile.persist = false
	profile.data = Profile.empty_profile()
	profile.data.classes.assassin.total_xp = Classes.threshold(14)
	check(not profile.choose_teleport("forward"), "Teleport is locked at level 14")
	profile.data.classes.assassin.total_xp = Classes.threshold(15)
	check(profile.choose_teleport("forward") and profile.loadout("assassin").teleport == "forward", "Level 15 explicitly unlocks Forward")
	check(profile.choose_teleport("map") and profile.loadout("assassin").teleport == "map", "Selecting Map replaces Forward")
	check(not profile.choose_teleport("both"), "Only one recognised mode may be selected")
	profile.begin_match("assassin")
	check(not profile.choose_teleport("forward"), "Teleport selection is frozen during a round")
	profile.end_match()
	profile.context = "lobby"
	check(not profile.choose_teleport("forward"), "Teleport cannot be changed in a connected lobby")
	profile.context = "main"
	var restored := Profile.sanitize(profile.data)
	check(restored.classes.assassin.teleport == "map", "Selected mode survives save sanitisation")
	var old := Profile.empty_profile()
	old.version = 2
	old.classes.assassin.total_xp = Classes.threshold(20)
	old.classes.assassin.choices = [0,1,0,1,-1,-1]
	old.classes.assassin.erase("teleport")
	var migrated := Profile.sanitize(old)
	check(migrated.classes.assassin.total_xp == old.classes.assassin.total_xp and migrated.classes.assassin.choices == old.classes.assassin.choices, "Migration preserves all old XP and passive talents")
	check(migrated.classes.assassin.teleport == "" and Profile.sanitize(migrated) == migrated, "Existing players explicitly choose their new ability; migration is idempotent")
	check(Classes.sanitize_loadout({"id":"assassin", "level":14, "teleport":"map"}).teleport == "", "Network loadouts cannot unlock the ability early")
	check(Classes.sanitize_loadout({"id":"gunslinger", "level":30, "teleport":"map"}).teleport == "", "Other classes cannot claim Teleport")
	check(Classes.sanitize_loadout({"id":"assassin", "level":15, "teleport": ["map"]}).teleport == "", "Malformed network mode is discarded")
	profile.free()
	Map._ensure()
	Map.BOUNDS = Rect2(-80,-80,160,160)
	Map._x0 = -80; Map._z0 = -80; Map._w = 161; Map._hh = 161
	Map._h.resize(161 * 161); Map._h.fill(0.0)
	var arena := Arena.new()
	root.add_child(arena)
	current_scene = arena
	box(arena, Vector3(0,-0.5,0), Vector3(120,1,120))
	arena.nav_region = NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-60,0,-60),Vector3(-60,0,60),Vector3(60,0,60),Vector3(60,0,-60)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	arena.nav_region.navigation_mesh = mesh
	arena.add_child(arena.nav_region)
	var actor := Player.new()
	actor.remote_actor = true
	arena.add_child(actor)
	actor.set_physics_process(false)
	actor.active = true
	arena.player = actor
	var ability := QuietTeleport.new()
	ability.game = arena
	arena.add_child(ability)
	ability.set_physics_process(false)
	for i in 4: await physics_frame
	configure(actor, "forward", 14)
	check(not ability.perform(actor, Vector2.ZERO).is_empty() and actor.teleport_serial == 0, "Host refuses a locked teleport")
	configure(actor, "forward")
	check(ability.perform(actor, Vector2(70,70)).is_empty() and is_equal_approx(actor.position.z, -8.0) and absf(actor.position.x) < 0.01, "Forward travels 8 metres in facing direction and ignores a forged map target")
	check(actor.velocity == Vector3.ZERO and actor.teleport_serial == 1 and actor.teleport_cooldown == 12.0, "Teleport clears momentum and starts its cooldown and serial")
	var landed := actor.position
	check(not ability.perform(actor, Vector2.ZERO).is_empty() and actor.position == landed, "Cooldown prevents repeated teleport commands")
	ability._physics_process(12.1)
	check(actor.teleport_cooldown == 0.0, "Cooldown becomes ready after elapsed gameplay time")
	for mode in ["forward","map"]:
		configure(actor,mode,30)
		actor.class_combat.configure(Classes.loadout("assassin",Classes.threshold(30),[-1,-1,-1,-1,-1,0],mode))
		check(ability.perform(actor,Vector2(25,0)).is_empty() and actor.teleport_cooldown==(6.0 if mode=="forward" else 15.0),"Master Assassin halves the actual %s teleport cooldown" % mode)
	configure(actor, "forward")
	actor.rotation.y = -PI * 0.5
	check(ability.perform(actor, Vector2.ZERO).is_empty() and is_equal_approx(actor.position.x, 8.0), "Forward follows horizontal facing")
	var wall := box(arena, Vector3(0,2,-5), Vector3(12,4,0.5))
	await physics_frame; await physics_frame
	configure(actor, "forward")
	check(ability.perform(actor, Vector2.ZERO).is_empty() and actor.position.z > -4.2 and actor.position.z < -2.0, "Forward stops safely in front of a wall")
	wall.position.z = -1.0
	await physics_frame; await physics_frame
	configure(actor, "forward")
	check(not ability.perform(actor, Vector2.ZERO).is_empty() and actor.teleport_cooldown == 0, "Blocked forward cast consumes no cooldown")
	wall.queue_free()
	await physics_frame; await physics_frame
	configure(actor, "map")
	check(ability.perform(actor, Vector2(25,0)).is_empty() and absf(actor.position.x - 25.0) < 0.01 and actor.teleport_cooldown == 30.0, "Map teleports to the selected position with its longer cooldown")
	configure(actor, "map")
	check(not ability.perform(actor, Vector2(41,0)).is_empty() and actor.teleport_cooldown == 0, "Map range rejects distant points without consuming cooldown")
	check(not ability.perform(actor, Vector2(NAN,0)).is_empty(), "Non-finite coordinates are rejected")
	check(not ability.perform(actor, Vector2.ZERO).is_empty(), "No-op teleport is rejected")
	var obstacle := box(arena, Vector3(20,1,0), Vector3(3,2,3))
	await physics_frame; await physics_frame
	check(not ability.perform(actor, Vector2(20,0)).is_empty(), "Occupied landing is rejected")
	obstacle.queue_free()
	var enemy := box(arena, Vector3(20,0.9,0), Vector3(1,1.8,1), 2)
	await physics_frame; await physics_frame
	check(not ability.perform(actor, Vector2(20,0)).is_empty(), "Cannot teleport inside an enemy")
	enemy.queue_free()
	arena.field_trials = Trial.new()
	arena.add_child(arena.field_trials)
	check(not ability.perform(actor, Vector2(20,0)).is_empty(), "Cannot escape a sealed field trial")
	arena.field_trials.queue_free(); arena.field_trials = null
	for state in ["downed", "spectating"]:
		actor.set(state, true)
		check(not ability.perform(actor, Vector2(10,0)).is_empty(), "Teleport blocked while " + state)
		actor.set(state, false)
	actor.mounted_tower = 1
	check(not ability.perform(actor, Vector2(10,0)).is_empty(), "Cannot teleport while mounted")
	actor.mounted_tower = 0; actor.controlling_drone = 1
	check(not ability.perform(actor, Vector2(10,0)).is_empty(), "Cannot teleport while piloting a drone")
	actor.controlling_drone = 0; actor.alive = false
	check(not ability.perform(actor, Vector2(10,0)).is_empty(), "Dead actors cannot teleport")
	actor.alive = true; arena.over = true
	check(not ability.perform(actor, Vector2(10,0)).is_empty(), "Finished rounds cannot teleport")
	arena.over = false
	var world = preload("res://scripts/coop_world.gd").new()
	world.actors[2] = actor
	actor.teleport_serial = 7
	world.pose_times[2] = 0.0
	var before := actor.position
	world.move_player(2, before + Vector3(0.2,0,0), 0,0,false,Vector3.ZERO,0.1,1,false,6)
	check(actor.position == before, "Delayed pre-teleport poses cannot rewind the host")
	world.move_player(2, before + Vector3(0.2,0,0), 0,0,false,Vector3.ZERO,0.2,2,false,7)
	check(actor.position.x > before.x + 0.1, "Acknowledged post-teleport movement resumes normally")
	print("ASSASSIN_TELEPORT_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

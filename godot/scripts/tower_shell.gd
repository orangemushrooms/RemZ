extends Node3D
# Swept ballistic shell: only the host applies blast damage; replicas show the flight.
var start := Vector3.ZERO
var destination := Vector3.ZERO
var owner_peer := 1
var damage_amount := 145.0
var authoritative := true
var excluded: Array[RID] = []
var game: Node3D
var elapsed := 0.0
var duration := 1.6
var arc_height := 12.0

func _ready() -> void:
	global_position = start
	duration = clampf(start.distance_to(destination)/25.0,0.7,2.8)
	arc_height = maxf(6.0,start.distance_to(destination)*0.3)
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.065
	mesh.height = 0.28
	DefenceTower.piece(self,mesh,Vector3.ZERO,DefenceTower.material(Color(0.16,0.18,0.13),0.6))

func _physics_process(delta: float) -> void:
	if not game.started or game.over: return
	elapsed += delta
	var t := minf(1,elapsed/duration)
	var point := start.lerp(destination,t)+Vector3.UP*(4*arc_height*t*(1-t))
	var ray := PhysicsRayQueryParameters3D.create(global_position,point,Zombie.SHOT_MASK,excluded)
	ray.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var travel := point - global_position
	if travel.length_squared() > 0.0001: quaternion = Quaternion(Vector3.UP, travel.normalized())
	global_position = hit.position if not hit.is_empty() else point
	if t>=1 or not hit.is_empty(): explode()

func explode() -> void:
	set_physics_process(false)
	if authoritative and not NetSession.is_client():
		for enemy in game.zombies_root.get_children():
			if not enemy is Zombie or not enemy.alive: continue
			var center: Vector3 = enemy.global_position+Vector3.UP*enemy.height*0.5
			var distance := global_position.distance_to(center)
			if distance>6: continue
			var ray := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*0.15,center,1|8,excluded)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
			enemy.killer_peer = owner_peer
			enemy.killer_weapon = "tower"
			enemy.last_headshot = false
			enemy.damage(damage_amount*lerpf(1,0.25,distance/6),(center-global_position).normalized())
	Sfx.play_at(game,"boom",global_position,-5)
	preload("res://scripts/tower_effects.gd").explosion(game, global_position)
	queue_free()

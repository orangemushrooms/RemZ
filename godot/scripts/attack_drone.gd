class_name AttackDrone
extends CharacterBody3D

const SPECS := {
	"scout": {"name": "Kestrel Scout", "wave": 5, "hp": 100.0, "speed": 9.0, "damage": 24.0, "rate": 0.18, "range": 65.0, "size": 1.25, "heat": 0.075},
	"viper": {"name": "Viper Gunship", "wave": 10, "hp": 180.0, "speed": 11.0, "damage": 42.0, "rate": 0.12, "range": 85.0, "size": 1.65, "heat": 0.055},
	"tempest": {"name": "Tempest Assault", "wave": 15, "hp": 280.0, "speed": 12.0, "damage": 62.0, "rate": 0.085, "range": 110.0, "size": 2.05, "heat": 0.04},
}
const Effects = preload("res://scripts/tower_effects.gd")
# Own layer: player bullets, grenades and tower sight lines pass a drone instead of stopping at it.
const LAYER := 64
# Roof volumes only drones collide with (main._gable_roof): the roofs themselves are bare meshes.
const BLOCKER_LAYER := 128
var game: Node
var system: Node3D
var drone_id := 0
var owner_peer := 1
var kind := "scout"
var hp := 100.0
var replica := false
var body: CharacterBody3D
var input_move := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var firing := false
var input_timeout := 0.0
var cooldown := 0.0
var collision_cooldown := 0.0
var heat := 0.0
var overheated := false
var shots := 0
var impact := Vector3.ZERO
var shot_origin := Vector3.ZERO
var visual: Node3D
var gun: Node3D
var muzzle: Node3D
var camera: Camera3D
var flash: OmniLight3D
var fx: Node3D
var tracer: MeshInstance3D
var shot_audio: AudioStreamPlayer3D
var motor: AudioStreamPlayer3D
var smoke: CPUParticles3D
var rotors: Array[Node3D] = []
var _flash_time := 0.0
var target_position := Vector3.ZERO
var target_yaw := 0.0
var target_pitch := 0.0
static var _motor_stream: AudioStreamWAV
const MOTOR_LOOP_START := 2.32
var motor_elapsed := 0.0
var motor_start_position := 0.0
var piloted_here := false   # this machine flies it: the view follows the mouse every frame
var _motion_from := Vector3.ZERO
var _motion_to := Vector3.ZERO

func spec() -> Dictionary: return SPECS[kind]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	body = self
	add_to_group("attack_drones")
	add_to_group("render_dynamic")
	collision_layer = LAYER
	collision_mask = 1 | 2 | 8 | LAYER | BLOCKER_LAYER
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = float(spec().size) * 0.42
	shape.shape = sphere
	add_child(shape)
	visual = Node3D.new()
	add_child(visual)
	var model := WorldModels.attach(visual, "drone_" + kind)
	if not model:
		# Diagnostic fallback while the generated assets are being imported.
		DefenceTower.box(visual, Vector3(0.6,0.22,0.7), Vector3.ZERO, DefenceTower.material(Color(0.2,0.26,0.24),0.7))
	gun = Node3D.new()
	add_child(gun)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0,-0.18,-float(spec().size)*0.6)
	gun.add_child(muzzle)
	var gunmetal := DefenceTower.material(Color(0.08,0.1,0.12),0.85)
	var barrel_count := 6 if kind == "tempest" else 2 if kind == "viper" else 1
	DefenceTower.box(gun,Vector3(0.23,0.16,0.27),Vector3(0,-0.18,-0.17),gunmetal)
	for i in barrel_count:
		var offset := Vector3.ZERO
		if kind == "tempest": offset = Vector3(cos(i*TAU/6)*0.07,sin(i*TAU/6)*0.07,0)
		elif kind == "viper": offset.x = -0.12 if i == 0 else 0.12
		var length := absf(muzzle.position.z)-0.2
		var barrel := DefenceTower.cylinder(gun,0.024,length,Vector3(0,-0.18,-0.2-length*0.5)+offset,gunmetal)
		barrel.rotation.x = PI*0.5
	fx = Effects.new()
	fx.kind = "mg42" if kind == "tempest" else "standard"
	muzzle.add_child(fx)
	flash = OmniLight3D.new()
	flash.light_color = Color(1,0.65,0.25)
	flash.omni_range = 5.0
	flash.light_energy = 2.5
	flash.hide()
	muzzle.add_child(flash)
	var glow := DefenceTower.material(Color(1,0.8,0.35))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer = DefenceTower.box(self,Vector3(0.015,0.015,1),Vector3.ZERO,glow)
	tracer.top_level = true
	tracer.hide()
	shot_audio = AudioStreamPlayer3D.new()
	shot_audio.stream = load("res://assets/audio/sfx/towers/" + ("mg42_shot.wav" if kind == "tempest" else "sentinel_shot.wav"))
	shot_audio.max_polyphony = 3
	shot_audio.volume_db = -10
	shot_audio.max_distance = 120
	muzzle.add_child(shot_audio)
	_build_rotors()
	motor = AudioStreamPlayer3D.new()
	motor.stream = motor_stream()
	motor.volume_db = -14
	motor.max_distance = 65
	add_child(motor)
	motor_start_position = motor_position(motor_elapsed)
	motor.play(motor_start_position)
	smoke = Effects.cloud(1,12,0.8,Vector2(0.45,0.45),false)
	smoke.direction = Vector3.UP
	smoke.gravity = Vector3.UP * 0.6
	smoke.color = Color(0.2,0.2,0.2,0.6)
	add_child(smoke)
	camera = Camera3D.new()
	camera.fov = 80
	camera.near = 0.08
	camera.far = 600
	add_child(camera)
	update_view()

static func motor_stream() -> AudioStreamWAV:
	if _motor_stream: return _motor_stream
	_motor_stream = (load("res://assets/audio/sfx/drone_flying_motor.wav") as AudioStreamWAV).duplicate()
	_motor_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_motor_stream.loop_begin = roundi(MOTOR_LOOP_START * _motor_stream.mix_rate)
	_motor_stream.loop_end = roundi(_motor_stream.get_length() * _motor_stream.mix_rate)
	return _motor_stream

static func motor_position(elapsed: float) -> float:
	var length := motor_stream().get_length()
	if elapsed < length: return maxf(0,elapsed)
	return MOTOR_LOOP_START + fposmod(elapsed-MOTOR_LOOP_START,length-MOTOR_LOOP_START)

func _build_rotors() -> void:
	var radius := float(spec().size)*0.36
	var mat := DefenceTower.material(Color(0.12,0.16,0.17,0.28),0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var count := 6 if kind == "tempest" else 4
	for i in count:
		var pivot := Node3D.new()
		visual.add_child(pivot)
		var angle := TAU * i / count + PI*0.25
		pivot.position = Vector3(cos(angle)*radius,0.09,sin(angle)*radius)
		DefenceTower.box(pivot,Vector3(radius*0.85,0.008,0.055),Vector3.ZERO,mat)
		rotors.append(pivot)

# `offset` shifts only what is drawn (model, gun, camera) to the position between two physics
# ticks; the body, its collisions and every shot stay on the tick.
func update_view(offset := Vector3.ZERO) -> void:
	rotation.y = yaw
	gun.rotation.x = pitch
	camera.rotation.x = pitch
	var local_offset := global_basis.inverse() * offset
	visual.position = local_offset
	gun.position = local_offset
	# Chase camera follows the crosshair, with a sweep to avoid looking through walls and roofs.
	var wanted := to_global(Vector3(0,0.6,2.8).rotated(Vector3.RIGHT,pitch)) + offset
	var q := PhysicsRayQueryParameters3D.create(global_position + offset, wanted, 1|8|BLOCKER_LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	camera.global_position = hit.position + hit.normal*0.12 if not hit.is_empty() else wanted

func _physics_process(delta: float) -> void:
	if replica or hp <= 0 or game.over: return
	if not game.started: return
	_motion_from = global_position
	# Keep up to one tick of overshoot, like Weapons: clamped at zero every shot waited for the next
	# whole tick and the Tempest fired 10 instead of 11.8 rounds a second.
	cooldown = maxf(-delta,cooldown-delta)
	collision_cooldown = maxf(0,collision_cooldown-delta)
	input_timeout = maxf(0,input_timeout-delta)
	if input_timeout <= 0:
		input_move = Vector3.ZERO
		firing = false
	heat = maxf(0,heat-delta*0.19)
	if overheated and heat < 0.25: overheated = false
	var direction := input_move.rotated(Vector3.UP,yaw)
	velocity = velocity.move_toward(direction*float(spec().speed),delta*24)
	var incoming := velocity
	var previous_position := global_position
	move_and_slide()
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var speed := absf(incoming.dot(collision.get_normal()))
		if speed > 1.5 and collision_cooldown <= 0:
			collision_cooldown = 0.65
			# Obstacles scrape the hull; enemy strikes are handled by their attack animation.
			damage(clampf(speed*0.6,2,8),false)
	var border := Map.BOUNDS.grow(-1)
	global_position.x = clampf(global_position.x,border.position.x,border.end.x)
	global_position.z = clampf(global_position.z,border.position.y,border.end.y)
	var ceiling := Map.ground_height(global_position.x,global_position.z)+45.0
	if global_position.y > ceiling:
		global_position.y = ceiling
		velocity.y = minf(0,velocity.y)
	if global_position.y < Map.ground_height(global_position.x,global_position.z)-3:
		damage(10000,false)
	_motion_to = global_position
	if hp > 0:
		game.progression.record_drone_flight(kind, minf(previous_position.distance_to(global_position), incoming.length()*delta))
	update_view()
	if firing and cooldown <= 0 and not overheated and hp > 0: shoot()

func _process(delta: float) -> void:
	if replica:
		global_position = global_position.lerp(target_position,1-exp(-delta*18))
		# The pilot's own look is set locally every frame (DroneSystem), not chased from snapshots.
		if not piloted_here:
			yaw = lerp_angle(yaw,target_yaw,1-exp(-delta*20))
			pitch = lerp_angle(pitch,target_pitch,1-exp(-delta*20))
		update_view()
	elif piloted_here and hp > 0:
		# Draw between the last two physics positions; a teleport snaps.
		var offset := Vector3.ZERO
		if global_position.is_equal_approx(_motion_to):
			offset = (_motion_from - _motion_to) * (1.0 - Engine.get_physics_interpolation_fraction())
		update_view(offset)
	for rotor in rotors: rotor.rotate_y(delta*90)
	var local_velocity := velocity.rotated(Vector3.UP,-yaw)
	visual.rotation.z = lerpf(visual.rotation.z,-local_velocity.x*0.018, minf(1,delta*6))
	visual.rotation.x = lerpf(visual.rotation.x,local_velocity.z*0.014,minf(1,delta*6))
	# Preserve the recorded spin-up. Only steady flight follows throttle, smoothly.
	var motor_pitch := 1.0 if motor_elapsed < MOTOR_LOOP_START else 0.97 + velocity.length()*0.015
	motor.pitch_scale = lerpf(motor.pitch_scale,motor_pitch,1-exp(-delta*4))
	motor_elapsed += delta * motor.pitch_scale
	smoke.emitting = hp > 0 and hp < float(spec().hp)*0.35
	_flash_time = maxf(0,_flash_time-delta)
	flash.visible = _flash_time > 0
	tracer.visible = _flash_time > 0

func shoot() -> void:
	if replica or NetSession.is_client() or hp <= 0 or cooldown > 0 or overheated: return
	update_view()
	var q := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*float(spec().range),Zombie.SHOT_MASK,[get_rid()])
	q.collide_with_areas = true
	var aim := Zombie.cast_ray(self,q)
	var destination: Vector3 = aim.position if not aim.is_empty() else q.to
	shot_origin = muzzle.global_position
	var direction := shot_origin.direction_to(destination)
	q.from = shot_origin
	q.to = shot_origin + direction * float(spec().range)
	var hit := Zombie.cast_ray(self,q)
	# A protruding barrel cannot bypass cover between the hull and the muzzle.
	var clearance := PhysicsRayQueryParameters3D.create(global_position,shot_origin,1|8,[get_rid()])
	var obstruction := get_world_3d().direct_space_state.intersect_ray(clearance)
	if not obstruction.is_empty(): hit = obstruction
	impact = hit.position if not hit.is_empty() else q.to
	var enemy := Zombie.from_hit(hit)
	if enemy and enemy.alive:
		enemy.killer_peer = owner_peer
		enemy.killer_weapon = "drone"
		enemy.last_headshot = false
		enemy.damage(float(spec().damage),direction)
		if not enemy.alive: game.progression.record_drone_kill(kind)
	else:
		preload("res://scripts/bullet_impacts.gd").hit(game,hit)
	cooldown = maxf(cooldown,-float(spec().rate))+float(spec().rate)
	heat = minf(1,heat+float(spec().heat))
	if heat >= 0.99: overheated = true
	shots += 1
	show_shot()

func show_shot() -> void:
	_flash_time = 0.045
	flash.show()
	fx.fire(shot_origin.distance_to(impact))
	shot_audio.play()
	var distance := shot_origin.distance_to(impact)
	if distance > 0.01:
		tracer.global_position = (shot_origin+impact)*0.5
		tracer.look_at(impact,Vector3.RIGHT if absf(shot_origin.direction_to(impact).y)>0.98 else Vector3.UP)
		tracer.scale = Vector3(1,1,distance)
		tracer.show()

func attack_point(_from: Vector3) -> Vector3:
	return global_position

func damage(amount: float, enemy_hit := true) -> void:
	if replica or NetSession.is_client() or hp <= 0 or not is_finite(amount) or amount <= 0: return
	hp = maxf(0,hp-(maxf(30,amount*2.5) if enemy_hit else amount))
	if hp <= 0:
		Effects.explosion(game,global_position)
		Sfx.play_at(game,"barricade_break",global_position,-8)
		system.finish(drone_id,true)

# First-person player: movement, mouse look, flashlight, health.
class_name Player
extends CharacterBody3D

signal died

const WALK_SPEED := 4.4
const SPRINT_SPEED := 7.2
const EYE := 1.7
const SENS := 0.0022

var camera: Camera3D
var head: Node3D
var flashlight: SpotLight3D
var hud: Hud
var hp := 100.0
var max_hp := 100.0
var score := 0
var alive := true
var active := false
var pitch := 0.0
var bob := 0.0
var regen_timer := 0.0
var wobble := 0.0
var _gravity := 20.0
var speed_mul := 1.0
var regen_mul := 1.0
var recoil_offset := Vector2.ZERO   # (pitch, yaw) radians of visual recoil still settling

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 8
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 300.0
	head.add_child(camera)
	camera.make_current()
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.95, 0.84)
	flashlight.light_energy = 6.0
	flashlight.spot_range = 45.0
	flashlight.spot_angle = 26.0
	flashlight.spot_attenuation = 0.9
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.15, -0.1, -0.2)
	camera.add_child(flashlight)
	rotation.y = PI

func _unhandled_input(event: InputEvent) -> void:
	if not active or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * SENS)
		pitch = clampf(pitch - event.relative.y * SENS, -1.45, 1.45)
		head.rotation.x = pitch + recoil_offset.x
	if event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible

func _physics_process(delta: float) -> void:
	if not active or not alive:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprint := Input.is_action_pressed("sprint")
	var speed := (SPRINT_SPEED if sprint else WALK_SPEED) * speed_mul
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var target := dir * speed
	velocity.x = lerpf(velocity.x, target.x, minf(1.0, delta * 12.0))
	velocity.z = lerpf(velocity.z, target.z, minf(1.0, delta * 12.0))
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -1.0
	move_and_slide()
	# keep inside the map
	global_position.x = clampf(global_position.x, Map.BOUNDS.position.x, Map.BOUNDS.end.x)
	global_position.z = clampf(global_position.z, Map.BOUNDS.position.y, Map.BOUNDS.end.y)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	bob += delta * ((13.0 if sprint else 9.0) if moving else 0.0)
	head.position.y = EYE + (sin(bob) * 0.04 if moving else 0.0)
	wobble = maxf(0.0, wobble - delta * 3.0)
	camera.rotation.z = (sin(bob * 0.5) * 0.004 if moving else 0.0) + sin(wobble * 30.0) * 0.02 * wobble
	head.rotation.x = pitch + recoil_offset.x
	camera.rotation.y = recoil_offset.y
	if regen_timer > 0.0:
		regen_timer -= delta
	elif hp < max_hp:
		hp = minf(max_hp, hp + delta * 4.0 * regen_mul)
		hud.set_health(hp)

func damage(n: float) -> void:
	if not alive:
		return
	hp -= n
	regen_timer = 5.0
	wobble = 1.0
	hud.set_health(hp)
	hud.damage_flash()
	Sfx.play(self, "hurt", -6.0)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		died.emit()

func add_score(n: int) -> void:
	score += n
	hud.set_score(score)

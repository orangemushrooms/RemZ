extends Node3D
var owl := false
var index := 0
var game: Node
var home := Vector3.ZERO
var flying := 0.0
var clock := 0.0
var check_time := 0.0
var call_time := 4.0
var wings: Array[Node3D] = []
var voice: AudioStreamPlayer3D
func _ready() -> void:
	add_to_group("render_dynamic")
	visible = not owl
	var kind := "owl" if owl else "raven"
	var body := MeshInstance3D.new()
	body.mesh = load("res://assets/cornfield/%s_body.res" % kind)
	add_child(body)
	for side in [-1,1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side*0.09,0.23,0)
		add_child(pivot)
		var mesh := MeshInstance3D.new()
		mesh.mesh = load("res://assets/cornfield/%s_wing.res" % kind)
		mesh.scale.x = side
		pivot.add_child(mesh)
		wings.append(pivot)
	voice = AudioStreamPlayer3D.new()
	voice.stream = load("res://assets/cornfield/%s.wav" % kind)
	voice.volume_db = -12
	voice.max_distance = 45
	voice.unit_size = 6
	add_child(voice)
	clock = index*0.8
	call_time += index*2.7
func scare(origin: Vector3) -> void:
	if not visible or global_position.distance_to(origin)>24 or flying>0: return
	flying = 10.0
	voice.play()
func _process(delta: float) -> void:
	if not game.started or game.over or not game.day_night: return
	clock += delta
	var hour: float = game.day_night.clock_seconds/3600.0
	visible = not owl or hour>=20 or hour<5
	if not visible:
		voice.stop()
		return
	check_time -= delta
	if check_time <= 0:
		check_time = 0.3
		var players: Array = NetSession.world.actors.values() if NetSession.enabled else [game.player]
		for p: Player in players:
			if p.alive and global_position.distance_to(p.global_position)<7: scare(p.global_position)
	call_time -= delta
	if call_time <= 0:
		call_time = 15.0+index*1.7
		if game.player.global_position.distance_to(global_position)<45: voice.play()
	var old := position
	if owl:
		position = home+Vector3(sin(clock*0.22)*12,2+sin(clock*0.4)*0.7,cos(clock*0.22)*8)
	elif flying>0:
		flying = maxf(0,flying-delta)
		var progress := (10.0-flying)/10.0
		position = home+Vector3(sin(progress*TAU)*8,sin(progress*PI)*8,(1-cos(progress*TAU))*5)
	else: position = home
	var motion := position-old
	if motion.length_squared()>0.00001: rotation.y = atan2(-motion.x,-motion.z)
	for i in wings.size():
		wings[i].rotation.z = (1 if i==0 else -1)*(sin(clock*(7 if owl else 15))*0.65 if owl or flying>0 else 1.1)

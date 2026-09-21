extends Node3D
const RAVEN_CALLS = [preload("res://assets/audio/sfx/raven_1.mp3"), preload("res://assets/audio/sfx/raven2.mp3"), preload("res://assets/audio/sfx/raven3.mp3")]
# Real wingbeat curves instead of a plain sine, measured from the animated birds of the
# three.js library (see tools/fetch_flap_library.py): the hand wing already lags the arm
# wing and the downstroke is faster than the upstroke, which is what sells the flutter.
const Flap = preload("res://scripts/flap_cycle.gd")
const FLAP_GAIN := 0.9
var last_call := -1
var owl := false
var index := 0
var game: Node
var home := Vector3.ZERO
var flying := 0.0
var flight_wait := 0.0
var clock := 0.0
var check_time := 0.0
var call_time := 4.0
var wings: Array[Node3D] = []
var voice: AudioStreamPlayer3D
var skeleton: Skeleton3D
var wing_bones: Array[int] = []
var model_root: Node3D
var cycle: Dictionary = {}
var flap_phase := 0.0
var flap_power := 0.0
var flap_inner := 0.0
var flap_outer := 0.0
var flap_row := 0.0
func _ready() -> void:
	add_to_group("render_dynamic")
	visible = not owl
	var kind := "owl" if owl else "raven"
	# The owl is a slow silent soarer, the raven rows: two different library cycles.
	cycle = Flap.CYCLES.get("stork" if owl else "parrot", {})
	var model_path := "res://assets/models/%s_real.glb" % kind
	if ResourceLoader.exists(model_path):
		var model: Node3D = load(model_path).instantiate()
		add_child(model)
		model_root = model
		for node in model.find_children("*", "Skeleton3D", true, false): skeleton = node
		if skeleton:
			for bone in ["Wing_L","Wing_R","Tip_L","Tip_R"]:
				wing_bones.append(skeleton.find_bone(bone))
		_pose_raven()
	else:
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
	voice.stream = load("res://assets/cornfield/owl.wav") if owl else RAVEN_CALLS[index % RAVEN_CALLS.size()]
	voice.volume_db = -12
	voice.max_distance = 45
	voice.unit_size = 6
	add_child(voice)
	clock = index*0.8
	call_time += (index%10)*2.7
	flight_wait = 9.0+(index%7)*2.3
	flap_phase = fmod(index*0.37,1.0)  # a scared flock must not beat in lockstep

func _sample(curve: Array, phase: float) -> float:
	if curve.is_empty(): return 0.0
	var count := curve.size()
	var x := fposmod(phase,1.0)*count
	var i := int(x)
	return lerpf(curve[i%count],curve[(i+1)%count],x-float(i))

# How hard the bird beats right now: a startled burst off the perch, then cruising
# wingbeats interrupted by short glides, and braking flaps just before it settles.
func _advance_flap(delta: float) -> void:
	var rate := 0.0
	var power := 0.0
	if owl:
		rate = 2.5
		power = 0.85
	elif flying > 0:
		var since := 10.0-flying
		if since < 1.5:
			rate = 7.6
			power = 1.0
		elif flying < 1.8:
			rate = 5.4
			power = 1.0
		else:
			rate = 4.4
			power = clampf(0.4+sin(since*0.85+index)*1.3,0.0,1.0)
	flap_phase = fposmod(flap_phase+delta*rate,1.0)
	flap_power = move_toward(flap_power,power,delta*(7.0 if power>flap_power else 2.5))
	# The library measures the wing against world up, the rig's roll axis points the other
	# way, so the curves are negated: the fast power stroke really goes downwards.
	flap_inner = -_sample(cycle.get("inner",[]),flap_phase)*flap_power*FLAP_GAIN
	flap_outer = -_sample(cycle.get("outer",[]),flap_phase)*flap_power*FLAP_GAIN
	flap_row = _sample(cycle.get("sweep",[]),flap_phase)*flap_power

func _pose_raven() -> void:
	if not skeleton or wing_bones.size()!=4: return
	var flight_blend := 1.0 if owl else clampf(minf((10.0-flying)*4.0,flying*3.0),0.0,1.0) if flying>0 else 0.0
	for i in 4:
		if wing_bones[i]<0: continue
		var side := 1.0 if i%2==0 else -1.0
		var tip := i>=2
		var roll := lerpf(0.42 if tip else 0.85,flap_outer if tip else flap_inner,flight_blend)
		var fold := (1.0-flight_blend)*(1.25 if tip else 0.85)+flight_blend*flap_row*(0.55 if tip else 0.2)
		skeleton.set_bone_pose_rotation(wing_bones[i],Quaternion.from_euler(Vector3(0,side*fold,side*roll)))
	# The body rides the beat: it sinks on the upstroke and is pushed up on the downstroke.
	if model_root: model_root.position.y = -flap_inner*0.05*flight_blend

func call_voice() -> void:
	if voice.playing: return
	if not owl:
		var choice := randi_range(0,RAVEN_CALLS.size()-2)
		if choice >= last_call: choice += 1
		choice %= RAVEN_CALLS.size()
		last_call = choice
		voice.stream = RAVEN_CALLS[choice]
		voice.pitch_scale = randf_range(0.96,1.04)
	voice.play()

func scare(origin: Vector3) -> void:
	if not visible or global_position.distance_to(origin)>24 or flying>0: return
	flying = 10.0
	call_voice()
func _process(delta: float) -> void:
	if not game.started or game.over or not game.day_night: return
	if game.intro and game.intro.active and game.intro.phase == "logo": return
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
		call_time = 15.0+(index%10)*1.7
		if game.player.global_position.distance_to(global_position)<45: call_voice()
	_advance_flap(delta)
	_pose_raven()
	var old := position
	if owl:
		position = home+Vector3(sin(clock*0.22)*12,2+sin(clock*0.4)*0.7,cos(clock*0.22)*8)
	elif flying>0:
		flying = maxf(0,flying-delta)
		var progress := (10.0-flying)/10.0
		position = home+Vector3(sin(progress*TAU)*8,sin(progress*PI)*8,(1-cos(progress*TAU))*5)
		if flying == 0: flight_wait = 12.0+(index%7)*2.3
	else:
		position = home
		flight_wait -= delta
		if flight_wait<=0: flying = 10.0
	# Keep flight paths above the sloping meadows and forest floor.
	position.y = maxf(position.y,Map.ground_height(position.x,position.z)+(4.0 if owl else 0.2))
	var motion := position-old
	if motion.length_squared()>0.00001: rotation.y = atan2(-motion.x,-motion.z)
	for i in wings.size():
		wings[i].rotation.z = (1 if i==0 else -1)*(flap_inner if owl or flying>0 else 1.1)
		wings[i].rotation.y = (1 if i==0 else -1)*flap_row*0.3 if owl or flying>0 else 0.0

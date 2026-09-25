# Sound effects. Prefers the recorded clips in assets/audio/sfx (from the user's sound library),
# falls back to short procedural bursts for anything without a file (hurt, wood, boom, ...).
class_name Sfx

const DIR := "res://assets/audio/sfx/"
const FOOTSTEPS := ["footstep1", "footstep2", "footstep3"]
const FireLoop = preload("res://scripts/weapon_fire_loop.gd")

# logical name -> list of file stems; one is picked at random per play for variety
const FILES := {
	"pistol": ["pistol"],
	"revolver": ["revolver"],
	"smg": ["smg"],
	"ak47": ["ak47"],
	"shotgun": ["shotgun"],
	# The eight supplied September 23 recordings, trimmed/normalized by build_weapon_audio.py.
	"deagle": ["weapons/deagle"],
	"flare": ["weapons/flare"],
	"mac10": ["weapons/mac10"],
	"cryo": ["weapons/cryo"],
	"cryo_freeze": ["weapons/cryo_freeze"],
	"plasma": ["weapons/plasma"],
	"plasma_vent": ["weapons/plasma_vent"],
	"lever": ["weapons/lever"],
	"lever_cycle": ["weapons/lever_cycle"],
	"minigun": ["weapons/minigun"],
	"minigun_spinup": ["weapons/minigun_spinup"],
	"minigun_loop": ["weapons/minigun_loop"],
	"minigun_spindown": ["weapons/minigun_spindown"],
	"graviton": ["weapons/graviton"],
	"graviton_impact": ["weapons/graviton_impact"],
	"graviton_charge": ["weapons/graviton_charge"],
	"reload": ["reload"],
	"empty": ["empty"],
	"click": ["click"],
	"confirm": ["confirm"],
	"menu": ["confirm_menu"],
	"pickup": ["gun_pick_up"],
	"key_pickup": ["key_Pickup"],
	"weapon_pickup": ["gun_pick_up"],
	"quest_accept": ["acceppt_1", "acceppt_2"],
	"quest_progress": ["confirm"],
	"quest_ready": ["quest_aaccept_Finish"],
	"quest_complete": ["quest_aaccept_Finish"],
	"purchase": ["gun_pick_up"],
	"vendor_vocal": ["vendor_vocal_1", "vendor_vocal_2", "vendor_vocal_3"],
	"secret_vendor_vocal": ["secret_vendor_vocal"],
	"mechanic_vocal": ["mechanic_vocal", "mechanic_vocal_2", "mechanic_vocal_3"],
	"mara_morning": ["mara_sfx_good_morning"],
	"mara_day": ["mara_sfx_hello"],
	"mara_evening": ["mara_sfx_good_evening"],
	"mara_night": ["mara_sfx_good_night"],
	"door_open": ["door_open"],
	"owl": ["owl1", "owl2", "owl3", "owl4"],
	"raven": ["raven_1", "raven2", "raven3"],
	"hit": ["impact"],
	"hurt": ["hurt_1", "hurt_2", "hurt_3", "hurt_4", "hurt_5"],
	"player_death": ["player_death_1", "player_death_2"],
	"zombie_death": ["zombie_death_1", "zombie_death_2", "zombie_death_3", "zombie_death_4"],
	"melee": ["melee_1", "melee_2", "melee_3"],
	"melee_stab": ["melee_stab_1", "melee_stab_2"],
	"knife_swing": ["knife_leftklick"],
	"wood_hit": ["wood_hit_1", "wood_hit_2", "wood_hit_3", "wood_hit_4", "wood_hit_5"],
	"build": ["build_1", "build_2", "build_3", "build_4", "build_5"],
	"crash": ["crash"],
	"pumpkin_splat": ["pumpkin_splat"],
	"head_burst": ["head_burst_1", "head_burst_2", "head_burst_3", "head_burst_4", "head_burst_5"],
	"boom": ["boom"],
	"grenade_throw": ["grenade_throw"],
	"grenade_bounce": ["grenade_bounce_1", "grenade_bounce_2", "grenade_bounce_3"],
	"heartbeat": ["heartbeat"],
	"land": ["land"],
	"weapon_switch": ["weapon_switch_1", "weapon_switch_2"],
	"flashlight": ["flashlight"],
	"hover": ["hover_1", "hover_2", "hover_3"],
	"achievement": ["achievement"],
	"streak": ["streak"],
	"consume": ["consume_1", "consume_2", "consume_3"],
	"mushroom_pickup": ["mushroom_pickup"],
	"rustle": ["rustle"],
	"door_close": ["door_close_1", "door_close_2", "door_close_3"],
	"door_locked": ["door_locked"],
	"hut_collapse": ["hut_collapse"],
	"hut_under_attack": ["hut_under_attack"],
	"growl": ["zombie_1", "zombie_2", "zombie_3", "zombie_4"],
	"barricade_break": ["barricade_break_1", "barricade_break_2", "barricade_break_3", "barricade_break_4"],
	"wave": ["wave_start"],
	# 26 Sep 2026: weather, callouts and the special infected (tools/build_weather_audio.py)
	"rain": ["secret_rain"],
	"thunder": ["thunder_1", "thunder_2", "thunder_3"],
	"radio": ["radio_ping"],
	"screamer_call": ["screamer_call"],
	"acid_spit": ["acid_spit"],
	"acid_splash": ["acid_splash"],
	"helmet_ping": ["helmet_ping"],
	"step_gravel": FOOTSTEPS,
	"step_grass": FOOTSTEPS,
	"step_leaves": FOOTSTEPS,
	"step": FOOTSTEPS,
}

# Footsteps per surface. The three recorded clips are a boot on a hard road; every softer ground plays them
# through its own bus with a low-pass filter (duller thud, fewer dB) and layers a short procedural texture on
# top: grass swish, leaf-litter crackle, gravel grit, a hollow knock on the hut's wooden floor.
# surface -> [bus name, low-pass cutoff Hz, base clip dB offset, texture dB offset]
const STEP_SURFACES := {
	"hard":   ["Master", 0.0, 0.0, -99.0],
	"gravel": ["StepGravel", 2600.0, -2.0, -5.0],
	"grass":  ["StepGrass", 1400.0, -5.0, -1.0],
	"leaves": ["StepSoft", 800.0, -6.0, -2.0],
	"wood":   ["StepWood", 1800.0, -1.0, -4.0],
	# Soft field soil under the boot, but the dry maize blades brushing past are what you hear.
	"corn":   ["StepCorn", 1000.0, -8.0, 1.5],
}
static var _buses_ready := false

static var _cache: Dictionary = {}
static var _rng := RandomNumberGenerator.new()
static var _last_footstep := -1
static var _last_event_variant: Dictionary = {}
const EVENTS := {"consume": -8.0, "pickup": -8.0, "mushroom_pickup": -10.0, "key_pickup": -6.0, "weapon_pickup": -8.0, "quest_accept": -10.0, "quest_complete": -8.0, "purchase": -12.0,
	"quest_progress": -14.0, "quest_ready": -10.0,
	"vendor_vocal": -3.0, "secret_vendor_vocal": -3.0, "mechanic_vocal": -3.0, "achievement": -5.0,
	"mara_morning": -3.0, "mara_day": -3.0, "mara_evening": -3.0, "mara_night": -3.0}
static var _voices: Dictionary = {}        # name -> Array of live players; automatic fire never stacks more than MAX_VOICES
const MAX_VOICES := 3
static var _voice_frame := -1
static var _voice_counts: Dictionary = {}

static func _allow_voice(name: String) -> bool:
	var frame := Engine.get_process_frames()
	if frame != _voice_frame:
		_voice_frame = frame
		_voice_counts.clear()
	var count: int = _voice_counts.get(name, 0)
	if count >= MAX_VOICES: return false
	_voice_counts[name] = count + 1
	return true

# Prepare every variant, including procedural footsteps, while loading. Picking
# one random clip here used to leave the remaining variants cold during combat.
static func prewarm() -> void:
	for name: String in FILES:
		for stem: String in FILES[name]:
			if not _file(stem) and not _cache.has(name): _cache[name] = _procedural(name)
	for name in ["hurt_thud", "tower_flame", "tower_tesla", "wood"]:
		if not _cache.has(name): _cache[name] = _procedural(name)
	_ensure_step_buses()
	for surface: String in STEP_SURFACES:
		for variant in 3: _step_texture(surface, variant)

static func _wav(samples: PackedFloat32Array, rate: int = 22050) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	return wav

static func _burst(dur: float, decay: float, lowpass: float, gain: float, tone: float = 0.0, slide: float = 0.0) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var env := exp(-t / decay)
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * lowpass
		var v := lp * env * gain
		if tone > 0.0:
			var f := tone + slide * t
			phase += TAU * f / rate
			v += sin(phase) * env * gain * 0.6
		s[i] = v
	return _wav(s, rate)

static func _procedural(name: String) -> AudioStreamWAV:
	match name:
		"tower_flame": return _burst(0.18,0.1,0.9,0.4,65.0,20.0)
		"tower_tesla": return _burst(0.3,0.08,0.4,0.45,800.0,-1200.0)
		"pistol": return _burst(0.25, 0.05, 0.6, 1.0, 160.0, -400.0)
		"shotgun": return _burst(0.45, 0.12, 0.35, 1.2, 80.0, -120.0)
		"reload": return _burst(0.12, 0.03, 0.9, 0.3, 900.0, 0.0)
		"empty": return _burst(0.05, 0.01, 0.9, 0.25, 1200.0, 0.0)
		"hit": return _burst(0.12, 0.04, 0.2, 0.5)
		"hurt": return _burst(0.4, 0.15, 0.15, 0.6, 120.0, -100.0)
		"hurt_thud": return _burst(0.35, 0.09, 0.04, 0.9, 60.0, -40.0)
		"growl": return _burst(0.8, 0.35, 0.05, 0.35, 70.0 + _rng.randf() * 50.0, -20.0)
		"build": return _burst(0.2, 0.06, 0.4, 0.5, 220.0, 0.0)
		"wave": return _burst(1.4, 0.6, 0.02, 0.4, 110.0, 30.0)
		"wood": return _burst(0.3, 0.1, 0.3, 0.8)
		"rustle": return _burst(0.5, 0.18, 0.75, 0.35)   # leaves, a deer bolting
		"mushroom_pickup": return _burst(0.28, 0.08, 0.12, 0.45) # soft plucking/rustle, no weapon clicks or metallic tone
		"boom": return _burst(1.6, 0.45, 0.05, 1.4, 45.0, -30.0)
		"pickup", "consume": return _burst(0.2, 0.08, 0.9, 0.3, 660.0, 800.0)
		"step_gravel": return _burst(0.14, 0.035, 0.55, 0.42)
		"step": return _burst(0.14, 0.035, 0.55, 0.42)
		"step_grass": return _burst(0.16, 0.05, 0.22, 0.26)
		"step_leaves": return _burst(0.18, 0.06, 0.32, 0.34)
		"heartbeat": return _burst(0.32, 0.07, 0.03, 1.0, 48.0, -25.0)
		"streak": return _burst(0.18, 0.06, 0.8, 0.3, 880.0, 400.0)
		"melee": return _burst(0.22, 0.05, 0.25, 0.7, 90.0, -60.0)
		"thunder": return _burst(2.6, 0.9, 0.03, 0.9, 42.0, -14.0)
		"radio": return _burst(0.12, 0.03, 0.8, 0.35, 1760.0, 0.0)
		"screamer_call": return _burst(1.6, 0.5, 0.35, 0.7, 700.0, 500.0)
		"acid_spit": return _burst(0.4, 0.12, 0.6, 0.5, 120.0, -60.0)
		"acid_splash": return _burst(0.6, 0.2, 0.5, 0.6)
		"helmet_ping": return _burst(0.5, 0.12, 0.95, 0.5, 2300.0, -300.0)
	return _burst(0.1, 0.03, 0.5, 0.3)

static func _file(stem: String) -> AudioStream:
	var key := "file:" + stem
	if _cache.has(key):
		return _cache[key]
	var st: AudioStream = null
	for ext: String in [".mp3", ".ogg", ".wav"]:
		var path := DIR + stem + ext
		if ResourceLoader.exists(path):
			st = load(path)
			break
	_cache[key] = st
	return st

static func get_stream(name: String) -> AudioStream:
	if FILES.has(name):
		var variants: Array = FILES[name]
		var index := _rng.randi_range(0, variants.size() - 1)
		if EVENTS.has(name) and variants.size() > 1:
			var previous: int = _last_event_variant.get(name, -1)
			if previous >= 0: index = (previous + _rng.randi_range(1, variants.size() - 1)) % variants.size()
			_last_event_variant[name] = index
		if variants == FOOTSTEPS:
			# Share the previous variant across surfaces and landings.
			if _last_footstep >= 0:
				index = (_last_footstep + _rng.randi_range(1, variants.size() - 1)) % variants.size()
			_last_footstep = index
		var st := _file(variants[index])
		if st:
			return st
	if _cache.has(name):
		return _cache[name]
	var p := _procedural(name)
	_cache[name] = p
	return p

# slight random pitch so repeated clips (shots, growls) do not sound machine-like
static func _pitch(spread: float) -> float:
	return 1.0 + _rng.randf_range(-spread, spread)

static func event(node: Node, peer_id: int, name: String) -> void:
	if not EVENTS.has(name): return
	if NetSession.enabled:
		if NetSession.is_host(): NetSession.feedback(peer_id, "sfx", [name])
	else:
		play(node, name, EVENTS[name])

static func play(node: Node, name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if name == "minigun":
		_sustain_fire(node, false, volume_db, pitch)
		return
	if not _allow_voice(name): return
	var p := _voice(node, name, false) as AudioStreamPlayer
	p.stream = get_stream(name)
	p.volume_db = volume_db
	p.pitch_scale = pitch if EVENTS.has(name) else pitch * _pitch(0.04)
	p.process_mode = Node.PROCESS_MODE_ALWAYS if EVENTS.has(name) else Node.PROCESS_MODE_INHERIT
	p.play()

static func _voice(parent: Node, name: String, spatial: bool) -> Node:
	var list: Array = _voices.get(name, [])
	var live: Array = []
	var available: Node
	for v in list:
		if is_instance_valid(v) and v.is_inside_tree() and not v.is_queued_for_deletion():
			live.append(v)
			if not v.playing and not available: available = v
	if not available:
		available = live[0] if live.size() >= MAX_VOICES else (AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new())
	available.stop()
	live.erase(available)
	live.append(available)
	if not available.get_parent(): parent.add_child(available)
	elif available.get_parent() != parent: available.reparent(parent, false)
	_voices[name] = live
	return available

static func play_at(node: Node, name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0, unit_size: float = 10.0, max_distance: float = 60.0) -> void:
	if name == "minigun":
		_sustain_fire(node, true, volume_db, pitch, pos, unit_size, max_distance)
		return
	if not _allow_voice("3d:" + name): return
	var p := _voice(node, "3d:" + name, true) as AudioStreamPlayer3D
	p.stream = get_stream(name)
	p.volume_db = volume_db
	p.pitch_scale = pitch * _pitch(0.08)
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.global_position = pos
	p.play()

static func _sustain_fire(node: Node, spatial: bool, volume: float, pitch: float, point := Vector3.ZERO, unit_size := 10.0, max_distance := 60.0) -> void:
	var key := "MinigunFire3D" if spatial else "MinigunFire"
	var loop = node.get_node_or_null(key)
	if loop == null:
		var stream := get_stream("minigun") as AudioStreamWAV
		if not stream: return
		loop = FireLoop.new()
		loop.name = key
		node.add_child(loop)
		loop.configure(stream, spatial)
	loop.shot(volume, pitch, point, unit_size, max_distance)

static func stop_fire_loop(node: Node, immediately := true) -> void:
	for key in ["MinigunFire", "MinigunFire3D"]:
		var loop = node.get_node_or_null(key)
		if loop:
			if immediately: loop.stop()
			else: loop.release()

# ---------------------------------------------------------------- footsteps
static func _ensure_step_buses() -> void:
	if _buses_ready:
		return
	_buses_ready = true
	for key in STEP_SURFACES:
		var spec: Array = STEP_SURFACES[key]
		if spec[0] == "Master" or AudioServer.get_bus_index(spec[0]) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, spec[0])
		AudioServer.set_bus_send(idx, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = spec[1]
		lp.resonance = 0.55
		AudioServer.add_bus_effect(idx, lp)

# Band-limited noise with a fast attack and a decay, optional crackle transients (leaf litter, grit) and an
# optional low resonant knock (hollow wood). lp / hp are one-pole coefficients at 22.05 kHz.
static func _texture(dur: float, attack: float, decay: float, lp: float, hp: float, gain: float, crackles: int, knock_hz: float, seed_v: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var l := 0.0
	var l2 := 0.0
	var h := 0.0
	var pops: Array = []
	for k in crackles:
		pops.append([int(rng.randf_range(0.004, dur * 0.65) * rate), rng.randf_range(0.35, 1.0), rng.randf_range(14.0, 40.0)])
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var env := (1.0 - exp(-t / attack)) * exp(-t / decay)
		var w := rng.randf_range(-1.0, 1.0)
		# two cascaded one-pole low-passes (12 dB/oct) so the hiss really stays below the cutoff
		l += (w - l) * lp
		l2 += (l - l2) * lp
		var v := l2 - h
		h += (l2 - h) * hp
		var out := v * env * gain
		for p in pops:
			var dt := i - int(p[0])
			if dt >= 0 and dt < 120:
				out += l2 * float(p[1]) * gain * 2.2 * exp(-dt / float(p[2]))
		if knock_hz > 0.0:
			phase += TAU * knock_hz * (1.0 - 0.25 * t) / rate
			out += sin(phase) * exp(-t / 0.045) * gain * 0.9
		s[i] = out
	return _wav(s, rate)

# Looping bed for walking through standing maize: a papery brush of leaves along the body with
# irregular slaps of stiff blades snapping back. The caller fades it with the walking speed.
static func corn_bed(seed_v: int = 17) -> AudioStreamWAV:
	var key := "cornbed:%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var rate := 22050
	var n := int(6.0 * rate)
	var blend := mini(int(0.25 * rate), n / 2)
	var s := PackedFloat32Array()
	s.resize(n + blend)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var l := 0.0
	var l2 := 0.0
	var h := 0.0
	var wobble := 0.0
	var slap := 1.0
	var slap_gain := 0.0
	var slap_decay := 1.0
	var next_slap := 0
	for i in s.size():
		var w := rng.randf_range(-1.0, 1.0)
		l += (w - l) * 0.5
		l2 += (l - l2) * 0.5
		var v := l2 - h
		h += (l2 - h) * 0.12
		wobble += (rng.randf_range(-1.0, 1.0) - wobble) * 0.004
		var out := v * (0.5 + clampf(wobble * 3.0, -0.35, 0.45)) * 0.5
		if i >= next_slap:
			next_slap = i + int(rng.randf_range(0.03, 0.17) * rate)
			slap_gain = rng.randf_range(0.4, 1.0)
			slap_decay = rng.randf_range(0.004, 0.02) * rate
			slap = 0.0
		slap += 1.0
		out += v * slap_gain * exp(-slap / slap_decay) * 1.6
		s[i] = out / (1.0 + absf(out) / 0.7)
	# Blend the tail into the head so the loop itself cannot click.
	for i in blend:
		var t := smoothstep(0.0, 1.0, float(i) / maxf(blend - 1, 1))
		s[i] = lerpf(s[n + i], s[i], t)
	s.resize(n)
	var wav := _wav(s, rate)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	_cache[key] = wav
	return wav

static func _step_texture(surface: String, variant: int) -> AudioStream:
	var key := "steptex:%s:%d" % [surface, variant]
	if _cache.has(key):
		return _cache[key]
	var seed_v := hash(key)
	var st: AudioStreamWAV = null
	match surface:
		"grass": st = _texture(0.26, 0.028, 0.08, 0.34, 0.1, 0.9, 2, 0.0, seed_v)       # soft swish, body ~0.5-1.5 kHz
		"leaves": st = _texture(0.24, 0.010, 0.085, 0.4, 0.08, 0.72, 8, 0.0, seed_v)     # dry crackle, duller body
		"gravel": st = _texture(0.15, 0.005, 0.045, 0.55, 0.18, 0.36, 14, 0.0, seed_v)   # fine grit, brighter
		"wood": st = _texture(0.2, 0.004, 0.05, 0.25, 0.04, 0.5, 0, 150.0, seed_v)      # hollow knock
		"corn": st = _texture(0.40, 0.014, 0.14, 0.46, 0.11, 0.85, 5, 0.0, seed_v)      # long papery swish of leaves
	_cache[key] = st
	return st

# One footstep (or landing) on `surface`: "hard" | "gravel" | "grass" | "leaves" | "wood".
static func footstep(node: Node, surface: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_ensure_step_buses()
	var spec: Array = STEP_SURFACES.get(surface, STEP_SURFACES["hard"])
	var base := AudioStreamPlayer.new()
	base.stream = get_stream("step")
	base.bus = spec[0]
	base.volume_db = volume_db + float(spec[2])
	base.pitch_scale = pitch * _pitch(0.05) * (0.9 if surface == "leaves" else (0.95 if surface == "grass" else 1.0))
	node.add_child(base)
	base.play()
	base.finished.connect(base.queue_free)
	var tex := _step_texture(surface, _rng.randi_range(0, 2))
	if tex:
		var layer := AudioStreamPlayer.new()
		layer.stream = tex
		layer.volume_db = volume_db + float(spec[3])
		layer.pitch_scale = _pitch(0.12)
		node.add_child(layer)
		layer.play()
		layer.finished.connect(layer.queue_free)

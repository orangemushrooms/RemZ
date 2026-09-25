# Weather (26 Sep 2026): rain that soaks the ground and the leaves, fog banks drifting over the meadow and a
# thunderstorm whose lightning lights the whole forest for a moment and makes every zombie glow, so the
# horde stands out against the dark. The host (or the solo game) plans one schedule per game day and
# decides every state change and every bolt; clients mirror the state and the bolt count from the
# snapshot ("weather") and play their own flash and thunder from it. Effects touch only what already
# exists: the sun and fill of the day cycle (weather_dim / overcast), the fog of the environment, one
# GPUParticles3D of rain streaks around the camera, four FogVolumes, the wetness global of the ground,
# leaf and bark shaders (remz_wetness) and a rain loop on top of the wind. "--weather=<state>" pins a
# state for tests and screenshots, the cheat menu does the same at run time.
class_name Weather
extends Node

const STATES := ["clear", "fog", "rain", "storm"]
const FADE_SECONDS := 8.0          # a state takes this long to reach full strength
const SOAK_SECONDS := 28.0         # rain until the ground is fully wet
const DRY_SECONDS := 110.0         # and this long to dry again
const RAIN_DB := -25.0   # a quarter of the first cut (user, 25 Sep 2026 evening, twice "too loud")
const BOLT_MIN := 5.0
const BOLT_MAX := 15.0
const REVEAL_SECONDS := 0.45       # how long the horde glows after a bolt
const BANK_COUNT := 4
const DIM := {"clear": 0.0, "fog": 0.22, "rain": 0.45, "storm": 0.62}
const OVERCAST := {"clear": 0.0, "fog": 0.55, "rain": 0.85, "storm": 0.95}
const RAIN_AMOUNT := {"clear": 0.0, "fog": 0.0, "rain": 0.62, "storm": 1.0}

var main: Node
var state := "clear"
var intensity := 0.0               # 0..1 presence of the current state's effects (smoothed)
var wetness := 0.0
var wind := Vector2(0.8, 0.35)
var lightning_serial := 0          # host: bolts so far; everyone plays a bolt when it grows
var forced := ""                   # "" or a pinned state
var day_count := 0
var flash := 0.0                   # 0..1 current lightning brightness
var thunder_count := 0             # diagnostics
var _schedule: Array = []          # [{start, end, state}] in clock seconds of the current day
var _shown_lightning := 0
var _flash_t := 0.0
var _flash_len := 0.0
var _flicker := 0.0
var _next_bolt := 8.0
var _thunder: Array = []           # [delay left, position, volume, pitch]
var _rain: GPUParticles3D
var _rain_audio: AudioStreamPlayer
var _banks: Array[FogVolume] = []
var _bank_drift: Array[Vector2] = []
var _sky: ShaderMaterial
var _env: Environment
var _rng := RandomNumberGenerator.new()
var _decide_t := 0.0
var _prev_hour := -1.0
var _sun_restore := false

func setup(game: Node) -> void:
	main = game
	_env = main.settings.env
	_sky = _env.sky.sky_material if _env.sky else null
	_rng.seed = hash(str(Time.get_ticks_usec())) if not "--smoke-test" in OS.get_cmdline_user_args() else 4242
	for flag in OS.get_cmdline_user_args():
		if flag.begins_with("--weather="):
			var wanted := flag.get_slice("=", 1)
			if wanted in STATES: forced = wanted
	_build_rain()
	_build_banks()
	_plan_day(0)
	if forced != "": _enter(forced, true)

# ---------------------------------------------------------------- planning (host / solo)
# Day 0 is scripted so every run meets the weather: morning fog, rain from the late afternoon with a
# storm across the dusk. Later days roll fog (55 %), rain (50 %) and a storm inside a third of the rains.
func _plan_day(day: int) -> void:
	day_count = day
	_schedule.clear()
	if day == 0:
		_schedule.append({"start": 6.3 * 3600.0, "end": 8.0 * 3600.0, "state": "fog"})
		_schedule.append({"start": 16.5 * 3600.0, "end": 18.0 * 3600.0, "state": "rain"})
		_schedule.append({"start": 18.0 * 3600.0, "end": 19.4 * 3600.0, "state": "storm"})
		_schedule.append({"start": 19.4 * 3600.0, "end": 20.6 * 3600.0, "state": "rain"})
		return
	if _rng.randf() < 0.55:
		var start := _rng.randf_range(3.5, 7.0) * 3600.0
		_schedule.append({"start": start, "end": start + _rng.randf_range(1.5, 3.5) * 3600.0, "state": "fog"})
	if _rng.randf() < 0.5:
		var start := _rng.randf_range(11.0, 22.0) * 3600.0
		var length := _rng.randf_range(2.0, 5.0) * 3600.0
		if _rng.randf() < 0.36:
			var mid := start + length * 0.35
			_schedule.append({"start": start, "end": mid, "state": "rain"})
			_schedule.append({"start": mid, "end": mid + length * 0.35, "state": "storm"})
			_schedule.append({"start": mid + length * 0.35, "end": start + length, "state": "rain"})
		else:
			_schedule.append({"start": start, "end": start + length, "state": "rain"})
	if _rng.randf() < 0.25:
		var start := _rng.randf_range(20.5, 23.0) * 3600.0
		_schedule.append({"start": start, "end": start + _rng.randf_range(1.0, 2.5) * 3600.0, "state": "fog"})

func scheduled_state(clock_seconds: float) -> String:
	# entries may run past midnight (end > 24 h): the next day's early hours still belong to them
	for entry in _schedule:
		var t := clock_seconds
		if t < float(entry.start) and float(entry.end) > DayNightCycle.DAY_SECONDS: t += DayNightCycle.DAY_SECONDS
		if t >= float(entry.start) and t < float(entry.end): return str(entry.state)
	return "clear"

func schedule() -> Array:
	return _schedule.duplicate(true)

# ---------------------------------------------------------------- state
func _enter(next: String, immediate := false) -> void:
	if next == state and not immediate: return
	state = next
	if immediate:
		intensity = 0.0 if state == "clear" else 1.0
		if state in ["rain", "storm"]: wetness = 1.0
	if state == "storm": _next_bolt = _rng.randf_range(2.0, 6.0)

func force(next: String) -> void:
	if not next in STATES: return
	forced = next
	if not NetSession.is_client(): _enter(next)

func release() -> void:
	forced = ""

func is_raining() -> bool:
	return state in ["rain", "storm"] and intensity > 0.2

func is_foggy() -> bool:
	return state == "fog" and intensity > 0.2

func is_storm() -> bool:
	return state == "storm" and intensity > 0.2

# Stalkers only come out of the maize when the field is hidden: fog, rain, a storm or the night.
func hides_stalkers() -> bool:
	if state != "clear" and intensity > 0.3: return true
	return main.day_night != null and main.day_night.is_night()

func label() -> String:
	if intensity < 0.15 or state == "clear": return ""
	return {"fog": "Fog", "rain": "Rain", "storm": "Thunderstorm"}[state]

func snapshot() -> Array:
	return [state, intensity, wind.x, wind.y, lightning_serial, wetness, day_count]

func apply_snapshot(data: Array, initial: bool) -> void:
	if data.size() < 6: return
	if str(data[0]) in STATES and str(data[0]) != state: _enter(str(data[0]))
	if initial:
		intensity = float(data[1])
		wetness = float(data[5])
		_shown_lightning = int(data[4])
	wind = Vector2(float(data[2]), float(data[3]))
	lightning_serial = int(data[4])
	if data.size() > 6: day_count = int(data[6])

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if not main or not main.started or main.over or get_tree().paused: return
	var day_night: DayNightCycle = main.day_night
	if not NetSession.is_client() and day_night:
		var hour: float = day_night.clock_seconds / 3600.0
		if _prev_hour >= 0.0 and hour >= 5.0 and (_prev_hour < 5.0 or _prev_hour > hour + 12.0):
			_plan_day(day_count + 1)
		_prev_hour = hour
		_decide_t -= delta
		if _decide_t <= 0.0:
			_decide_t = 0.5
			var wanted := forced if forced != "" else scheduled_state(day_night.clock_seconds)
			var quiet: bool = (main.intro and main.intro.active) or (main.secret_night and main.secret_night.active)
			if quiet and forced == "": wanted = "clear"
			_enter(wanted)
		if state == "storm" and intensity > 0.5:
			_next_bolt -= delta
			if _next_bolt <= 0.0:
				_next_bolt = _rng.randf_range(BOLT_MIN, BOLT_MAX)
				lightning_serial += 1
	# presence of the state's effects fades in and out; wet ground soaks and dries at its own pace
	var target := 0.0 if state == "clear" else 1.0
	intensity = move_toward(intensity, target, delta / FADE_SECONDS)
	var raining := state in ["rain", "storm"] and intensity > 0.05
	wetness = move_toward(wetness, 1.0 if raining else 0.0, delta / (SOAK_SECONDS if raining else DRY_SECONDS))
	RenderingServer.global_shader_parameter_set("remz_wetness", wetness)
	_apply_environment(delta)
	_update_rain(delta)
	_update_banks(delta)
	if lightning_serial > _shown_lightning:
		_shown_lightning = lightning_serial
		_strike(lightning_serial)
	_update_flash(delta)
	_update_thunder(delta)

func _apply_environment(delta: float) -> void:
	var day_night: DayNightCycle = main.day_night
	if not day_night or not _env: return
	var k := intensity
	day_night.weather_dim = 1.0 - float(DIM[state]) * k
	day_night.overcast = float(OVERCAST[state]) * k
	# the intro and the secret night drive the fog themselves
	var quiet: bool = (main.intro and main.intro.active) or (main.secret_night and main.secret_night.active)
	if quiet: return
	var fog_target := 0.0032
	var vfog_target := 0.0025
	match state:
		"fog":
			fog_target = lerpf(0.0032, 0.012, k)
			vfog_target = lerpf(0.0025, 0.011, k)
		"rain":
			fog_target = lerpf(0.0032, 0.0055, k)
			vfog_target = lerpf(0.0025, 0.0045, k)
		"storm":
			fog_target = lerpf(0.0032, 0.007, k)
			vfog_target = lerpf(0.0025, 0.006, k)
	_env.fog_density = lerpf(_env.fog_density, fog_target, minf(1.0, delta * 0.8))
	_env.volumetric_fog_density = lerpf(_env.volumetric_fog_density, vfog_target, minf(1.0, delta * 0.8))

# ---------------------------------------------------------------- rain
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(20.0, 7.0, 20.0)
	process.direction = Vector3(0.12, -1.0, 0.05)
	process.spread = 2.0
	process.initial_velocity_min = 11.0
	process.initial_velocity_max = 14.0
	process.gravity = Vector3(0, -6.0, 0)
	process.scale_min = 0.8
	process.scale_max = 1.3
	_rain.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.42)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.72, 0.8, 0.92, 0.3)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = false
	quad.material = material
	_rain.draw_pass_1 = quad
	_rain.amount = 2400
	_rain.lifetime = 1.5
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	_rain.emitting = false
	_rain.amount_ratio = 0.0
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.name = "RainLoop"
	_rain_audio.stream = Sfx.get_stream("rain")
	if _rain_audio.stream is AudioStreamWAV:
		var loop := (_rain_audio.stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_end = loop.data.size() / 2
		_rain_audio.stream = loop
	_rain_audio.volume_db = -60.0
	add_child(_rain_audio)

func _update_rain(delta: float) -> void:
	if not _rain: return
	var amount := float(RAIN_AMOUNT[state]) * intensity
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera:
		var at := camera.global_position + Vector3(wind.x, 0.0, wind.y) * -3.0
		_rain.global_position = Vector3(at.x, at.y + 6.0, at.z)
		var process := _rain.process_material as ParticleProcessMaterial
		process.direction = Vector3(wind.x * 0.18, -1.0, wind.y * 0.18)
	_rain.amount_ratio = clampf(amount, 0.0, 1.0)
	if amount > 0.02 and not _rain.emitting: _rain.emitting = true
	elif amount <= 0.02 and _rain.emitting: _rain.emitting = false
	if _rain_audio:
		var target := -60.0
		if amount > 0.02:
			target = RAIN_DB + linear_to_db(maxf(amount, 0.05))
			# under the hut roof the rain drums outside; the loop is muffled a little
			var p: Node3D = main.player
			if p and Map.in_building(p.global_position.x, p.global_position.z): target -= 7.0
			if not _rain_audio.playing: _rain_audio.play(_rng.randf() * 6.0)
		elif _rain_audio.playing and _rain_audio.volume_db <= -58.0:
			_rain_audio.stop()
		_rain_audio.volume_db = lerpf(_rain_audio.volume_db, target, minf(1.0, delta * 1.5))

# ---------------------------------------------------------------- fog banks
func _build_banks() -> void:
	var material := FogMaterial.new()
	material.density = 0.0
	material.albedo = Color(0.78, 0.8, 0.82)
	material.emission = Color(0.06, 0.07, 0.08)
	material.edge_fade = 0.35
	for i in BANK_COUNT:
		var bank := FogVolume.new()
		bank.name = "FogBank%d" % i
		bank.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		bank.size = Vector3(46.0 + i * 8.0, 7.0, 26.0 + i * 5.0)
		bank.material = material
		bank.visible = false
		add_child(bank)
		_banks.append(bank)
		_bank_drift.append(Vector2.ZERO)
		bank.position = Map.ground_pos(Map.FIRE.x + [40, -55, 20, -30][i], Map.FIRE.y + [70, 30, -90, 95][i]) + Vector3.UP * 2.5

func _update_banks(delta: float) -> void:
	if _banks.is_empty(): return
	var density := 0.0
	match state:
		"fog": density = 0.075 * intensity
		"storm": density = 0.018 * intensity
		"rain": density = 0.012 * intensity
	var material := _banks[0].material as FogMaterial
	material.density = density
	var show := density > 0.001
	var p: Node3D = main.player
	for i in _banks.size():
		var bank := _banks[i]
		if bank.visible != show: bank.visible = show
		if not show or not p: continue
		# banks drift with the wind and are carried back around the player when they wander off
		var drift := Vector2(wind.x, wind.y) * (0.9 + 0.25 * i) * delta
		bank.position.x += drift.x
		bank.position.z += drift.y
		var flat := Vector2(bank.position.x - p.global_position.x, bank.position.z - p.global_position.z)
		if flat.length() > 150.0:
			var back := -Vector2(wind.x, wind.y).normalized() * 110.0 + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40))
			bank.position.x = p.global_position.x + back.x
			bank.position.z = p.global_position.z + back.y
		bank.position.y = Map.ground_height(bank.position.x, bank.position.z) + 2.5

# ---------------------------------------------------------------- lightning
# Every bolt is replayed from its serial on every peer: the same seed picks the same distance and
# direction, so the flash timing and the thunder delay agree between host and clients.
func _strike(serial: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = serial * 7919 + 13
	var distance := rng.randf_range(80.0, 520.0)
	var azimuth := rng.randf() * TAU
	var p: Node3D = main.player
	var origin: Vector3 = (p.global_position if p else Vector3.ZERO) + Vector3(cos(azimuth), 0.0, sin(azimuth)) * distance + Vector3.UP * 60.0
	_flash_len = 0.32 + rng.randf() * 0.28
	_flash_t = _flash_len
	_flicker = rng.randf_range(0.5, 1.0)
	var volume := clampf(-2.0 - distance / 45.0, -20.0, -2.0)
	_thunder.append([distance / 343.0 + 0.12, origin, volume, rng.randf_range(0.85, 1.15), distance])
	# the horde glows for a moment: every zombie in the world, near or far
	for z in main.zombies_root.get_children():
		if z is Zombie and z.alive: z.lightning_reveal(REVEAL_SECONDS)
	_sun_restore = true

func _update_flash(delta: float) -> void:
	if _flash_t <= 0.0:
		if _sun_restore:
			_sun_restore = false
			flash = 0.0
			if _sky: _sky.set_shader_parameter("flash", 0.0)
			if main.day_night: main.day_night._apply_lighting(false)
		return
	_flash_t -= delta
	var t := 1.0 - _flash_t / _flash_len
	# two flickers: bright at the start, a second surge a third of the way in
	var level := maxf(exp(-t * 6.0), _flicker * exp(-absf(t - 0.35) * 14.0)) * (1.0 - t * 0.4)
	flash = clampf(level, 0.0, 1.0)
	if _sky: _sky.set_shader_parameter("flash", flash * 0.9)
	var sun: DirectionalLight3D = main.settings.sun
	var fill: DirectionalLight3D = main.fill_light
	if sun: sun.light_energy = maxf(sun.light_energy, flash * 9.0)
	if fill:
		fill.light_energy = maxf(fill.light_energy, flash * 3.0)
		fill.light_color = fill.light_color.lerp(Color(0.85, 0.9, 1.0), flash)
	if _env: _env.ambient_light_energy = maxf(_env.ambient_light_energy, 1.0 + flash * 2.5)

func _update_thunder(delta: float) -> void:
	for i in range(_thunder.size() - 1, -1, -1):
		var entry: Array = _thunder[i]
		entry[0] -= delta
		if entry[0] > 0.0: continue
		_thunder.remove_at(i)
		thunder_count += 1
		Sfx.play_at(self, "thunder", entry[1], float(entry[2]), float(entry[3]), 240.0, 1400.0)
		var p: Player = main.player
		if p: p.add_tremor(clampf(0.45 - float(entry[4]) / 900.0, 0.08, 0.45), 1.6)

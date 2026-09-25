class_name DayNightCycle
extends Node

const DAY_SECONDS := 86400.0
const MORNING_SECONDS := 6.0 * 3600.0
const LIGHT_UPDATE_SECONDS := 0.1
const SKY_UPDATE_GAME_SECONDS := 30.0
const SKY_MIN_UPDATE_SECONDS := 1.0
const DAY_START := 5.0 * 3600.0
const NIGHT_START := 20.0 * 3600.0
const DUSK_END_HOUR := 21.0
# Keep the full cycle at 15 real minutes: 10.5 minutes from morning to evening,
# 4.5 minutes of night. Clock hours still drive lighting, wildlife and NPCs.
const DAY_DURATION_FACTOR := 1.12
const NIGHT_DURATION_FACTOR := 0.8

# Requested gameplay (user, 17.9.2026): one full day lasts 15 real minutes, the game starts at 06:00 and the
# clock runs on through the waves so the night actually arrives. reset_each_wave = true restores the old
# "every wave starts in the morning" behaviour.
const CONTINUOUS_DAY_MINUTES := 15.0
# Moon phases and the blood moon (26 Sep 2026): every night that begins (the clock crossing 20:00) counts;
# the phase runs over MOON_CYCLE nights (0 new, half way full), and every BLOOD_MOON_EVERY-th night the
# moon rises blood red: the horde runs BLOOD_MOON_PACE times faster and every kill pays double
# (main._zombie_killed). Weather (weather.gd) dims the sun through weather_dim / overcast.
const MOON_CYCLE := 8
const BLOOD_MOON_EVERY := 5
const BLOOD_MOON_PACE := 1.25
const BLOOD_MOON_TINT := Color(0.85, 0.2, 0.12)
signal night_began(index: int)
signal blood_moon_changed(active: bool)
@export var time_scale := DAY_SECONDS / (CONTINUOUS_DAY_MINUTES * 60.0)
@export var reset_each_wave := false
var clock_seconds := MORNING_SECONDS
var fire_energy_multiplier := 1.0
var night_index := 0            # nights begun since the round started (the first evening makes it 1)
var blood_moon_active := false
var weather_dim := 1.0          # sun and ambient multiplier under clouds (weather.gd)
var overcast := 0.0             # 0 clear .. 1 closed cloud lid (sky shader)
var main: Node
var environment: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var _sky_material: ShaderMaterial
var _lamps: Array[Dictionary] = []
var _flames: Array[StandardMaterial3D] = []
var _light_elapsed := 0.0
var _sky_elapsed := 0.0
var _sky_real_elapsed := 0.0
var _displayed_minute := -1

func setup(game: Node, fill_light: DirectionalLight3D) -> void:
	main = game
	environment = main.settings.env
	sun = main.settings.sun
	fill = fill_light
	_sky_material = environment.sky.sky_material
	if "--continuous-day-night" in OS.get_cmdline_user_args():
		time_scale = DAY_SECONDS / (CONTINUOUS_DAY_MINUTES * 60.0)
		reset_each_wave = false
	# "--blood-moon": the first evening of the round is already a blood night (screenshots, quick checks)
	if "--blood-moon" in OS.get_cmdline_user_args():
		night_index = BLOOD_MOON_EVERY - 1
	# Only fixtures opt in. Muzzle flashes, loot lights and the flashlight keep
	# their own lifetimes/controls. Cache references once, not every frame.
	for light: Node in get_tree().get_nodes_in_group("day_night_lamps"):
		_lamps.append({"light": light, "energy": light.light_energy})
	for particles: Node in get_tree().get_nodes_in_group("day_night_flames"):
		_flames.append(particles.draw_pass_1.material)
	main.waves.wave_started.connect(start_wave)
	set_time_hours(6.0)

func start_wave(_wave_number: int) -> void:
	if reset_each_wave:
		set_time_hours(6.0)

func set_time_hours(hours: float) -> void:
	clock_seconds = fposmod(hours * 3600.0, DAY_SECONDS)
	_light_elapsed = 0.0
	_sky_elapsed = 0.0
	_sky_real_elapsed = 0.0
	_displayed_minute = -1
	# "--blood-moon" with a jump straight into the night (--views hour): the blood night is this one
	if "--blood-moon" in OS.get_cmdline_user_args() and is_night() and night_index == BLOOD_MOON_EVERY - 1:
		night_index = BLOOD_MOON_EVERY
	_update_moon()
	_apply_lighting(true)
	_update_clock()

func _process(delta: float) -> void:
	if not main or get_tree().paused or not main.started or main.over:
		return
	if not NetSession.enabled and (not main.player.active or not main.player.alive):
		return
	advance(delta)

func advance(real_seconds: float) -> void:
	if main and "secret_night" in main and main.secret_night and main.secret_night.active:
		return
	var before := fposmod(clock_seconds, DAY_SECONDS)
	var elapsed := _cycle_time(before) + maxf(real_seconds, 0.0) * maxf(time_scale, 0.0)
	clock_seconds = _clock_time(fposmod(elapsed, DAY_SECONDS))
	var game_seconds := floorf(elapsed / DAY_SECONDS) * DAY_SECONDS + clock_seconds - before
	# every crossing of 20:00 begins a night (a frame may wrap midnight: then the crossing is behind us)
	if game_seconds > 0.0 and (before < NIGHT_START and (clock_seconds >= NIGHT_START or clock_seconds < before)):
		night_index += 1
		night_began.emit(night_index)
	_update_moon()
	_light_elapsed += maxf(real_seconds, 0.0)
	_sky_elapsed += game_seconds
	_sky_real_elapsed += maxf(real_seconds, 0.0)
	if _light_elapsed >= LIGHT_UPDATE_SECONDS:
		_light_elapsed = fmod(_light_elapsed, LIGHT_UPDATE_SECONDS)
		var update_sky := _sky_elapsed >= SKY_UPDATE_GAME_SECONDS and _sky_real_elapsed >= SKY_MIN_UPDATE_SECONDS
		if update_sky:
			_sky_elapsed = fmod(_sky_elapsed, SKY_UPDATE_GAME_SECONDS)
			_sky_real_elapsed = 0.0
		_apply_lighting(update_sky)
	_update_clock()

# Nights begun so far decide the moon: blood red every fifth night, from 20:00 to 05:00.
func is_night() -> bool:
	return clock_seconds >= NIGHT_START or clock_seconds < DAY_START

func blood_moon() -> bool:
	return blood_moon_active

static func blood_night(index: int) -> bool:
	return index > 0 and index % BLOOD_MOON_EVERY == 0

# 0 = new moon, 1 = full; a blood moon is always full
func moon_phase() -> float:
	if blood_moon_active: return 1.0
	return 0.5 - 0.5 * cos(float(night_index % MOON_CYCLE) / MOON_CYCLE * TAU)

func moon_phase_name() -> String:
	if blood_moon_active: return "Blood moon"
	var k := night_index % MOON_CYCLE
	return ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous", "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"][k]

func _update_moon() -> void:
	var active := is_night() and blood_night(night_index)
	if active == blood_moon_active: return
	blood_moon_active = active
	Zombie.horde_pace = BLOOD_MOON_PACE if active else 1.0
	blood_moon_changed.emit(active)
	_apply_lighting(true)

# co-op clients follow the host's night count (snapshot "moon")
func apply_moon(index: int) -> void:
	if index == night_index: return
	night_index = index
	_update_moon()
	_apply_lighting(true)

func current_time_scale() -> float:
	var daytime := clock_seconds >= DAY_START and clock_seconds < NIGHT_START
	return maxf(time_scale, 0.0) / (DAY_DURATION_FACTOR if daytime else NIGHT_DURATION_FACTOR)

# Mapping through a uniformly advancing cycle handles dawn, dusk and any number
# of midnights within one frame without changing the result with frame rate.
static func _cycle_time(seconds: float) -> float:
	if seconds < DAY_START: return seconds * NIGHT_DURATION_FACTOR
	var morning := DAY_START * NIGHT_DURATION_FACTOR
	if seconds < NIGHT_START: return morning + (seconds - DAY_START) * DAY_DURATION_FACTOR
	return morning + (NIGHT_START - DAY_START) * DAY_DURATION_FACTOR + (seconds - NIGHT_START) * NIGHT_DURATION_FACTOR

static func _clock_time(seconds: float) -> float:
	var morning := DAY_START * NIGHT_DURATION_FACTOR
	var evening := morning + (NIGHT_START - DAY_START) * DAY_DURATION_FACTOR
	if seconds < morning: return seconds / NIGHT_DURATION_FACTOR
	if seconds < evening: return DAY_START + (seconds - morning) / DAY_DURATION_FACTOR
	return NIGHT_START + (seconds - evening) / NIGHT_DURATION_FACTOR

static func daylight_at(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	return smoothstep(5.0, 8.0, h) * (1.0 - smoothstep(16.5, DUSK_END_HOUR, h))

static func phase_at(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	if h >= 5.0 and h < 9.0:
		return "Morning"
	if h >= 9.0 and h < 17.0:
		return "Day"
	if h >= 17.0 and h < DUSK_END_HOUR:
		return "Evening"
	return "Night"

static func clock_text(seconds: float) -> String:
	var minute := int(fposmod(seconds, DAY_SECONDS) / 60.0)
	return "%02d:%02d" % [minute / 60, minute % 60]

static func sun_direction_at(hour: float) -> Vector3:
	# East -> south -> west, matching the map's north-up compass. Tilt keeps
	# the sun below the zenith, as appropriate for a Swiss autumn landscape.
	var angle := (fposmod(hour, 24.0) - 6.0) * TAU / 24.0
	return Vector3(cos(angle), sin(angle) * 0.72, sin(angle) * 0.69).normalized()

func _update_clock() -> void:
	if not main:
		return
	var minute := int(clock_seconds / 60.0)
	if minute == _displayed_minute:
		return
	_displayed_minute = minute
	main.hud.set_world_time(clock_seconds, phase_at(clock_seconds / 3600.0), current_time_scale())

func _apply_lighting(update_sky: bool) -> void:
	if not environment:
		return
	var hour := clock_seconds / 3600.0
	var day := daylight_at(hour)
	var twilight := 4.0 * day * (1.0 - day)
	var direction := sun_direction_at(hour)
	var sun_strength := smoothstep(-0.055, 0.3, direction.y)
	var warm := Color(1.0, 0.51, 0.26)
	var daylight := Color(1.0, 0.92, 0.8)
	sun.light_energy = 2.5 * sun_strength * weather_dim
	sun.light_color = daylight.lerp(warm, twilight * 0.75)
	sun.look_at_from_position(direction * 100.0, Vector3.ZERO)
	# Reuse the existing shadow-free fill for gentle moonlight; no extra light
	# or shadow atlas is introduced when night falls. The moon's phase sets how much of it there is,
	# clouds take most of it away, and a blood moon turns the whole night red.
	var moonlight := (0.55 + 0.75 * moon_phase()) * lerpf(1.0, 0.35, overcast)
	fill.light_energy = lerpf(0.16 * moonlight, 0.7 * weather_dim, day)
	var moon_colour := Color(0.39, 0.52, 0.78) if not blood_moon_active else Color(0.72, 0.2, 0.14)
	fill.light_color = moon_colour.lerp(Color(0.7, 0.72, 0.78), day)
	environment.ambient_light_energy = lerpf(0.85, 1.1, day) * lerpf(1.0, 0.82, overcast)
	# A small, cool ambient floor keeps nearby paths/enemy silhouettes readable
	# under dense canopy, without lifting fire or flashlight exposure.
	environment.ambient_light_color = Color(0.42, 0.5, 0.66) if not blood_moon_active else Color(0.55, 0.32, 0.3).lerp(Color(0.42, 0.5, 0.66), day)
	environment.ambient_light_sky_contribution = lerpf(0.35, 1.0, day)
	var night_fog := Color(0.105, 0.15, 0.25) if not blood_moon_active else Color(0.22, 0.07, 0.06)
	environment.fog_light_color = night_fog.lerp(Color(0.59, 0.66, 0.70).lerp(Color(0.4, 0.42, 0.45), overcast), day).lerp(Color(0.66, 0.43, 0.31), twilight * 0.28 * (1.0 - overcast))
	environment.fog_light_energy = lerpf(0.12, 0.8 * weather_dim, day)
	environment.fog_sun_scatter = lerpf(0.02, 0.22, day) * (1.0 - overcast * 0.8)
	environment.volumetric_fog_emission_energy = lerpf(0.001, 0.02, day)
	environment.volumetric_fog_emission = (Color(0.22, 0.32, 0.5) if not blood_moon_active else Color(0.4, 0.12, 0.1)).lerp(Color(0.8, 0.65, 0.45), day)
	# Constant exposure preserves the contrast of the real local lights.
	var lamp_multiplier := lerpf(1.65, 0.85, day)
	for entry: Dictionary in _lamps:
		var light: Light3D = entry.light
		if is_instance_valid(light):
			light.light_energy = entry.energy * lamp_multiplier
	fire_energy_multiplier = lerpf(1.45, 0.9, day)
	for material: StandardMaterial3D in _flames:
		var brightness := lerpf(1.45, 1.0, day)
		material.albedo_color = Color(brightness, brightness, brightness, 1.0)
	if main.weapons and main.weapons.viewmodel:
		main.weapons.viewmodel.set_daylight(day, twilight)
	if update_sky:
		_sky_material.set_shader_parameter("daylight", day)
		_sky_material.set_shader_parameter("twilight", twilight)
		_sky_material.set_shader_parameter("sun_direction", direction)
		_sky_material.set_shader_parameter("overcast", overcast)
		_sky_material.set_shader_parameter("moon_phase", moon_phase())
		_sky_material.set_shader_parameter("moon_tint", BLOOD_MOON_TINT if blood_moon_active else Color(0.55, 0.66, 0.86))
		_sky_material.set_shader_parameter("moon_size", 0.026 if blood_moon_active else 0.018)

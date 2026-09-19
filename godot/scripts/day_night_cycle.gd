class_name DayNightCycle
extends Node

const DAY_SECONDS := 86400.0
const MORNING_SECONDS := 6.0 * 3600.0
const LIGHT_UPDATE_SECONDS := 0.1
const SKY_UPDATE_GAME_SECONDS := 30.0
const SKY_MIN_UPDATE_SECONDS := 1.0

# Requested gameplay (user, 17.9.2026): one full day lasts 15 real minutes, the game starts at 06:00 and the
# clock runs on through the waves so the night actually arrives. reset_each_wave = true restores the old
# "every wave starts in the morning" behaviour.
const CONTINUOUS_DAY_MINUTES := 15.0
@export var time_scale := DAY_SECONDS / (CONTINUOUS_DAY_MINUTES * 60.0)
@export var reset_each_wave := false
var clock_seconds := MORNING_SECONDS
var fire_energy_multiplier := 1.0
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
	_apply_lighting(true)
	_update_clock()

func _process(delta: float) -> void:
	if not main or get_tree().paused or not main.started or main.over:
		return
	if not NetSession.enabled and (not main.player.active or not main.player.alive):
		return
	advance(delta)

func advance(real_seconds: float) -> void:
	var game_seconds := maxf(real_seconds, 0.0) * maxf(time_scale, 0.0)
	clock_seconds = fposmod(clock_seconds + game_seconds, DAY_SECONDS)
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

static func daylight_at(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	return smoothstep(5.0, 8.0, h) * (1.0 - smoothstep(16.5, 20.0, h))

static func phase_at(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	if h >= 5.0 and h < 9.0:
		return "Morgen"
	if h >= 9.0 and h < 17.0:
		return "Tag"
	if h >= 17.0 and h < 20.0:
		return "Abend"
	return "Nacht"

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
	main.hud.set_world_time(clock_seconds, phase_at(clock_seconds / 3600.0), time_scale)

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
	sun.light_energy = 2.5 * sun_strength
	sun.light_color = daylight.lerp(warm, twilight * 0.75)
	sun.look_at_from_position(direction * 100.0, Vector3.ZERO)
	# Reuse the existing shadow-free fill for gentle moonlight; no extra light
	# or shadow atlas is introduced when night falls.
	fill.light_energy = lerpf(0.16, 0.7, day)
	fill.light_color = Color(0.39, 0.52, 0.78).lerp(Color(0.7, 0.72, 0.78), day)
	environment.ambient_light_energy = lerpf(0.85, 1.1, day)
	# A small, cool ambient floor keeps nearby paths/enemy silhouettes readable
	# under dense canopy, without lifting fire or flashlight exposure.
	environment.ambient_light_color = Color(0.42, 0.5, 0.66)
	environment.ambient_light_sky_contribution = lerpf(0.35, 1.0, day)
	environment.fog_light_color = Color(0.105, 0.15, 0.25).lerp(Color(0.59, 0.66, 0.70), day).lerp(Color(0.66, 0.43, 0.31), twilight * 0.28)
	environment.fog_light_energy = lerpf(0.12, 0.8, day)
	environment.fog_sun_scatter = lerpf(0.02, 0.22, day)
	environment.volumetric_fog_emission_energy = lerpf(0.001, 0.02, day)
	environment.volumetric_fog_emission = Color(0.22, 0.32, 0.5).lerp(Color(0.8, 0.65, 0.45), day)
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

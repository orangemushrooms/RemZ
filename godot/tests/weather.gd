# Weather and the moon (26 Sep 2026): the day-0 schedule, rain soaking the ground, fog banks, a storm's
# lightning that lights the horde, thunder, the snapshot round trip, the night count, the blood moon's
# pace and double points. Headless:
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=weather --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func tick(seconds: float, step := 0.25) -> void:
	var t := 0.0
	while t < seconds:
		game.weather._process(step)
		t += step

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.day_night.set_process(false)
	var weather: Weather = game.weather
	var cycle: DayNightCycle = game.day_night
	check(weather != null and game.pings != null, "Weather and the radio exist")
	# ---- the schedule of day 0
	var plan: Array = weather.schedule()
	check(plan.size() == 4, "Day 0 carries four scripted weather windows (%d)" % plan.size())
	check(weather.scheduled_state(7.0 * 3600.0) == "fog", "07:00 of day 0 is foggy")
	check(weather.scheduled_state(12.0 * 3600.0) == "clear", "Noon of day 0 is clear")
	check(weather.scheduled_state(17.0 * 3600.0) == "rain", "17:00 of day 0 rains")
	check(weather.scheduled_state(18.5 * 3600.0) == "storm", "18:30 of day 0 is a thunderstorm")
	check(weather.scheduled_state(20.0 * 3600.0) == "rain", "20:00 of day 0 rains again")
	check(weather.state == "clear" and weather.intensity == 0.0 and weather.wetness == 0.0, "The round starts dry and clear")
	weather._plan_day(3)
	check(weather.day_count == 3 and weather.schedule().size() <= 5, "Later days roll their own schedule")
	weather._plan_day(0)
	# ---- rain: soaks in, dims the sun, drums on the loop, darkens the leaves
	weather.force("rain")
	check(weather.state == "rain" and weather.forced == "rain", "Rain can be pinned")
	tick(10.0)
	check(weather.intensity > 0.95, "Rain reaches full strength after the fade (%.2f)" % weather.intensity)
	check(weather._rain.emitting and weather._rain.amount_ratio > 0.5, "Rain streaks fall around the camera")
	check(weather._rain_audio.playing and weather._rain_audio.volume_db > -30.0, "The rain loop plays (%.1f dB)" % weather._rain_audio.volume_db)
	check(weather.wetness > 0.25 and weather.wetness < 1.0, "The ground is soaking (%.2f)" % weather.wetness)
	var wet_global = RenderingServer.global_shader_parameter_get("remz_wetness")
	check(wet_global == null or absf(float(wet_global) - weather.wetness) < 0.001, "The wetness global follows (%s)" % str(wet_global))
	check(cycle.weather_dim < 0.6 and cycle.overcast > 0.8, "Rain dims the sun and closes the sky (dim %.2f, overcast %.2f)" % [cycle.weather_dim, cycle.overcast])
	check(game.settings.env.fog_density > 0.004, "Rain thickens the distance fog (%.4f)" % game.settings.env.fog_density)
	check(weather.is_raining() and weather.label() == "Rain", "Rain reports itself")
	tick(30.0)
	check(weather.wetness >= 0.999, "Half a minute of rain soaks the ground fully")
	game._process(0.6)
	game._process(0.6)
	check(Lang.text(game.hud.weather_label.text).contains("Rain") and game.hud.weather_label.visible, "The clock panel shows the weather (%s)" % Lang.text(game.hud.weather_label.text))
	# ---- fog banks
	weather.force("fog")
	tick(10.0)
	check(weather.is_foggy() and weather.label() == "Fog", "Fog reports itself")
	check(weather._banks.size() == Weather.BANK_COUNT and weather._banks[0].visible and (weather._banks[0].material as FogMaterial).density > 0.05, "Fog banks drift over the land")
	check(not weather._rain.emitting, "No rain in the fog")
	check(weather.hides_stalkers(), "Fog hides the stalkers")
	# ---- storm: bolts, the flash, the glow of the horde, thunder
	weather.force("storm")
	tick(10.0)
	check(weather.is_storm() and weather.label() == "Thunderstorm", "The storm reports itself")
	var spawned: bool = game.spawn_zombie("shambler", Vector2(20, 80), 1.0)
	var zombie: Zombie = null
	for z in game.zombies_root.get_children():
		if z is Zombie: zombie = z
	check(spawned and zombie != null, "A zombie stands in the storm")
	var serial_before: int = weather.lightning_serial
	weather._next_bolt = 0.0
	weather._process(0.05)
	check(weather.lightning_serial == serial_before + 1, "The storm throws a bolt")
	check(weather.flash > 0.2, "The bolt lights the sky (%.2f)" % weather.flash)
	check(game.settings.sun.light_energy > 2.5, "The bolt lights the whole forest (sun %.1f)" % game.settings.sun.light_energy)
	check(zombie._reveal_t > 0.0 and zombie._materials.size() > 0 and zombie._materials[0].emission.b > 1.5, "The horde glows cold white in the flash")
	check(weather._thunder.size() == 1 and float(weather._thunder[0][0]) > 0.2, "Thunder follows the bolt after the distance delay")
	tick(3.0, 0.1)
	check(weather.thunder_count == weather.lightning_serial and weather._thunder.is_empty(), "Every bolt rolled its thunder (count %d, bolts %d)" % [weather.thunder_count, weather.lightning_serial])
	check(weather.flash == 0.0 and weather._flash_t <= 0.0, "The flash is over")
	for frame in 45: await physics_frame
	check(zombie._reveal_t <= 0.0 and zombie._materials[0].emission == Color.BLACK, "The glow fades with the flash (%.2f)" % zombie._reveal_t)
	# ---- snapshot round trip: a client follows the state and replays the bolt count
	var snapshot: Array = weather.snapshot()
	check(snapshot.size() == 7 and str(snapshot[0]) == "storm" and int(snapshot[4]) == weather.lightning_serial, "The weather snapshot carries state, wind, bolts and wetness")
	var shown_before: int = weather._shown_lightning
	weather.apply_snapshot(["fog", 0.5, 1.0, 0.0, weather.lightning_serial + 1, 0.3, 2], false)
	check(weather.state == "fog" and weather.lightning_serial == shown_before + 1, "A snapshot switches the state and announces a bolt")
	weather._process(0.05)
	check(weather._shown_lightning == weather.lightning_serial and weather.flash > 0.0, "The announced bolt flashes on this machine too")
	tick(4.0, 0.1)
	weather.release()
	weather.force("clear")
	tick(12.0)
	check(weather.intensity == 0.0 and not weather._rain.emitting and not weather._banks[0].visible, "Clear weather switches everything off")
	weather.release()
	check(weather.forced == "", "The weather is released to its schedule")
	# ---- the moon: night count, phases, the blood moon
	check(not cycle.is_night() and cycle.night_index == 0, "The round begins by day with no night begun")
	cycle.set_time_hours(19.98)
	var began: Array = []
	cycle.night_began.connect(func(index: int): began.append(index))
	cycle.advance(3.0)
	check(cycle.night_index == 1 and began == [1] and cycle.is_night(), "Crossing 20:00 begins the first night")
	check(not cycle.blood_moon() and Zombie.horde_pace == 1.0, "The first night is an ordinary night")
	check(DayNightCycle.blood_night(5) and DayNightCycle.blood_night(10) and not DayNightCycle.blood_night(3) and not DayNightCycle.blood_night(0), "Every fifth night is a blood night")
	check(cycle.moon_phase_name() == "Waxing crescent" and cycle.moon_phase() > 0.1 and cycle.moon_phase() < 0.2, "Night 1 shows a waxing crescent (%.2f)" % cycle.moon_phase())
	cycle.set_time_hours(12.0)
	cycle.night_index = 4
	cycle.set_time_hours(19.99)
	var moon_events: Array = []
	cycle.blood_moon_changed.connect(func(active: bool): moon_events.append(active))
	cycle.advance(2.0)
	check(cycle.night_index == 5 and cycle.blood_moon() and moon_events == [true], "The fifth night rises as a blood moon")
	check(Zombie.horde_pace == DayNightCycle.BLOOD_MOON_PACE, "The horde runs faster under the blood moon (%.2f)" % Zombie.horde_pace)
	check(cycle.moon_phase() == 1.0 and cycle.moon_phase_name() == "Blood moon", "A blood moon is full")
	check(game.fill_light.light_color.r > game.fill_light.light_color.b, "The moonlight turns red")
	var sky: ShaderMaterial = game.settings.env.sky.sky_material
	var tint: Color = sky.get_shader_parameter("moon_tint")
	check(tint.r > 0.8 and tint.g < 0.3, "The sky's moon is blood red")
	check(Lang.text(game.hud.msg_label.text).begins_with("BLOOD MOON"), "The blood moon is announced")
	check(game.pings.active.size() > 0 and game.pings.active.back().kind == "blood_moon", "The radio calls the blood moon")
	# double points: the same kill pays twice as much under the red moon
	game.stats._streak = 0
	game.stats._streak_t = 0.0
	zombie.killer_peer = 1
	zombie.last_headshot = false
	zombie.killer_weapon = "pistol"
	var earned_before: int = game.stats.points_earned
	zombie.die(Vector3.FORWARD)
	var red_points: int = game.stats.points_earned - earned_before
	cycle.set_time_hours(12.0)
	check(not cycle.blood_moon() and moon_events == [true, false] and Zombie.horde_pace == 1.0, "The blood moon sets at daybreak")
	game.stats._streak = 0
	game.stats._streak_t = 0.0
	game.spawn_zombie("shambler", Vector2(22, 82), 1.0)
	var second: Zombie = null
	for z in game.zombies_root.get_children():
		if z is Zombie and z.alive: second = z
	second.killer_peer = 1
	second.last_headshot = false
	second.killer_weapon = "pistol"
	earned_before = game.stats.points_earned
	second.die(Vector3.FORWARD)
	var day_points: int = game.stats.points_earned - earned_before
	check(red_points == day_points * 2 and day_points > 0, "A kill under the blood moon pays double (%d vs %d)" % [red_points, day_points])
	# the co-op mirror of the night count
	cycle.apply_moon(10)
	cycle.set_time_hours(22.0)
	cycle.advance(0.0)
	check(cycle.night_index == 10 and cycle.blood_moon(), "A client follows the host's night count into a blood moon")
	cycle.apply_moon(11)
	check(not cycle.blood_moon(), "... and out of it")
	print("WEATHER_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

class_name SecretNight
extends Node3D

# The northern Sorchen trail remains inside the playable bounds here.
const SITE := Vector2(-108, -201)
const TOTEMS := [Vector2(-119, -193), Vector2(-111, -184), Vector2(-99, -192)]
const BAR := Vector2(-120, -202)
# The dance circle sits in front of the stage (the stage proxy reaches to z -199.5); with the circle at -195
# the dancers stood inside the DJ desk. Kept 3 m clear since 25 Sep 2026.
const DANCE := Vector2(-108, -192)
const SONG := "res://assets/audio/music/Goa_Party_Sidequest.mp3"
# Stages (25 Sep 2026, the long version): 0 follow the sound, 1 tune the totems, HARVEST pick three glowing
# mushrooms around the floor, TRIP eat the DJ's mushroom at the bar (everyone hallucinates), COLOUR_RUN reach
# the totem that flashes, four rounds in RUN_SECONDS each (too slow = start over), CLEAR drink the Clear Head,
# DANCE_STEP the final dance, GUESTS the bass wakes the dead - clear the floor, then the old ending.
const HARVEST := 2
const TRIP := 3
const COLOUR_RUN := 4
const CLEAR := 5
const DANCE_STEP := 6
const GUESTS := 7
const CLOSING := 8
const ECHO := 9
const RETURN := 10
const WAKING := 11
const ECHO_POINT := SITE + Vector2(0, 8.0)
const CLOSING_SECONDS := 18.0
const WAKING_SECONDS := 8.0
const RETURN_RADIUS := 14.0
const REWARD := 250
const PREPARATION_SECONDS := 30.0
# The quest always ends at the next morning: the echo burns down as the clock turns to MORNING_SECONDS, the
# morning song plays, and for MORNING_GLOW_SECONDS the fog stays thick so the low sun shafts through the trees.
const MORNING_SECONDS := 6.7 * 3600.0
const MORNING_GLOW_SECONDS := 90.0
const MORNING_FOG := 0.03
const WAKE_SECONDS := 5.0
const GLOW_SPOTS := [Vector2(-96, -198), Vector2(-120, -190), Vector2(-110, -183)]
const TRIP_SECONDS := 36.0
const RUN_SEQUENCE := [1, 2, 0, 2]
const RUN_SECONDS := 10.0
const RUN_RADIUS := 3.5
const RAVERS := ["shambler", "runner", "shambler", "nurse", "shambler", "runner", "shambler", "soldier"]
const STAGE_NAMES := ["THE DISTANT SOUND", "SOUND TOTEMS", "GLOW HARVEST", "THE DJ'S MUSHROOM", "COLOUR RUN", "CLEAR HEAD", "ONE LAST DANCE", "UNINVITED GUESTS", "LAST TRACK", "ECHO OF THE NIGHT", "THE WAY HOME", "BACK TO REALITY"]
const COLOURS := [Color(0.1, 0.9, 1.0), Color(1.0, 0.18, 0.6), Color(0.7, 0.35, 1.0)]
const COLOUR_NAMES := ["TURQUOISE", "PINK", "VIOLET"]
const INTRO := "Your team has eaten too many mushrooms.\nYou hear a sound in the distance. Follow it …"
const STEPS := ["Follow the bass and the glowing mushrooms to Oberer Schorchen.",
	"Awaken the sound totems: TURQUOISE → PINK → VIOLET. [E]",
	"The bartender wants three glowing mushrooms from around the floor. Pick them. [E]",
	"The DJ hands you a mushroom of his own. Eat it at the bar. [E]",
	"Run to the totem that flashes. Four rounds, ten seconds each.",
	"Heads spinning. Get the Clear Head drink at the bar. [E]",
	"Stay in the glowing dance circle for the finale.",
	"The bass woke the dead. Clear the dance floor!",
	"The last beat fades away. Take this moment with you.",
	"Final quest: collect the Echo of the Night in front of the DJ booth. [E]",
	"Bring the Echo of the Night back to the campfire. Gather your team and place it in the fire. [E]",
	"The echo burns away. Stay together by the fire until your heads are clear."]
var main: Node
var active := false
var completed := false
var step := 0
var tuned := 0
var dance_time := 0.0
var closing_time := 0.0
var waking_time := 0.0
var echo_collected := false
var echo_offered := false
var harvest_mask := 0          # bits of GLOW_SPOTS already picked
var run_round := 0             # colour run rounds done
var run_target := -1           # totem to reach right now, -1 = about to be drawn
var run_time := 0.0
var ravers_spawned := false
var glow_props: Array[Node3D] = []
var _morning_left := 0.0
var _wake_left := 0.0
var echo_prop: Node3D
var echo_light: OmniLight3D
var echo_caption: Label3D
var echo_meshes: Array[GeometryInstance3D] = []
var _announced_step := -1
var _clock_refresh := 0.0
var elapsed := 0.0
var saved_clock := 0.0
var saved_fog := 0.0
var scenery: Node3D
var lights: Array[SpotLight3D] = []
var dancers: Array[Node3D] = []
var totem_lights: Array[OmniLight3D] = []
var party_fills: Array[OmniLight3D] = []
var beams: Array[MeshInstance3D] = []
var guest_meshes: Array[GeometryInstance3D] = []
var party_glows: Array[Dictionary] = []
var party_labels: Array[Label3D] = []
var stage_sign: Label3D
var song: AudioStreamPlayer3D
var song_filter: AudioEffectLowPassFilter
var song_bus := ""
var rain_sound: AudioStreamPlayer
var rain: GPUParticles3D
var panel: PanelContainer
var title: Label
var copy: Label
var haze: ColorRect
var bar: PartyBar
var show_t := 2.0                # seconds to the next salvo of the party's own fireworks
var show_rockets := 0            # statistics / tests
const SHOW_SPOTS := [Vector2(-121, -186), Vector2(-95, -186), Vector2(-100, -176), Vector2(-116, -176)]
const SHOW_KINDS := ["fw_ruby", "fw_aurora", "fw_gold"]
var haze_material: ShaderMaterial

func setup(game: Node) -> void:
	main = game
	add_to_group("render_dynamic")
	_build_party()
	_build_echo()
	_build_weather()
	_build_hud()
	bar = PartyBar.new()
	add_child(bar)
	bar.setup(self)
	scenery.hide()
	_set_collisions(false)
	panel.hide()
	haze.hide()

func begin() -> void:
	if active or completed: return
	active = true
	step = 0
	tuned = 0
	dance_time = 0.0
	closing_time = 0.0
	waking_time = 0.0
	echo_collected = false
	echo_offered = false
	harvest_mask = 0
	run_round = 0
	run_target = -1
	run_time = 0.0
	ravers_spawned = false
	elapsed = 0.0
	main.waves.phase = "secret_night"
	main.waves.queue.clear()
	main.waves.boss_fight = false
	_enter_presentation()

func _enter_presentation(original_clock := -1.0) -> void:
	saved_clock = main.day_night.clock_seconds if original_clock < 0 else original_clock
	saved_fog = main.settings.env.volumetric_fog_density
	main.day_night.set_time_hours(0.5)
	main.settings.env.volumetric_fog_density = 0.012
	main.music.horde = 0.0
	main.music.play("secret_night") # Crossfade ordinary music to silence.
	scenery.show()
	_set_collisions(true)
	panel.show()
	haze.show()
	rain.emitting = step <= CLOSING and party_energy() > 0.001
	_update_song_distance(0.0, true)
	if step <= CLOSING:
		song.play(fposmod(elapsed, maxf(song.stream.get_length(), 0.001)))
	if rain.emitting: rain_sound.play()
	_announced_step = -1
	_present_stage()
	_update_ending(0.0)

func _leave_presentation() -> void:
	scenery.hide()
	_set_collisions(false)
	panel.hide()
	haze.hide()
	rain.emitting = false
	song.stop()
	rain_sound.stop()
	main.settings.env.volumetric_fog_density = saved_fog
	main.day_night.set_time_hours(saved_clock / 3600.0)

func _set_collisions(enabled: bool) -> void:
	for shape in scenery.find_children("*", "CollisionShape3D", true, false):
		shape.set_deferred("disabled", not enabled)

func target() -> Vector2:
	match step:
		0: return DANCE
		1: return TOTEMS[mini(tuned, 2)]
		HARVEST: return GLOW_SPOTS[_nearest_glow(Vector2(main.player.global_position.x, main.player.global_position.z))] if harvest_mask != 7 else BAR + Vector2(0, 2)
		TRIP: return BAR + Vector2(0, 2)
		COLOUR_RUN: return TOTEMS[run_target] if run_target >= 0 else DANCE
		CLEAR: return BAR + Vector2(0, 2)
		DANCE_STEP: return DANCE
		GUESTS: return DANCE
		CLOSING: return DANCE
		ECHO: return ECHO_POINT
	return Map.FIRE

func _nearest_glow(from: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in GLOW_SPOTS.size():
		if harvest_mask & (1 << i): continue
		var d: float = from.distance_to(GLOW_SPOTS[i])
		if d < best_d:
			best_d = d
			best = i
	return maxi(best, 0)

func harvested() -> int:
	var n := 0
	for i in GLOW_SPOTS.size():
		if harvest_mask & (1 << i): n += 1
	return n

func prompt(p: Player) -> String:
	if not active or not p.alive or p.controlling_drone or p.mounted_tower: return ""
	if Vector2(p.global_position.x, p.global_position.z).distance_to(target()) > 3.5: return ""
	match step:
		1: return Lang.t("[E] Tune sound totem · %s", [["Turquoise", "Pink", "Violet"][mini(tuned, 2)]])
		HARVEST: return Lang.t("[E] Pick the glowing mushroom · %d / 3", [harvested()]) if harvest_mask != 7 else ""
		TRIP: return "[E] Eat the DJ's mushroom · \"Trust me, forest spirit.\""
		CLEAR: return "[E] Drink Clear Head · water, mint and forest magic"
		ECHO: return "[E] Collect Echo of the Night · shared quest item"
		RETURN:
			return "[E] Place Echo of the Night in the fire" if echo_collected and _team_near(Map.FIRE, RETURN_RADIUS, true) else "Gather your team and the echo by the fire …"
	return ""

func request_interact() -> void:
	if NetSession.enabled: NetSession.command("secret_night")
	else: interact(main.player)

# Every action is validated against the authoritative actor and current step.
func interact(p: Player) -> bool:
	if NetSession.is_client() or prompt(p).is_empty(): return false
	match step:
		1:
			tuned += 1
			Sfx.play(self, "menu", -8.0)
			if tuned == 3: step = HARVEST
		HARVEST:
			var index := _nearest_glow(Vector2(p.global_position.x, p.global_position.z))
			if harvest_mask & (1 << index): return false
			harvest_mask |= 1 << index
			Sfx.play(self, "mushroom_pickup", -6.0)
			if harvest_mask == 7: step = TRIP
		TRIP:
			step = COLOUR_RUN
			run_round = 0
			run_target = -1
			run_time = 0.0
			_trip_everyone(TRIP_SECONDS)
			Sfx.play(self, "consume", -8.0)
		CLEAR:
			step = DANCE_STEP
			_sober_everyone()
			Sfx.play(self, "consume", -8.0)
		ECHO:
			if echo_collected: return false
			echo_collected = true
			step = RETURN
			Sfx.play(self, "menu", -8.0)
		RETURN:
			if not echo_collected or echo_offered or not _team_near(Map.FIRE, RETURN_RADIUS, true): return false
			echo_offered = true
			step = WAKING
			waking_time = 0.0
			saved_clock = MORNING_SECONDS    # the awakening turns the clock to the next morning
	_present_stage()
	_update_ending(0.0)
	return true

# The DJ's mushroom: every teammate's view swims (hud.hallucinate, clients through the "hallucinate" feedback);
# the Clear Head drink ends it within a second and a half.
func _trip_everyone(seconds: float) -> void:
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() else [main.player]
	for p: Player in actors:
		if p == main.player: main.hud.hallucinate(seconds)
		elif NetSession.is_host(): NetSession.feedback(p.peer_id, "hallucinate", [seconds])

func _sober_everyone() -> void:
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() else [main.player]
	for p: Player in actors:
		if p == main.player: main.hud.sober()
		elif NetSession.is_host(): NetSession.feedback(p.peer_id, "sober", [])

# The bass wakes the dead: eight ravers rise around the floor and have to be cleared before the last track.
func _spawn_ravers() -> void:
	if ravers_spawned or NetSession.is_client(): return
	ravers_spawned = true
	for i in RAVERS.size():
		var angle := TAU * i / RAVERS.size() + 0.3
		var point := DANCE + Vector2(cos(angle), sin(angle)) * 15.0
		if not main.spawn_zombie(RAVERS[i], point, 1.0, "", 0.0):
			main.spawn_zombie(RAVERS[i], DANCE + Vector2(cos(angle), sin(angle)) * 9.0, 1.0, "", 0.0)

func _complete() -> void:
	if not active or completed or step != WAKING or not echo_offered or NetSession.is_client(): return
	active = false
	completed = true
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() else [main.player]
	for p: Player in actors: p.add_score(REWARD)
	_leave_presentation()
	main.waves.phase = "idle"
	main.waves.timer = PREPARATION_SECONDS
	_morning_left = MORNING_GLOW_SECONDS
	_wake_left = WAKE_SECONDS
	_update_morning(0.0)
	_completion_message()

func _completion_message() -> void:
	main.music.play(main.music.intermission_track(saved_clock / 3600.0))
	main.hud.message(Lang.t("ECHO OF THE NIGHT · QUEST COMPLETE\nThe last echo burns away. You are home again.\n+%d Rem Dollars per player · Wave 5 in %d seconds", [REWARD, int(PREPARATION_SECONDS)]), 10.0)

func _team_near(point: Vector2, radius: float, everyone := false) -> bool:
	var actors: Array = NetSession.world.actors.values() if NetSession.enabled and NetSession.world else [main.player]
	var living := 0
	var nearby := 0
	for p: Player in actors:
		if not p.alive: continue
		living += 1
		if Vector2(p.global_position.x, p.global_position.z).distance_to(point) <= radius: nearby += 1
	return living > 0 and (nearby == living if everyone else nearby > 0)

func _process(delta: float) -> void:
	_update_morning(delta)
	if not active: return
	if main.over:
		active = false
		_leave_presentation()
		return
	if not main.started or get_tree().paused: return
	elapsed += delta
	if not NetSession.is_client(): _update_show(delta)
	if not NetSession.is_client():
		if step == 0 and _team_near(DANCE, 12.0): step = 1
		if step == COLOUR_RUN:
			if run_target < 0:
				run_target = RUN_SEQUENCE[run_round]
				run_time = 0.0
				main.hud.message(Lang.t("DJ: %s! Run to the totem that flashes!", [COLOUR_NAMES[run_target]]), 3.0)
			else:
				run_time += delta
				if _team_near(TOTEMS[run_target], RUN_RADIUS):
					run_round += 1
					run_target = -1
					Sfx.play(self, "menu", -8.0)
					if run_round >= RUN_SEQUENCE.size(): step = CLEAR
				elif run_time >= RUN_SECONDS:
					run_round = 0
					run_target = -1
					main.hud.message("DJ: Too slow, forest spirits! Once more from the top.", 3.0)
		elif step == DANCE_STEP:
			if _team_near(DANCE, 7.0, true): dance_time += delta
			if dance_time >= 16.0:
				step = GUESTS
				_spawn_ravers()
		elif step == GUESTS:
			if ravers_spawned and main.alive_zombies() == 0:
				step = CLOSING
				closing_time = 0.0
		elif step == CLOSING:
			closing_time = minf(CLOSING_SECONDS, closing_time + delta)
			if closing_time >= CLOSING_SECONDS: step = ECHO
		elif step == WAKING:
			if _team_near(Map.FIRE, RETURN_RADIUS, true): waking_time += delta
			if waking_time >= WAKING_SECONDS:
				_complete()
				return
	_present_stage()
	_update_song_distance(delta)
	var distance := Vector2(main.player.global_position.x, main.player.global_position.z).distance_to(target())
	title.text = "SECRET NIGHT · OBERER SCHORCHEN"
	var detail := Lang.t("%d m · Wave 5 is waiting for you", [int(distance)])
	if step == DANCE_STEP: detail = Lang.t("All living teammates inside the circle · %d / 16 s", [mini(16, int(dance_time))])
	elif step == HARVEST: detail = Lang.t("Glowing mushrooms · %d / 3", [harvested()])
	elif step == COLOUR_RUN: detail = Lang.t("Round %d / %d · %s · %d s left", [mini(run_round + 1, RUN_SEQUENCE.size()), RUN_SEQUENCE.size(), COLOUR_NAMES[run_target] if run_target >= 0 else "…", ceili(RUN_SECONDS - run_time)])
	elif step == GUESTS: detail = Lang.t("Ravers left on the floor · %d", [main.alive_zombies()])
	elif step == CLOSING: detail = Lang.t("Last track · %d s remaining", [ceili(CLOSING_SECONDS - closing_time)])
	elif step == RETURN: detail = Lang.t("Echo of the Night: carried by your team · %d m to the campfire", [int(distance)])
	elif step == WAKING: detail = Lang.t("Together by the fire · %d / %d s", [mini(int(WAKING_SECONDS), int(waking_time)), int(WAKING_SECONDS)])
	copy.text = Lang.t(STEPS[step]) + "\n" + detail
	main.hud.set_wave(5, Lang.t("SECRET NIGHT · %s", [STAGE_NAMES[step]]))
	rain.global_position = main.player.global_position + Vector3(0, 10, 0)
	var beat := 0.5 + 0.5 * sin(elapsed * TAU * 140.0 / 60.0)
	var energy := party_energy()
	for i in lights.size():
		lights[i].rotation = Vector3(-0.85 + sin(elapsed * 0.4 + i) * 0.3, sin(elapsed * 0.31 + i * 2) * 1.1, 0)
	for i in dancers.size():
		dancers[i].rotation.z = sin(elapsed * TAU * 140.0 / 120.0 + i) * 0.09 * energy
		dancers[i].position.y = float(dancers[i].get_meta("floor")) + beat * 0.09 * energy
	_update_ending(delta)

# After the completion: a warm wake-up flash over the screen and a long, thick morning haze so the sun
# shafts through the forest, both fading out on their own.
# The party's own fireworks: a salvo every few seconds over the dance floor from the moment the team
# arrives until the last track fades (host / solo; clients see them through the fireworks snapshot).
func _update_show(delta: float) -> void:
	if step < 1 or step > CLOSING or not main.fireworks: return
	show_t -= delta
	if show_t > 0.0: return
	show_t = randf_range(2.2, 4.5) if step < DANCE_STEP else randf_range(0.9, 1.8)
	var spot: Vector2 = SHOW_SPOTS[randi() % SHOW_SPOTS.size()]
	if main.fireworks.launch_at(SHOW_KINDS[randi() % SHOW_KINDS.size()], Map.ground_pos(spot.x, spot.y) + Vector3.UP * 0.05):
		show_rockets += 1

func _update_morning(delta: float) -> void:
	if _morning_left <= 0.0: return
	_morning_left = maxf(0.0, _morning_left - delta)
	var k := smoothstep(0.0, 1.0, _morning_left / MORNING_GLOW_SECONDS)
	main.settings.env.volumetric_fog_density = lerpf(saved_fog, MORNING_FOG, k)
	if _wake_left > 0.0:
		_wake_left = maxf(0.0, _wake_left - delta)
		haze.show()
		haze_material.set_shader_parameter("strength", 0.0)
		haze_material.set_shader_parameter("awakening", smoothstep(0.0, 1.0, _wake_left / WAKE_SECONDS) * 0.95)
		if _wake_left <= 0.0: haze.hide()

func party_energy() -> float:
	if step < CLOSING: return 1.0
	if step > CLOSING: return 0.0
	return 1.0 - smoothstep(4.0, CLOSING_SECONDS, closing_time)

func _present_stage() -> void:
	if _announced_step == step: return
	_announced_step = step
	match step:
		0: main.hud.message(INTRO, 10.0)
		HARVEST: main.hud.message("BARTENDER: Three glowing mushrooms from around the floor, and the next round is on the house.", 7.0)
		TRIP: main.hud.message("DJ: You brought them? Then take this one. Trust me, forest spirit.\nEat it at the bar.", 7.0)
		COLOUR_RUN: main.hud.message("DJ: Now the colours show you the way. Run to the totem that flashes - ten seconds each!", 7.0)
		CLEAR: main.hud.message("DJ: Enough spinning. The bartender has a Clear Head for you.", 6.0)
		DANCE_STEP: main.hud.message("DJ: One last dance, forest spirits!\nEveryone into the circle. Then it is time to go home.", 7.0)
		GUESTS: main.hud.message("DJ: The bass woke the dead! Clear the floor before the last track!", 7.0)
		CLOSING: main.hud.message("DJ: That was our last journey tonight.\nGet home safely. See you on the other side of the morning.", 8.0)
		ECHO: main.hud.message("FINAL QUEST · ECHO OF THE NIGHT\nA glowing sound totem remains by the DJ booth.\nOne last message: bring my echo to the fire. Only there can this dream end.", 10.0)
		RETURN: main.hud.message("ECHO OF THE NIGHT COLLECTED\nYou feel the last beat inside the totem. Bring it to the campfire together.\nThe glowing mushrooms show you the way home.", 8.0)
		WAKING: main.hud.message("You place the echo in the fire. The last beat becomes a spark.\nOne deep breath. The world becomes clear again.", 7.0)

func _update_ending(delta: float) -> void:
	var energy := party_energy()
	var beat := 0.5 + 0.5 * sin(elapsed * TAU * 140.0 / 60.0)
	for light in lights: light.light_energy = (3.0 + beat * 2.0) * energy
	for i in totem_lights.size():
		var flash := 4.0 + 6.0 * beat if step == COLOUR_RUN and i == run_target else 0.0
		totem_lights[i].light_energy = ((3.5 if i < tuned else 0.8) + flash) * energy
	for i in glow_props.size():
		glow_props[i].visible = step <= HARVEST and not (harvest_mask & (1 << i)) and energy > 0.001
	for light in party_fills: light.light_energy = 4.5 * energy
	for beam in beams:
		beam.transparency = 1.0 - energy
		beam.visible = energy > 0.001
	for mesh in guest_meshes:
		mesh.transparency = 1.0 - energy
		mesh.visible = energy > 0.001
	for glow in party_glows: glow.material.emission_energy_multiplier = glow.energy * energy
	for label in party_labels: label.modulate.a = energy
	stage_sign.text = "SCHORCHEN\nAFTER HOURS" if step < CLOSING else ("ONE LAST BEAT" if step == CLOSING else "UNTIL THE NEXT DREAM")
	stage_sign.modulate = COLOURS[0].lerp(Color(0.7, 0.55, 0.3), 1.0 - energy)
	var weather := 1.0 if step < CLOSING else energy
	rain.amount_ratio = weather
	rain.emitting = weather > 0.001
	rain_sound.volume_db = -20.0 + linear_to_db(0.5) + linear_to_db(maxf(0.0001, weather))
	if weather <= 0.001: rain_sound.stop()
	main.settings.env.volumetric_fog_density = lerpf(saved_fog, 0.012, weather)
	haze_material.set_shader_parameter("strength", (0.12 if step >= 3 else 0.55) * weather)
	if energy <= 0.001: song.stop()
	var waking := clampf(waking_time / WAKING_SECONDS, 0.0, 1.0) if step == WAKING else 0.0
	haze_material.set_shader_parameter("awakening", sin(waking * PI) * 0.65)
	echo_prop.visible = (step == ECHO and not echo_collected) or (step == WAKING and echo_offered)
	if echo_prop.visible:
		var point := Map.FIRE if echo_offered else ECHO_POINT
		echo_prop.position = Map.ground_pos(point.x, point.y) + Vector3.UP * (lerpf(0.9, 0.25, waking) if echo_offered else 0.7 + sin(elapsed * 2.0) * 0.08)
		echo_prop.rotation.y = elapsed * 0.45
		echo_prop.scale = Vector3.ONE * lerpf(1.0, 0.15, waking)
		echo_light.light_color = Color(1, 0.5, 0.12) if echo_offered else COLOURS[0]
		echo_light.light_energy = (2.0 + beat) * (1.0 - waking)
		echo_caption.text = "The echo burns away …" if echo_offered else "ECHO OF THE NIGHT\n[E] Collect"
		echo_caption.rotation.y = -echo_prop.rotation.y
		for mesh in echo_meshes: mesh.transparency = waking
	if step == WAKING:
		_clock_refresh -= delta
		if _clock_refresh <= 0.0:
			_clock_refresh = 0.2
			var difference := wrapf(saved_clock - 1800.0, -43200.0, 43200.0)
			main.day_night.set_time_hours((1800.0 + difference * smoothstep(0.0, 1.0, waking)) / 3600.0)

func _update_song_distance(delta: float, snap := false) -> void:
	# Each listener gets their own mix in co-op. The 3D source retains its direction;
	# this curve owns the gain so Godot does not attenuate the same distance twice.
	var distance: float = main.player.camera.global_position.distance_to(song.global_position)
	var far := smoothstep(12.0, 280.0, distance)
	var gain := lerpf(-7.0, -35.0, far)
	gain += linear_to_db(maxf(0.0001, party_energy()))
	var cutoff := exp(lerpf(log(18000.0), log(1100.0), far))
	var blend := 1.0 if snap else 1.0 - exp(-delta * 3.0)
	song.volume_db = lerpf(song.volume_db, gain, blend)
	song_filter.cutoff_hz = lerpf(song_filter.cutoff_hz, cutoff, blend)

func _exit_tree() -> void:
	if song_bus.is_empty(): return
	# Audio buses outlive scenes; remove only this scene's private filter bus.
	var index := AudioServer.get_bus_index(song_bus)
	if index >= 0: AudioServer.remove_bus(index)

func snapshot() -> Dictionary:
	return {"active": active, "completed": completed, "step": step, "tuned": tuned, "dance": dance_time, "closing": closing_time, "waking": waking_time, "echo_collected": echo_collected, "echo_offered": echo_offered, "elapsed": elapsed, "clock": saved_clock, "harvest": harvest_mask, "run_round": run_round, "run_target": run_target, "run_time": run_time, "ravers": ravers_spawned}

func apply_snapshot(data: Dictionary) -> void:
	if data.is_empty(): return
	var was_active := active
	active = bool(data.get("active", false))
	completed = bool(data.get("completed", false))
	step = clampi(int(data.get("step", 0)), 0, WAKING)
	tuned = clampi(int(data.get("tuned", 0)), 0, 3)
	dance_time = float(data.get("dance", 0))
	closing_time = clampf(float(data.get("closing", 0)), 0, CLOSING_SECONDS)
	waking_time = clampf(float(data.get("waking", 0)), 0, WAKING_SECONDS)
	echo_collected = bool(data.get("echo_collected", false))
	echo_offered = bool(data.get("echo_offered", false))
	harvest_mask = int(data.get("harvest", 0))
	run_round = int(data.get("run_round", 0))
	run_target = int(data.get("run_target", -1))
	run_time = float(data.get("run_time", 0))
	ravers_spawned = bool(data.get("ravers", false))
	elapsed = float(data.get("elapsed", 0))
	if active and not was_active: _enter_presentation(float(data.get("clock", main.day_night.clock_seconds)))
	if active: saved_clock = float(data.get("clock", saved_clock))
	if active:
		_present_stage()
		_update_ending(0.0)
	if was_active and not active:
		_leave_presentation()
		if completed: _completion_message()

func _material(colour: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.3
	m.emission_enabled = glow > 0
	m.emission = colour
	m.emission_energy_multiplier = glow
	return m

func _box(at: Vector3, size: Vector3, colour: Color, solid := false, glow := 0.0, fade_at_end := true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(colour, glow)
	if glow > 0 and fade_at_end: party_glows.append({"material": mesh.material_override, "energy": glow})
	scenery.add_child(mesh)
	mesh.position = at
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		shape.shape = bounds
		body.add_child(shape)
		mesh.add_child(body)
	return mesh

func _label(text: String, at: Vector3, colour: Color, size := 45) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.modulate = colour
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	scenery.add_child(label)
	label.position = at
	party_labels.append(label)
	return label

func _guest(model: String, at: Vector3) -> Node3D:
	# Meshy's rigged NPCs already use metres. Their bind-pose bounds must not be fitted.
	var guest := WorldModels.attach(scenery, model, at)
	if guest:
		for mesh: GeometryInstance3D in guest.find_children("*", "GeometryInstance3D", true, false): guest_meshes.append(mesh)
		for animation: AnimationPlayer in guest.find_children("*", "AnimationPlayer", true, false):
			for clip in animation.get_animation_list():
				if "idle" in clip.to_lower():
					animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
					animation.play(clip)
					break
	return guest

func _build_party() -> void:
	scenery = Node3D.new()
	add_child(scenery)
	var base := Map.ground_pos(SITE.x, SITE.y)
	WorldModels.attach(scenery, "goa_stage", base, 12.0, 0)
	WorldModels.attach(scenery, "goa_bar", Map.ground_pos(BAR.x, BAR.y), 4.0, 0)
	# Explicit collision protects the DJ desk without blocking the forest trail.
	_box(base + Vector3(0, 1, 0), Vector3(8, 2, 3), Color(0.08, 0.06, 0.12), true)
	# The model supplies the visuals; the proxy only supplies collision.
	scenery.get_child(scenery.get_child_count() - 1).hide()
	stage_sign = _label("SCHORCHEN\nAFTER HOURS", base + Vector3(0, 5, 0), COLOURS[0], 72)
	party_labels.erase(stage_sign)
	_label("HAZE BAR\nBeer · Mushrooms · Clear Head", Map.ground_pos(BAR.x, BAR.y) + Vector3(0, 4.9, 0), COLOURS[1])   # above the canopy, not behind it
	for i in 3:
		var pos := Map.ground_pos(TOTEMS[i].x, TOTEMS[i].y)
		WorldModels.attach(scenery, "goa_totem", pos, 2.6)
		var lamp := OmniLight3D.new()
		lamp.light_color = COLOURS[i]
		lamp.omni_range = 5
		scenery.add_child(lamp)
		lamp.position = pos + Vector3.UP * 2
		totem_lights.append(lamp)
		_label(["I · TURQUOISE", "II · PINK", "III · VIOLET"][i], pos + Vector3.UP * 3.3, COLOURS[i], 36)
	for i in 6:
		var lamp := SpotLight3D.new()
		lamp.light_color = COLOURS[i % 3]
		lamp.spot_range = 34
		lamp.spot_angle = 24
		lamp.light_volumetric_fog_energy = 6
		lamp.shadow_enabled = false
		scenery.add_child(lamp)
		lamp.position = base + Vector3((i - 2.5) * 1.8, 6, 1)
		lights.append(lamp)
		var beam := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.bottom_radius = 1.2
		cone.height = 18
		cone.radial_segments = 16
		beam.mesh = cone
		var beam_material := _material(Color(COLOURS[i % 3], 0.055), 0.6)
		beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = beam_material
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.add_child(beam)
		beam.position.z = -9
		beam.rotation.x = PI / 2
		beams.append(beam)
	for i in 2:
		var fill := OmniLight3D.new()
		fill.light_color = COLOURS[i]
		fill.light_energy = 4.5
		fill.omni_range = 15
		scenery.add_child(fill)
		fill.position = base + Vector3(-4 if i == 0 else 4, 4, 5)
		party_fills.append(fill)
	var bartender := _guest("npc_mechanic", Map.ground_pos(BAR.x, BAR.y - 1))
	if bartender: bartender.rotation.y = PI
	var dj := _guest("npc_secret_trader", base + Vector3(0, 0.6, -1))
	if dj: dj.rotation.y = PI
	# A luminous circle, pennant garlands and a trail make the destination legible in rain.
	for i in 40:
		var angle := TAU * i / 40.0
		var point := DANCE + Vector2(cos(angle), sin(angle)) * 6
		_box(Map.ground_pos(point.x, point.y) + Vector3.UP * 0.08, Vector3(0.45, 0.08, 0.45), COLOURS[i % 3], false, 2.5)
	for road: Dictionary in Map.ROADS:
		if not "Sorchen" in str(road.get("name", "")): continue
		for i in range(4, road.pts.size(), 5):
			var point: Vector2 = road.pts[i] + Vector2(2.7, 0)
			if point.y < -202: break
			var pos := Map.ground_pos(point.x, point.y)
			WorldModels.attach(scenery, "mushroom_cluster", pos, 0.65)
			_box(pos + Vector3.UP * 0.3, Vector3(0.13, 0.15, 0.13), COLOURS[i % 3], false, 4.0, false)
	for i in 22:
		var x := -122.0 + i * 0.85
		var point := Map.ground_pos(x, -187)
		var pennant := _box(point + Vector3.UP * (5.0 - sin(i / 21.0 * PI)), Vector3(0.25, 0.36, 0.02), COLOURS[i % 3], false, 0.15)
		pennant.rotation.z = PI / 4
	for i in 8:
		var angle := TAU * i / 8.0
		var point := DANCE + Vector2(cos(angle), sin(angle)) * 4.5
		if point.y < -197.0: continue    # never inside the stage (its front is at z -199.5)
		var pos := Map.ground_pos(point.x, point.y)
		var guest := _guest("npc_mechanic" if i % 2 == 0 else "npc_secret_trader", pos)
		if guest:
			guest.rotation.y = -angle - PI / 2
			guest.set_meta("floor", pos.y)
			dancers.append(guest)
	# the three glowing mushrooms of the harvest round
	for i in GLOW_SPOTS.size():
		var holder := Node3D.new()
		scenery.add_child(holder)
		var pos := Map.ground_pos(GLOW_SPOTS[i].x, GLOW_SPOTS[i].y)
		holder.position = pos
		WorldModels.attach(holder, "mushroom_cluster", Vector3.ZERO, 0.9)
		var glow := _box(pos + Vector3.UP * 0.35, Vector3(0.18, 0.2, 0.18), COLOURS[i], false, 5.0, false)
		glow.reparent(holder)
		var lamp := OmniLight3D.new()
		lamp.light_color = COLOURS[i]
		lamp.light_energy = 1.6
		lamp.omni_range = 4.0
		lamp.shadow_enabled = false
		lamp.position.y = 0.6
		holder.add_child(lamp)
		var caption := _label("GLOWING MUSHROOM\n[E] Pick", pos + Vector3.UP * 1.1, COLOURS[i], 30)
		caption.reparent(holder)
		glow_props.append(holder)
	song = AudioStreamPlayer3D.new()
	song.stream = load(SONG) if ResourceLoader.exists(SONG) else load("res://assets/audio/music/secret_goa_placeholder.wav")
	if song.stream is AudioStreamMP3: song.stream.loop = true
	if song.stream is AudioStreamWAV:
		song.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		song.stream.loop_end = song.stream.data.size() / 2
	song.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	song.attenuation_filter_db = 0.0
	song.max_distance = 0
	song.volume_db = -35
	song.max_db = -6
	song_bus = "SecretGoa_%d" % get_instance_id()
	var bus_index := AudioServer.bus_count
	AudioServer.add_bus(bus_index)
	AudioServer.set_bus_name(bus_index, song_bus)
	AudioServer.set_bus_send(bus_index, "Master")
	song_filter = AudioEffectLowPassFilter.new()
	song_filter.cutoff_hz = 1100.0
	AudioServer.add_bus_effect(bus_index, song_filter)
	song.bus = song_bus
	add_child(song)
	song.position = base + Vector3.UP * 2

func _build_echo() -> void:
	# Reuse the Meshy sound totem as a small, magical quest relic. It belongs to
	# the team, so a full inventory, death or disconnect cannot lose the objective.
	echo_prop = Node3D.new()
	scenery.add_child(echo_prop)
	var model := WorldModels.attach(echo_prop, "goa_totem", Vector3.ZERO, 0.65)
	if model:
		for mesh: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false): echo_meshes.append(mesh)
	echo_light = OmniLight3D.new()
	echo_light.omni_range = 6.0
	echo_light.position.y = 0.4
	echo_prop.add_child(echo_light)
	echo_caption = _label("ECHO OF THE NIGHT\n[E] Collect", Vector3.ZERO, COLOURS[0], 38)
	party_labels.erase(echo_caption)
	echo_caption.reparent(echo_prop)
	echo_caption.position = Vector3.UP * 1.1
	echo_prop.hide()

func _build_weather() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 1800
	rain.lifetime = 1.3
	rain.visibility_aabb = AABB(Vector3(-24, -24, -24), Vector3(48, 48, 48))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(17, 1, 17)
	process.direction = Vector3(-0.12, -1, 0.06)
	process.spread = 3
	process.initial_velocity_min = 16
	process.initial_velocity_max = 22
	process.gravity = Vector3(0, -3, 0)
	rain.process_material = process
	var streak := BoxMesh.new()
	streak.size = Vector3(0.012, 0.48, 0.012)
	streak.material = _material(Color(0.3, 0.44, 0.6), 0.35)
	rain.draw_pass_1 = streak
	add_child(rain)
	rain.emitting = false
	rain_sound = AudioStreamPlayer.new()
	rain_sound.stream = load("res://assets/audio/sfx/secret_rain.wav")
	if rain_sound.stream is AudioStreamWAV:
		rain_sound.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		rain_sound.stream.loop_end = rain_sound.stream.data.size() / 2
	rain_sound.volume_db = -20.0 + linear_to_db(0.5)
	add_child(rain_sound)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 4
	add_child(canvas)
	haze = ColorRect.new()
	haze.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float strength = 0.55;
uniform float awakening = 0.0;
void fragment() {
 vec2 uv = SCREEN_UV;
 float edge = smoothstep(0.12, 0.7, length(uv - 0.5));
 vec2 drift = vec2(sin(uv.y * 19.0 + TIME * 0.8), cos(uv.x * 17.0 + TIME * 0.6)) * 0.004 * edge * strength;
 vec3 col = texture(screen_texture, uv + drift).rgb;
 col.r = texture(screen_texture, uv + drift + vec2(0.003 * edge * strength, 0.0)).r;
 col += vec3(0.035, 0.005, 0.05) * edge * strength;
 COLOR = vec4(mix(col, vec3(0.95, 0.83, 0.64), awakening), 1.0);
}"""
	haze_material = ShaderMaterial.new()
	haze_material.shader = shader
	haze.material = haze_material
	canvas.add_child(haze)
	panel = PanelContainer.new()
	panel.position = Vector2(24, 160)
	panel.custom_minimum_size = Vector2(400, 110)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.018, 0.06, 0.9)
	style.border_color = COLOURS[0]
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_top = 14
	style.content_margin_right = 18
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	title = Label.new()
	title.add_theme_color_override("font_color", COLOURS[0])
	column.add_child(title)
	copy = Label.new()
	copy.custom_minimum_size.x = 380
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(copy)

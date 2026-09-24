class_name SecretNight
extends Node3D

# The northern Sorchen trail remains inside the playable bounds here.
const SITE := Vector2(-108, -201)
const TOTEMS := [Vector2(-119, -193), Vector2(-111, -184), Vector2(-99, -192)]
const BAR := Vector2(-120, -202)
const DANCE := Vector2(-108, -195)
const SONG := "res://assets/audio/music/Goa_Party_Sidequest.mp3"
const CLOSING := 4
const ECHO := 5
const RETURN := 6
const WAKING := 7
const ECHO_POINT := SITE + Vector2(0, 8.0)
const CLOSING_SECONDS := 18.0
const WAKING_SECONDS := 8.0
const RETURN_RADIUS := 14.0
const REWARD := 150
const PREPARATION_SECONDS := 20.0
const STAGE_NAMES := ["DER FERNE KLANG", "KLANGTOTEMS", "KLARER KOPF", "EIN LETZTER TANZ", "LETZTER TRACK", "DAS ECHO DER NACHT", "DER HEIMWEG", "ZURÜCK IN DER WIRKLICHKEIT"]
const COLOURS := [Color(0.1, 0.9, 1.0), Color(1.0, 0.18, 0.6), Color(0.7, 0.35, 1.0)]
const INTRO := "Euer Team hat zu viele Pilze gegessen.\nIhr hört aus der Ferne einen Klang. Folgt ihm …"
const STEPS := ["Folgt dem Bass und den leuchtenden Pilzen in den Oberen Schorchen.",
	"Weckt die Klangtotems: TÜRKIS → PINK → VIOLETT. [E]",
	"Die Musik ist zurück. Holt an der Bar den Klarer-Kopf-Trank. [E]",
	"Bleibt für das Finale im leuchtenden Tanzkreis.",
	"Der letzte Beat klingt aus. Nehmt diesen Moment mit.",
	"Abschlussauftrag: Holt das Echo der Nacht vor dem DJ-Pult ab. [E]",
	"Bringt das Echo der Nacht zurück zur Feuerstelle. Sammelt das Team und legt es ins Feuer. [E]",
	"Das Echo verglüht. Bleibt zusammen am Feuer, bis der Kopf wieder klar ist."]
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
var haze_material: ShaderMaterial

func setup(game: Node) -> void:
	main = game
	add_to_group("render_dynamic")
	_build_party()
	_build_echo()
	_build_weather()
	_build_hud()
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
		2: return BAR + Vector2(0, 2)
		3: return DANCE
		CLOSING: return DANCE
		ECHO: return ECHO_POINT
	return Map.FIRE

func prompt(p: Player) -> String:
	if not active or not p.alive or p.controlling_drone or p.mounted_tower: return ""
	if Vector2(p.global_position.x, p.global_position.z).distance_to(target()) > 3.5: return ""
	match step:
		1: return "[E] Klangtotem stimmen · " + ["Türkis", "Pink", "Violett"][mini(tuned, 2)]
		2: return "[E] Klarer-Kopf-Trank trinken · Wasser, Minze und Waldmagie"
		ECHO: return "[E] Echo der Nacht aufnehmen · gemeinsamer Questgegenstand"
		RETURN:
			return "[E] Echo der Nacht ins Feuer legen" if echo_collected and _team_near(Map.FIRE, RETURN_RADIUS, true) else "Sammelt das Team und das Echo am Feuer …"
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
			if tuned == 3: step = 2
		2: step = 3
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
	_present_stage()
	_update_ending(0.0)
	return true

func _complete() -> void:
	if not active or completed or step != WAKING or not echo_offered or NetSession.is_client(): return
	active = false
	completed = true
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() else [main.player]
	for p: Player in actors: p.add_score(REWARD)
	_leave_presentation()
	main.waves.phase = "idle"
	main.waves.timer = PREPARATION_SECONDS
	_completion_message()

func _completion_message() -> void:
	main.music.play(main.music.intermission_track(saved_clock / 3600.0))
	main.hud.message("ECHO DER NACHT · AUFTRAG ERFÜLLT\nDas letzte Echo verglüht. Ihr seid wieder zu Hause.\n+%d Rem Dollars pro Spieler · Wave 5 in %d Sekunden" % [REWARD, int(PREPARATION_SECONDS)], 10.0)

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
	if not active: return
	if main.over:
		active = false
		_leave_presentation()
		return
	if not main.started or get_tree().paused: return
	elapsed += delta
	if not NetSession.is_client():
		if step == 0 and _team_near(DANCE, 12.0): step = 1
		if step == 3:
			if _team_near(DANCE, 7.0, true): dance_time += delta
			if dance_time >= 16.0:
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
	title.text = "SECRET NACHT · OBERER SCHORCHEN"
	var detail := "%d m · Wave 5 wartet auf euch" % int(distance)
	if step == 3: detail = "Alle lebenden Teammitglieder im Kreis · %d / 16 s" % mini(16, int(dance_time))
	elif step == CLOSING: detail = "Letzter Track · noch %d s" % ceili(CLOSING_SECONDS - closing_time)
	elif step == RETURN: detail = "Echo der Nacht: im Teambesitz · %d m bis zur Feuerstelle" % int(distance)
	elif step == WAKING: detail = "Zusammen am Feuer · %d / %d s" % [mini(int(WAKING_SECONDS), int(waking_time)), int(WAKING_SECONDS)]
	copy.text = STEPS[step] + "\n" + detail
	main.hud.set_wave(5, "SECRET NACHT · " + STAGE_NAMES[step])
	rain.global_position = main.player.global_position + Vector3(0, 10, 0)
	var beat := 0.5 + 0.5 * sin(elapsed * TAU * 140.0 / 60.0)
	var energy := party_energy()
	for i in lights.size():
		lights[i].rotation = Vector3(-0.85 + sin(elapsed * 0.4 + i) * 0.3, sin(elapsed * 0.31 + i * 2) * 1.1, 0)
	for i in dancers.size():
		dancers[i].rotation.z = sin(elapsed * TAU * 140.0 / 120.0 + i) * 0.09 * energy
		dancers[i].position.y = float(dancers[i].get_meta("floor")) + beat * 0.09 * energy
	_update_ending(delta)

func party_energy() -> float:
	if step < CLOSING: return 1.0
	if step > CLOSING: return 0.0
	return 1.0 - smoothstep(4.0, CLOSING_SECONDS, closing_time)

func _present_stage() -> void:
	if _announced_step == step: return
	_announced_step = step
	match step:
		0: main.hud.message(INTRO, 10.0)
		3: main.hud.message("DJ: Noch ein letzter Tanz, ihr Waldgeister!\nKommt alle in den Kreis. Danach wird es Zeit, heimzugehen.", 7.0)
		CLOSING: main.hud.message("DJ: Das war unsere letzte Reise für heute.\nKommt gut heim. Wir sehen uns auf der anderen Seite des Morgens.", 8.0)
		ECHO: main.hud.message("ABSCHLUSSAUFTRAG · DAS ECHO DER NACHT\nAm DJ-Pult bleibt ein leuchtendes Klangtotem zurück.\nEine letzte Botschaft: Bringt mein Echo zum Feuer. Nur dort endet dieser Traum.", 10.0)
		RETURN: main.hud.message("ECHO DER NACHT AUFGENOMMEN\nIhr spürt den letzten Beat im Totem. Bringt es gemeinsam zur Feuerstelle.\nDie Leuchtpilze weisen euch den Heimweg.", 8.0)
		WAKING: main.hud.message("Ihr legt das Echo ins Feuer. Der letzte Beat wird zu einem Funken.\nEin tiefer Atemzug. Die Welt wird wieder klar.", 7.0)

func _update_ending(delta: float) -> void:
	var energy := party_energy()
	var beat := 0.5 + 0.5 * sin(elapsed * TAU * 140.0 / 60.0)
	for light in lights: light.light_energy = (3.0 + beat * 2.0) * energy
	for i in totem_lights.size(): totem_lights[i].light_energy = (3.5 if i < tuned else 0.8) * energy
	for light in party_fills: light.light_energy = 4.5 * energy
	for beam in beams:
		beam.transparency = 1.0 - energy
		beam.visible = energy > 0.001
	for mesh in guest_meshes:
		mesh.transparency = 1.0 - energy
		mesh.visible = energy > 0.001
	for glow in party_glows: glow.material.emission_energy_multiplier = glow.energy * energy
	for label in party_labels: label.modulate.a = energy
	stage_sign.text = "SCHORCHEN\nAFTER HOURS" if step < CLOSING else ("EIN LETZTER BEAT" if step == CLOSING else "BIS ZUM NÄCHSTEN TRAUM")
	stage_sign.modulate = COLOURS[0].lerp(Color(0.7, 0.55, 0.3), 1.0 - energy)
	var weather := 1.0 if step < CLOSING else energy
	rain.amount_ratio = weather
	rain.emitting = weather > 0.001
	rain_sound.volume_db = -20.0 + linear_to_db(maxf(0.0001, weather))
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
		echo_caption.text = "Das Echo verglüht …" if echo_offered else "ECHO DER NACHT\n[E] Aufnehmen"
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
	return {"active": active, "completed": completed, "step": step, "tuned": tuned, "dance": dance_time, "closing": closing_time, "waking": waking_time, "echo_collected": echo_collected, "echo_offered": echo_offered, "elapsed": elapsed, "clock": saved_clock}

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
	_label("NEBELBAR\nBier · Pilze · Klarer Kopf", Map.ground_pos(BAR.x, BAR.y) + Vector3(0, 3, 0), COLOURS[1])
	for i in 3:
		var pos := Map.ground_pos(TOTEMS[i].x, TOTEMS[i].y)
		WorldModels.attach(scenery, "goa_totem", pos, 2.6)
		var lamp := OmniLight3D.new()
		lamp.light_color = COLOURS[i]
		lamp.omni_range = 5
		scenery.add_child(lamp)
		lamp.position = pos + Vector3.UP * 2
		totem_lights.append(lamp)
		_label(["I · TÜRKIS", "II · PINK", "III · VIOLETT"][i], pos + Vector3.UP * 3.3, COLOURS[i], 36)
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
		var pos := Map.ground_pos(point.x, point.y)
		var guest := _guest("npc_mechanic" if i % 2 == 0 else "npc_secret_trader", pos)
		if guest:
			guest.rotation.y = -angle - PI / 2
			guest.set_meta("floor", pos.y)
			dancers.append(guest)
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
	echo_caption = _label("ECHO DER NACHT\n[E] Aufnehmen", Vector3.ZERO, COLOURS[0], 38)
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
	rain_sound.volume_db = -20
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

# Opening sequence: KONM Games card with the intro track, then the player wakes up in dense fog at the
# far end of the Sennhofstrasse. A typewriter briefing and a direction arrow lead along the road to the
# Weg zur Hütte; the fog lifts and the intro track fades the closer the player gets to the hut. Reaching
# the Weg zur Hütte releases the first wave (main connects road_reached to the waves).
class_name Intro
extends Node

signal road_reached
signal finished

const START := Vector2(136.0, 108.0)          # south end of the Sennhofstrasse inside the playable bounds
const START_YAW := 0.0                        # looking north, up the road
const LOGO_IN := 1.2
const LOGO_HOLD := 2.6
const LOGO_OUT := 1.0
const WAKE := 3.0                             # black -> foggy world
const FOG_DENSE := 0.045                      # exponential fog density when waking up (~40 m sight)
const VFOG_DENSE := 0.03
const MUSIC_DB := -6.0
const TYPE_SPEED := 32.0                      # characters per second
const BRIEFING := "Finde die Waldhütte.\nFolge der Strasse und dem Richtungspfeil."
const BRIEFING_ROAD := "Sie haben dich gehört.\nZur Waldhütte, halte die Barrikaden!"
# the arrow follows the road: junction, along the Weg zur Hütte, the fork, the hut
const WAYPOINTS := [Vector2(124.0, 21.0), Vector2(70.0, 41.0), Vector2(30.0, 54.5), Vector2(7.0, 61.0), Vector2(4.0, -4.0)]

var main: Node
var player: Player
var env: Environment
var active := false
var phase := "off"
var _t := 0.0
var _layer: CanvasLayer
var _black: ColorRect
var _logo: TextureRect
var _text: Label
var _arrow: Control
var _dist_label: Label
var _music: AudioStreamPlayer
var _fog_base := 0.0
var _vfog_base := 0.0
var _sky_affect_base := 1.0
var _aerial_base := 0.0
var _d0 := 1.0
var _typed := 0.0
var _briefing := BRIEFING
var _wp := 0
var _road_done := false
var _road_pts: PackedVector2Array
var _test := false
var _test_t := 0.0
var _route: PackedVector2Array          # START + WAYPOINTS, the walk the music follows
var _route_len := 1.0
var _path_prog := 0.0                   # 0..1 along the route, never decreases
var _fade_t := -1.0                     # >= 0: the intro track is fading out (seconds elapsed)
const FADE_OUT := 4.0
const MUSIC_STOP_DIST := 45.0           # silent before the player stands at the fire

func setup(m: Node, p: Player, e: Environment) -> void:
	main = m
	player = p
	env = e
	_test = "--intro-test" in OS.get_cmdline_user_args()
	for r in Map.ROADS:
		if r["name"].begins_with("Weg zur H"):
			_road_pts = r["pts"]
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.visible = false
	_layer.add_child(_black)
	_logo = TextureRect.new()
	var lp := "res://assets/ui/konm_games_logo.png"
	if ResourceLoader.exists(lp):
		_logo.texture = load(lp)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_logo.grow_vertical = Control.GROW_DIRECTION_BOTH
	_logo.custom_minimum_size = Vector2(420, 420)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	_layer.add_child(_logo)
	# briefing, typewriter style, lower third
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 22)
	_text.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_text.add_theme_constant_override("shadow_offset_x", 1)
	_text.add_theme_constant_override("shadow_offset_y", 1)
	_text.add_theme_constant_override("line_spacing", 10)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_text.anchor_left = 0.2
	_text.anchor_right = 0.8
	_text.offset_top = -250
	_text.offset_bottom = -150
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.visible = false
	_layer.add_child(_text)
	# direction arrow above the crosshair, with the distance to the next waypoint
	_arrow = Control.new()
	_arrow.set_anchors_preset(Control.PRESET_CENTER)
	_arrow.position.y = -120
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	_arrow.visible = false
	_layer.add_child(_arrow)
	_dist_label = Label.new()
	_dist_label.add_theme_font_size_override("font_size", 14)
	_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dist_label.set_anchors_preset(Control.PRESET_CENTER)
	_dist_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dist_label.position.y = -92
	_dist_label.modulate.a = 0.8
	_dist_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dist_label.visible = false
	_layer.add_child(_dist_label)
	_music = AudioStreamPlayer.new()
	var mp := "res://assets/audio/music/intro.mp3"
	if ResourceLoader.exists(mp):
		var st: AudioStream = load(mp)
		if st is AudioStreamMP3:
			st.loop = true
		_music.stream = st
	_music.volume_db = MUSIC_DB
	add_child(_music)
	# The guidance sits above the HUD so the black wake-up screen covers it, which also put the
	# briefing and the arrow on top of the pause menu; the menu overlay hides the whole layer.
	if main.hud:
		main.hud.overlay.visibility_changed.connect(func() -> void: _layer.visible = not main.hud.overlay.visible)
		_layer.visible = not main.hud.overlay.visible

func showing_guidance() -> bool:
	return active or (_text != null and _text.visible)

static func start_position(index: int = 0) -> Vector3:
	var point := START + Vector2(float(index % 2) * 1.3, float(index / 2) * 1.5)
	return Map.ground_pos(point.x, point.y) + Vector3.UP * 0.3

func begin(keep_position: bool = false) -> void:
	active = true
	phase = "logo"
	_t = 0.0
	_fog_base = env.fog_density
	_vfog_base = env.volumetric_fog_density
	_sky_affect_base = env.fog_sky_affect
	_aerial_base = env.fog_aerial_perspective
	if not keep_position: player.global_position = start_position()
	player.velocity = Vector3.ZERO
	player.rotation.y = START_YAW
	player.pitch = 0.0
	player.head.rotation.x = 0.0
	player.active = false
	_d0 = maxf(1.0, START.distance_to(WAYPOINTS[WAYPOINTS.size() - 1]))
	_route = PackedVector2Array([START])
	for w in WAYPOINTS:
		_route.append(w)
	_route_len = 0.0
	for i in _route.size() - 1:
		_route_len += _route[i].distance_to(_route[i + 1])
	_path_prog = 0.0
	_fade_t = -1.0
	env.fog_density = FOG_DENSE
	env.volumetric_fog_density = VFOG_DENSE
	# the sky sinks into the same murk, otherwise the fogged trees stand out white against a dark sky
	env.fog_sky_affect = 1.0
	env.fog_aerial_perspective = 0.0
	_black.visible = true
	_black.color.a = 1.0
	_logo.modulate.a = 0.0
	if _music.stream and not "--no-music" in OS.get_cmdline_user_args():
		_music.play()

func _progress() -> float:
	# 0 at the start, 1 at the hut
	var p := Vector2(player.global_position.x, player.global_position.z)
	var d := p.distance_to(WAYPOINTS[WAYPOINTS.size() - 1])
	return clampf(1.0 - d / _d0, 0.0, 1.0)

# fraction of the route (start -> junction -> Weg zur Hütte -> fork -> hut) already walked, measured along the
# polyline from the nearest point, so the music fades with the actual way and never comes back up
func _path_progress() -> float:
	var p := Vector2(player.global_position.x, player.global_position.z)
	var best := INF
	var along := 0.0
	var acc := 0.0
	for i in _route.size() - 1:
		var a := _route[i]
		var b := _route[i + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var dist := p.distance_to(q)
		if dist < best:
			best = dist
			along = acc + a.distance_to(q)
		acc += a.distance_to(b)
	_path_prog = maxf(_path_prog, clampf(along / maxf(_route_len, 1.0), 0.0, 1.0))
	return _path_prog

func _dist_to_road() -> float:
	return distance_to_road(player.global_position)

func distance_to_road(at: Vector3) -> float:
	var p := Vector2(at.x, at.z)
	var best := 1e9
	for i in _road_pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, _road_pts[i], _road_pts[i + 1])
		best = minf(best, p.distance_to(q))
	return best

func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	match phase:
		"logo":
			if _t < LOGO_IN:
				_logo.modulate.a = _t / LOGO_IN
			elif _t < LOGO_IN + LOGO_HOLD:
				_logo.modulate.a = 1.0
			elif _t < LOGO_IN + LOGO_HOLD + LOGO_OUT:
				_logo.modulate.a = 1.0 - (_t - LOGO_IN - LOGO_HOLD) / LOGO_OUT
			else:
				_logo.modulate.a = 0.0
				_logo.visible = false
				phase = "wake"
				_t = 0.0
				player.active = player.alive and not main.hud.overlay.visible
				_text.visible = true
				_text.text = ""
				_typed = 0.0
		"wake", "walk":
			if phase == "wake":
				# eyes open: black fades, a slow blink in the middle
				var k := clampf(_t / WAKE, 0.0, 1.0)
				var blink := 0.35 * maxf(0.0, sin(k * PI * 2.0)) if k < 0.5 else 0.0
				_black.color.a = clampf(1.0 - k + blink, 0.0, 1.0)
				if k >= 1.0:
					_black.visible = false
					phase = "walk"
			_type(delta)
			_update_guidance()
			var prog := _progress()
			# the fog lifts over the first 60 % of the way, the music fades all the way to the hut
			var fog_k := smoothstep(0.0, 0.6, prog)
			env.fog_density = lerpf(FOG_DENSE, _fog_base, fog_k)
			env.volumetric_fog_density = lerpf(VFOG_DENSE, _vfog_base, fog_k)
			env.fog_sky_affect = lerpf(1.0, _sky_affect_base, fog_k)
			env.fog_aerial_perspective = lerpf(0.0, _aerial_base, fog_k)
			# the track follows the walked route: full at the start, half as loud at the junction, a whisper
			# at the fork, and it fades out completely once wave 1 begins or the hut is 45 m away
			var pp := _path_progress()
			var base_db := MUSIC_DB + linear_to_db(maxf(0.001, pow(1.0 - pp, 2.2)))
			var to_hut := Vector2(player.global_position.x, player.global_position.z).distance_to(WAYPOINTS[WAYPOINTS.size() - 1])
			if _fade_t < 0.0 and (_road_done or main.waves.wave > 0 or to_hut < MUSIC_STOP_DIST):
				_fade_t = 0.0
			if _fade_t >= 0.0:
				_fade_t += delta
				var k := clampf(_fade_t / FADE_OUT, 0.0, 1.0)
				_music.volume_db = base_db + linear_to_db(maxf(0.001, 1.0 - k))
				if k >= 1.0 and _music.playing:
					_music.stop()
			else:
				_music.volume_db = base_db
			if not _road_done and _dist_to_road() < 5.0:
				_road_done = true
				_briefing = BRIEFING_ROAD
				_typed = 0.0
				_text.text = ""
				road_reached.emit()
			if prog > 0.93:
				_end()
		_:
			pass
	if _test:
		_test_step(delta)

func _type(delta: float) -> void:
	if _typed < _briefing.length():
		_typed = minf(_briefing.length(), _typed + delta * TYPE_SPEED)
		_text.text = _briefing.substr(0, int(_typed))

func _update_guidance() -> void:
	var p := Vector2(player.global_position.x, player.global_position.z)
	while _wp < WAYPOINTS.size() - 1 and p.distance_to(WAYPOINTS[_wp]) < 12.0:
		_wp += 1
	_arrow.visible = true
	_dist_label.visible = true
	var target: Vector2 = WAYPOINTS[_wp]
	_dist_label.text = "%d m" % int(p.distance_to(WAYPOINTS[WAYPOINTS.size() - 1]))
	# arrow angle relative to the view direction (0 = straight ahead)
	var to := Vector3(target.x - p.x, 0.0, target.y - p.y)
	var local: Vector3 = player.global_transform.basis.inverse() * to
	_arrow.set_meta("angle", atan2(local.x, -local.z))
	_arrow.queue_redraw()

func _draw_arrow() -> void:
	var a: float = _arrow.get_meta("angle", 0.0)
	var pts := PackedVector2Array()
	for v in [Vector2(0, -22), Vector2(14, 10), Vector2(0, 3), Vector2(-14, 10)]:
		pts.append((v as Vector2).rotated(a))
	_arrow.draw_colored_polygon(pts, Color(1.0, 0.72, 0.3, 0.95))
	var outline := pts.duplicate()
	outline.append(pts[0])
	_arrow.draw_polyline(outline, Color(0, 0, 0, 0.7), 2.0, true)

func _end() -> void:
	active = false
	phase = "done"
	env.fog_density = _fog_base
	env.volumetric_fog_density = _vfog_base
	env.fog_sky_affect = _sky_affect_base
	env.fog_aerial_perspective = _aerial_base
	_music.stop()
	_arrow.visible = false
	_dist_label.visible = false
	var tw := create_tween()
	tw.tween_property(_text, "modulate:a", 0.0, 1.5)
	tw.tween_callback(_text.hide)
	finished.emit()

# --intro-test: prints the phases, jumps to the road after a few seconds, saves screenshots, quits
func _test_step(delta: float) -> void:
	_test_t += delta
	if _test_t > 7.0 and _test_t - delta <= 7.0:
		_shot("intro_wake.png")
		print("INTRO_PHASE ", phase, " fog=", env.fog_density, " music_db=", _music.volume_db)
	if _test_t > 8.0 and not _road_done:
		player.global_position = Map.ground_pos(118.0, 24.0) + Vector3(0, 0.3, 0)
		player.rotation.y = PI / 2.0
	if _road_done and _test_t > 11.0 and _test_t - delta <= 11.0:
		_shot("intro_road.png")
		print("INTRO_ROAD_REACHED zombies=", main.alive_zombies(), " waves_phase=", main.waves.phase, " music_db=", _music.volume_db, " path_prog=", _path_prog)
	if _road_done and _test_t > 14.0:
		print("INTRO_MUSIC_AFTER_FADE playing=", _music.playing, " db=", _music.volume_db)
		get_tree().quit()

func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://") + "../shots/"
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir + name)

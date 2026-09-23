# Brightness of every frame from the first loading-screen frame through the start menu, "Spiel
# starten", the KONM card, waking up in the fog and the way back to the main menu. Each drawn frame
# (the loading screen's own force_draw calls inside main._ready included) is read back and measured:
# a mostly blown-out white frame fails, and so does a loading-screen frame that is not the dark
# loading screen. Written for the white, overexposed grass picture that flashed up at start (23 Sep
# 2026): at the very first build the loading screen drew nothing and every build step showed the
# half-built world. Windowed, like a normal launch (no --smoke-test, the saved quality profile applies):
# Godot.exe --path godot --resolution 1600x900 --script res://tests/run.gd -- --suite=start_exposure --no-music
extends SceneTree

const WHITE_LEVEL := 0.92        # a pixel whose three channels all exceed this counts as blown out
const MAX_WHITE_SHARE := 0.2     # a frame with more blown-out pixels than this fails
const MAX_LOADING_EDGE := 0.12  # the loading screen's outer strips are dark ink (about 0.05); the crest
                                # and the text sit in the middle
const SAVE_LIMIT := 30

var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
var frames: Array[Dictionary] = []
var saved := 0
var _last_stage := ""
var _segment := ""
var _stage_frame := 0
var _dir := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 240000:
		push_error("START_EXPOSURE_TIMEOUT")
		quit(1)
	return false

func _stage() -> String:
	if BootScreen.find(self): return _segment + "loading screen"
	if not is_instance_valid(game): return _segment + "between scenes"
	for child in game.get_children():
		if child is BootScreen and not child.is_queued_for_deletion(): return _segment + "loading screen"
	if game.intro and game.intro.active: return _segment + "intro " + game.intro.phase
	if game.hud and game.hud.overlay.visible: return _segment + "menu"
	return _segment + "play"

func _frame_drawn() -> void:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty(): return
	var small := image.duplicate() as Image
	small.convert(Image.FORMAT_RGB8)
	small.resize(96, 54, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	var edge := 0.0
	var edge_count := 0
	var centre := 0.0
	var centre_count := 0
	var white := 0
	for y in small.get_height():
		for x in small.get_width():
			var c := small.get_pixel(x, y)
			var luminance := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			total += luminance
			if x < 14 or x >= small.get_width() - 14:
				edge += luminance
				edge_count += 1
			elif x >= 34 and x < 62 and y >= 6 and y < 21:   # the crest's yellow upper field
				centre += luminance
				centre_count += 1
			if c.r > WHITE_LEVEL and c.g > WHITE_LEVEL and c.b > WHITE_LEVEL: white += 1
	var count := small.get_width() * small.get_height()
	var label := _stage()
	var entry := {"t": Time.get_ticks_msec() - began, "stage": label, "mean": total / count, "edge": edge / edge_count, "centre": centre / centre_count,
		"white": float(white) / count, "frame": Engine.get_frames_drawn()}
	var camera := root.get_camera_3d()
	if camera:
		entry["camera"] = str(camera.get_path()).get_file()
		entry["at"] = camera.global_position.snappedf(0.1)
	var bright: bool = entry.white > MAX_WHITE_SHARE
	if bright and is_instance_valid(game) and game.settings and game.settings.env:
		entry["fog"] = [game.settings.env.fog_density, game.settings.env.volumetric_fog_density]
		entry["sun"] = game.settings.sun.light_energy if game.settings.sun else -1.0
		entry["paused"] = paused
	frames.append(entry)
	_stage_frame = 0 if label != _last_stage else _stage_frame + 1
	# the first three frames of every stage, and every blown-out one
	if (bright or _stage_frame < 3) and saved < SAVE_LIMIT:
		saved += 1
		image.save_png(_dir + "%03d_%s%s.png" % [frames.size(), label.replace(" ", "_"), "_WHITE" if bright else ""])
	if bright or _stage_frame < 3:
		print("START_FRAME ", JSON.stringify(entry))
	_last_stage = label

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("start_exposure needs a rendered window.")
		quit(1)
		return
	_dir = ProjectSettings.globalize_path("res://") + "../artifacts/start-exposure/"
	DirAccess.make_dir_recursive_absolute(_dir)
	for file in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir + file)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	RenderingServer.frame_post_draw.connect(_frame_drawn)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	# the loading screen fades out, then the menu stands for a moment
	await create_timer(3.0).timeout
	game._on_start()
	# KONM card (4.8 s), waking up (3 s) and the first steps in the fog
	await create_timer(12.0).timeout
	# Pause -> Hauptmenü: the old scene hangs its cover under the root before the rebuild
	game._pause()
	await create_timer(1.0).timeout
	check(not game.intro._layer.visible, "The pause menu hides the intro briefing and arrow instead of wearing them on top")
	_segment = "reload "
	game._to_main_menu()
	await scene_changed
	game = current_scene
	while not game.navigation_ready: await process_frame
	await create_timer(2.0).timeout
	RenderingServer.frame_post_draw.disconnect(_frame_drawn)

	var worst := {}
	var by_stage := {}
	for entry in frames:
		var key: String = entry.stage
		if not by_stage.has(key): by_stage[key] = {"frames": 0, "worst_white": 0.0, "brightest": 0.0, "brightest_edge": 0.0, "centres": []}
		by_stage[key].centres.append(entry.centre)
		by_stage[key].frames += 1
		by_stage[key].worst_white = maxf(by_stage[key].worst_white, entry.white)
		by_stage[key].brightest = maxf(by_stage[key].brightest, entry.mean)
		by_stage[key].brightest_edge = maxf(by_stage[key].brightest_edge, entry.edge)
		if worst.is_empty() or entry.white > worst.white: worst = entry
	for key in by_stage:
		var centres: Array = by_stage[key].centres
		centres.sort()
		by_stage[key].erase("centres")
		by_stage[key]["centre_median"] = centres[centres.size() / 2]
		print("START_STAGE %-16s %s" % [key, JSON.stringify(by_stage[key])])
	check(frames.size() > 100, "Frames were read back (%d)" % frames.size())
	check(by_stage.has("loading screen") and by_stage.has("menu") and by_stage.has("intro wake")
		and by_stage.has("reload loading screen") and by_stage.has("reload menu"),
		"The capture covers both loading screens, both menus and waking up (%s)" % str(by_stage.keys()))
	for key in by_stage:
		check(by_stage[key].worst_white <= MAX_WHITE_SHARE,
			"%s: no blown-out frame (worst %.0f %% white)" % [key, 100.0 * by_stage[key].worst_white])
		if key.ends_with("loading screen"):
			check(by_stage[key].brightest_edge <= MAX_LOADING_EDGE,
				"%s: every frame shows the dark loading screen, never the world behind it (brightest outer strip %.2f)" % [key, by_stage[key].brightest_edge])
			check(by_stage[key].centre_median > 0.2,
				"%s: the crest stands above the title (yellow field brightness %.2f)" % [key, by_stage[key].centre_median])
	print("START_EXPOSURE_WORST ", JSON.stringify(worst))
	print("START_EXPOSURE_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func shot(screen: BootScreen, name: String) -> void:
	if "--render-loading" not in OS.get_cmdline_user_args(): return
	screen._paint()
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/loading-tips/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + name + ".png")
	check(screen._tip_paragraph.get_size().y <= ThemeDB.fallback_font.get_height(BootScreen.TIP_FONT_SIZE) * 4, "Tip fits the reserved text area: " + name)

func run() -> void:
	var screen := BootScreen.cover(self)
	screen.set_process(false)
	var first := screen.tip_text()
	screen.step(0.4, false)
	screen.step(0.7, false)
	check(screen.tip_text() == first and screen._target == 0.7, "Load progress changes without interrupting a readable tip")
	screen._update_tip(screen._next_tip_ms - 1)
	check(screen.tip_text() == first, "A tip remains visible for the full reading interval")
	var seen := {first: true}
	for i in BootScreen.TIPS.size() - 1:
		screen._update_tip(screen._next_tip_ms)
		seen[screen.tip_text()] = true
	check(seen.size() == BootScreen.TIPS.size(), "Every tip appears before any repetition")
	var last := screen.tip_text()
	screen._update_tip(screen._next_tip_ms)
	check(screen.tip_text() != last, "A new shuffled cycle does not repeat the previous tip")
	last = screen.tip_text()
	screen._next_tip_ms = 0
	screen.step(0.9, false)
	check(screen.tip_text() != last and screen._target == 0.9, "A build step rotates overdue tips even without idle frames")
	check(BootScreen.cover(self) == screen, "Scene reloads reuse the existing loading cover")
	Lang.set_language("de")
	var translated := true
	for msgid: String in BootScreen.TIPS:
		translated = translated and Lang.text(msgid) != msgid
	check(translated, "Every gameplay tip has a German translation")
	if "--render-loading" in OS.get_cmdline_user_args():
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1600, 900)
		for i in [0, 3, 8]:
			screen._tip_index = i
			await shot(screen, "de-%d" % i)
		root.size = Vector2i(1280, 720)
		await shot(screen, "de-720p")
		Lang.set_language("en")
		await shot(screen, "en-720p")
	screen.close()
	await create_timer(0.5).timeout
	check(not is_instance_valid(screen), "The loading cover fades away when loading finishes")
	print("LOADING_TIPS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

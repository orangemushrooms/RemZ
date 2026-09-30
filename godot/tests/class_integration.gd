extends SceneTree
const Classes = preload("res://scripts/character_classes.gd")
var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 180000: print("CLASS_INTEGRATION_TIMEOUT"); quit(1)
	return false
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)
func shot(name: String) -> void:
	if not "--class-visual" in OS.get_cmdline_user_args(): return
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/classes")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func click(control: Control) -> void:
	await process_frame
	await process_frame
	var point := control.get_global_rect().get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
	await process_frame

func run() -> void:
	CharacterProfile.data = CharacterProfile.empty_profile("Test survivor")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	var menu: Control = game.hud.overlay.get_node("CharacterMenu")
	check(CharacterProfile.can_edit(), "Character editing is available after boot")
	await create_timer(1.0).timeout
	check(root.get_visible_rect().encloses(menu.summary.get_global_rect()), "The full summary, including profile controls, fits the viewport")
	menu._open_profiles()
	await shot("profiles-en")
	menu.notice.hide()
	menu.open_page("skills")
	var locked: Button = menu._talent_buttons["0:0"]
	check(not locked.disabled, "Locked talents stay interactive so a click can explain the requirement")
	await click(locked)
	check(menu.notice.visible and CharacterProfile.data.classes.gunslinger.choices[0] == -1, "Clicking a locked talent shows a notice without equipping it")
	check(Lang.text(menu._requirement(0)).contains("7 700") and Lang.text(menu._requirement(0)).contains("level 5"), "The notice names the required class level and exact missing XP")
	check(root.get_visible_rect().encloses(menu.modal.get_global_rect()) and menu.modal.get_global_rect().encloses(menu._scroll.get_global_rect()), "The talent screen and its scrolling region fit the viewport")
	await shot("locked-en")
	Lang.set_language("de")
	await shot("locked-de")
	await click(menu.notice_body.find_children("*", "Button", true, false).back())
	check(not menu.notice.visible, "The notice closes through its real acknowledgement button")
	menu.close()
	Lang.set_language("en")
	menu.open_page("classes")
	for id in ["marksman", "gunslinger"]:
		for pick: Button in menu.body.find_children("*", "Button", true, false):
			if pick.get_meta("gallery_class", "") == id:
				await click(pick)
				break
		check(CharacterProfile.selected() == id, "Clicking the gallery card selects " + id)
	await shot("gallery-en")
	Lang.set_language("de")
	await shot("gallery-de")
	check(root.get_visible_rect().encloses(menu.modal.get_global_rect()), "The translated class gallery fits the viewport")
	Lang.set_language("en")
	menu.close()
	CharacterProfile.add_xp(Classes.threshold(21), "test")
	CharacterProfile.choose_skill("gunslinger", 0, 0)
	CharacterProfile.choose_skill("gunslinger", 1, 0)
	CharacterProfile.choose_skill("gunslinger", 2, 0)
	CharacterProfile.choose_skill("gunslinger", 3, 0)
	await shot("main-en")
	menu.open_page("skills")
	check(menu.modal.visible and not game.hud._card.visible, "Main menu opens the dedicated talent dossier")
	await click(menu._talent_buttons["0:1"])
	check(CharacterProfile.data.classes.gunslinger.choices[0] == 1 and not menu.notice.visible, "An unlocked talent card equips the alternative immediately")
	await click(menu._talent_buttons["0:0"])
	await shot("skills-en")
	Lang.set_language("de")
	await shot("skills-de")
	menu.page = "progress"
	menu._render_page()
	await shot("progress-de")
	if "--class-visual" in OS.get_cmdline_user_args():
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
		await create_timer(0.4).timeout
		menu._set_page("skills")
		await shot("skills-720-de")
		check(root.get_visible_rect().encloses(menu.modal.get_global_rect()), "The dossier remains within the smaller 1280 by 720 window")
		menu._scroll.scroll_vertical = 10000
		await create_timer(0.3).timeout
		await click(menu._talent_buttons["5:1"])
		check(menu.notice.visible and CharacterProfile.data.classes.gunslinger.choices[5] == -1, "The final locked tier can be scrolled to and clicked at 720p")
		await shot("locked-720-de")
		menu.notice.hide()
		menu._set_page("classes")
		await shot("gallery-720-de")
		check(root.get_visible_rect().encloses(menu.modal.get_global_rect()), "The class gallery remains within the smaller window")
		menu.close()
		await shot("main-720-de")
	menu.close()
	Lang.set_language("en")
	game.hud.show_tab("multiplayer")
	check(not CharacterProfile.choose_skill("gunslinger", 0, 1), "Multiplayer menu rejects talent changes before connection")
	menu.open_page("skills")
	check(not menu.modal.visible, "Skill screen cannot be opened from multiplayer")
	game.hud._set_menu_compact(true)
	game._on_start(false)
	game.waves.set_process(false)
	game.weapons.set_process(false)
	game.player.set_physics_process(false)
	check(CharacterProfile.context == "match" and game.player.class_combat.has("quick_hands"), "Solo starts with the chosen passive build")
	var w: Weapons = game.weapons
	var p: Player = game.player
	w.cur().ammo = 1
	w.reload()
	check(is_equal_approx(w.cur().reloading, float(w.cur().def.reload) * 0.8), "Quick Hands changes the actual reload timer")
	w.cur().reloading = 0
	w.cur().ammo = w.cur().def.mag
	game.classes.set_process(false)
	p.global_position = Map.ground_pos(20,105)
	var before: int = CharacterProfile.data.classes.gunslinger.total_xp
	game.spawn_zombie("shambler", Vector2(20,115), 1)
	await physics_frame
	var z: Zombie = game.zombies_root.get_children().back()
	z.set_physics_process(false)
	z.agent.avoidance_enabled = false
	z.killer_peer = 1
	z.killer_weapon = "pistol"
	z.last_headshot = true
	z.damage(100000, Vector3.FORWARD)
	game.classes.headshot(1)
	check(CharacterProfile.data.classes.gunslinger.stats.kills == 1 and CharacterProfile.data.classes.gunslinger.stats.headshots == 1, "A real zombie death updates the local class profile")
	check(CharacterProfile.data.classes.gunslinger.total_xp >= before + 20, "A pistol headshot kill includes Bounty XP")
	check(p.effective_speed_mul() > p.speed_mul, "Sidestep affects real player movement after a kill")
	before = CharacterProfile.data.classes.gunslinger.total_xp
	game.classes.quest(1, "test_quest", 300)
	game.classes.quest(1, "test_quest", 300)
	check(CharacterProfile.data.classes.gunslinger.total_xp == before + 600, "A quest completion cannot grant XP twice in the same match")
	before = CharacterProfile.data.classes.gunslinger.total_xp
	game.classes.wave(1)
	game.classes.wave(1)
	check(CharacterProfile.data.classes.gunslinger.total_xp == before + 220, "A wave reward is applied once")
	check(not CharacterProfile.select_class("assassin") and not CharacterProfile.choose_skill("gunslinger", 0, 1), "Running matches keep the class and talent build frozen")
	await shot("hud-en")
	# Check magazine upgrades combine with weapon mods without accumulating on refresh.
	p.class_combat.configure({"id": "assault", "level": 30, "choices": [1,-1,-1,-1,-1,0]})
	w.refresh_class_magazines()
	var magazine: int = w.state.ak47.def.mag
	w.refresh_class_magazines()
	check(magazine == 55 and w.state.ak47.def.mag == magazine, "Class magazine bonuses do not compound when refreshed")
	w.equip_mod("ak47", Weapons.Mods.DEFS.extended.slot, "extended")
	check(w.state.ak47.def.mag > magazine, "Magazine mods and class talents combine")
	w.unlocked.ak47 = true
	w.set_weapon("ak47")
	w._tick_ammo(1)
	w.cur().ammo = 0
	w.cur().reserve = 100
	w.reload()
	w._tick_ammo(10)
	check(w.cur().ammo == w.cur().def.mag, "Reload fills the enlarged magazine")
	game.classes.finish()
	check(not CharacterProfile.dirty, "Finishing a match flushes the profile")
	# Exercise the real host gate without a second process.
	game.started = false
	game.over = false
	CharacterProfile.end_match()
	game.hud.show_overlay("REMZ", "", "Start game", "", "start")
	check(NetSession.host("Class host", 24773) == OK, "Host opens a class lobby")
	NetSession.start_game()
	check(NetSession.phase == "lobby" and not game.started, "Host cannot start with an unconfirmed class")
	check(NetSession.choose_class("assassin"), "Class can be changed before locking")
	check(NetSession.choose_class("marksman", true), "Explicit class confirmation is accepted")
	check(not NetSession.choose_class("assassin") and NetSession.class_roster[1].id == "marksman", "Class changes are rejected after locking")
	game.hud.show_tab("multiplayer")
	await shot("lobby-en")
	NetSession.start_game()
	check(game.started and CharacterProfile.active_class() == "marksman", "Locked class starts the co-op match")
	game.waves.set_process(false)
	game.stats.record_death(1)
	check(CharacterProfile.data.classes.marksman.stats.deaths == 1, "Host death updates the played class")
	print("CLASS_INTEGRATION_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

extends SceneTree
const Checkpoint = preload("res://scripts/expedition_checkpoint.gd")
var game: Node
var run_director: RunDirector
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began > 450000:
		print("GAMEPLAY_UX_AUDIT_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func frames(count := 3) -> void:
	for i in count: await process_frame

func refresh_prompt(planes: bool) -> void:
	if planes:
		game.progression.sample_time = 0
		game.progression._process(0)
	else: game._process(0)

func run() -> void:
	var planes := "--audit-planes" in OS.get_cmdline_user_args()
	var region := "planes" if planes else "forest"
	CharacterProfile.data = CharacterProfile.empty_profile("Usability audit")
	game = load("res://scenes/%s.tscn" % ("planes" if planes else "main")).instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if planes:
		while not game.ready_for_exploration or game.preparing_survival or game.boot != null: await process_frame
	else: game._on_start(false)
	paused = false
	run_director = game.expedition
	run_director.set_process(false)
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.day_night.set_process(false)
	game.weather.set_process(false)
	game.hud.hide_overlay()
	root.gui_release_focus()
	game.player.active = true
	await frames()

	# The fixture deliberately overlaps a new objective and a real existing NPC.
	# One genuine E press must execute the action shown, and no second action.
	game.player.global_position = game.progression.npcs.camp.global_position+Vector3(1.8, 0.15, 0)
	await physics_frame
	check(game.progression.nearest(game.player) == "camp", region+": the interaction fixture reaches the actual Vendor")
	var site: Dictionary = run_director.sites.filter(func(entry): return entry.kind == "record")[0]
	var original_at: Vector3 = site.at
	site.at = game.player.global_position
	check(run_director.can_interact_world() and run_director.nearest(game.player) == site.id, region+": the optional cache shares Vendor's interaction range")
	refresh_prompt(planes)
	check(game.hud.prompt_label.text == run_director.interaction_prompt(site.id), region+": the visible E action matches the selected objective")
	var cash: int = game.player.score
	key(KEY_E, true)
	await frames()
	check(site.done and game.player.score == cash+60, region+": an actual E press collects the displayed cache exactly once")
	check(not game.progression.is_open, region+": the same E press cannot also open Vendor behind the cache")
	key(KEY_E, false)
	await frames()
	site.at = original_at
	if game.progression.is_open: game.progression.close()
	game.player.active = true
	root.gui_release_focus()
	refresh_prompt(planes)
	key(KEY_E, true)
	await frames()
	key(KEY_E, false)
	check(game.progression.is_open, region+": a second deliberate E press opens Vendor after the cache is gone")
	if game.progression.is_open: game.progression.close()
	paused = false
	root.gui_release_focus()
	game.player.active = true

	# Legal player actions after a checkpoint must not make that old save corrupt.
	var person := run_director.person(game.player.peer_id)
	person.bandages = 8
	person.offers = ["medic"]
	check(run_director.transact(game.player.peer_id, "augment", ["medic"]) == "Augment selected." and person.bandages == 8, region+": selecting Medic at capacity keeps a valid eight-bandage inventory")
	run_director.checkpoints.override_path = "user://usability_%s.save" % region
	var saved_position: Vector3 = game.player.global_position
	game.player.velocity = Vector3.ZERO
	var saved: Dictionary = run_director.checkpoints.capture()
	check(run_director.checkpoints.save_run() == "Checkpoint saved.", region+": the quiet checkpoint is written successfully")
	if planes:
		game.progression.quest_action("welcome")
		check(game.progression.accepted.has("welcome"), region+": a real quest can be accepted after the checkpoint")
	else:
		game.progression.transact(game.player, "camp", "quest", "arrival")
		check(game.progression.data(game.player.peer_id).accepted.has("arrival"), region+": a real quest can be accepted after the checkpoint")
	game.brewing.add_flower(game.player.peer_id, "golden_yarrow")
	game.brewing.stock(game.player.peer_id).drinks.brew_meadow = 1
	game.progression.rare_market.data(game.player.peer_id).owned.hawk = true
	if planes:
		game.progression.collectibles[0].taken = true
		game.progression.collectibles[0].node.hide()
		game.nature.hide_harvested(0)
		game.shooting_range.picked.ammo = true
	game.player.global_position += Vector3(0, 0, 1)
	game.player.velocity = Vector3(4, 0, 3)
	var validation: String = run_director.checkpoints.validate(saved)
	check(validation.is_empty(), region+": earlier save remains valid after quests, supplies and relics are acquired: "+validation)
	var loaded: String = run_director.checkpoints.load_run()
	check(loaded == "Expedition continued.", region+": the earlier checkpoint loads after continued play: "+loaded)
	check(game.player.global_position.is_equal_approx(saved_position) and game.player.velocity == Vector3.ZERO, region+": loading restores position and cancels stale movement")
	check(not game.brewing.stock(game.player.peer_id).drinks.has("brew_meadow") and not game.brewing.stock(game.player.peer_id).flowers.has("golden_yarrow"), region+": loading rolls back later supplies consistently")
	check(not game.progression.rare_market.data(game.player.peer_id).owned.has("hawk"), region+": loading rolls back later relic ownership")
	if planes:
		check(not game.progression.accepted.has("welcome"), "Planes: loading rolls back later quest acceptance")
		check(not game.progression.collectibles[0].taken and game.progression.collectibles[0].node.visible and not game.nature._picked.has(0), "Planes: earlier save restores harvestable baskets and plants")
		check(not game.shooting_range.picked.has("ammo"), "Planes: earlier save restores uncollected shooting-range loot")
	else: check(not game.progression.data(game.player.peer_id).accepted.has("arrival"), "Forest: loading rolls back later quest acceptance")

	var moved: Dictionary = saved.duplicate(true)
	moved.roster = {2: str(CharacterProfile.data.name)}
	moved.players = {2: saved.players[game.player.peer_id].duplicate(true)}
	moved.progression["standard" if planes else "people"] = {2: {"accepted": {}, "accepted_wave": {}, "claimed": {}, "skins": {}, "discovered": false}}
	if planes: moved.progression.rare = {2: {"owned": {"hawk": true}, "active": "", "ammo": {"fire": 0, "frost": 0}, "mode": "", "phoenix_wave": -1}}
	else: moved.progression.rare_market.people = {2: {"owned": {"hawk": true}, "active": "", "ammo": {"fire": 0, "frost": 0}, "mode": "", "phoenix_wave": -1}}
	var remapped: Dictionary = run_director.checkpoints.remap_players(moved)
	check(remapped.progression["standard" if planes else "people"].has(game.player.peer_id), region+": rejoining remaps the shared trader record")
	check((remapped.progression.rare if planes else remapped.progression.rare_market.people).has(game.player.peer_id), region+": rejoining preserves the named player's rare inventory")

	# Pausing must not add survival time or consume a kill streak.
	game.stats.seconds = 123.0
	game.stats._streak_t = 3.0
	game.stats._streak = 4
	game._pause()
	game._process(5.0)
	check(game.stats.seconds == 123.0 and game.stats._streak_t == 3.0 and game.stats._streak == 4, region+": solo pause preserves elapsed survival time and the current kill streak")
	if planes: game.set_menu(false)
	else: game._on_start(false)
	game._process(0.5)
	check(game.stats.seconds >= 123.5 and game.stats._streak_t < 3.0, region+": gameplay statistics resume after closing pause")
	await _wave_menu_input(planes)
	if planes: await _building_menus()
	print("GAMEPLAY_UX_AUDIT_DONE region=%s checks=%d failures=%d" % [region, checks, failures])
	quit(1 if failures else 0)

func _wave_menu_input(planes: bool) -> void:
	game.waves.phase = "idle"
	game.waves.timer = 60.0
	game.waves.set_process(true)
	game._pause()
	game.hud.overlay_button.grab_focus()
	key(KEY_ENTER, true)
	await frames()
	key(KEY_ENTER, false)
	await frames()
	check(game.player.active and not paused and not game.hud.overlay.visible, "Enter on Continue resumes actual gameplay")
	check(game.waves.phase == "idle" and game.waves.timer > 50.0, "Confirming Continue with Enter does not also start the next wave")
	if game.hud.overlay.visible:
		if planes: game.set_menu(false)
		else: game._on_start(false)
	game.waves.set_process(false)
	game.waves.timer = 60.0
	key(KEY_ENTER, true)
	check(game.waves.timer <= (0.1 if planes else 1.0), "A deliberate gameplay Enter starts the next wave, including wave one")
	key(KEY_ENTER, false)
	await frames()
	game.waves.timer = 60.0

func _building_menus() -> void:
	var construction: Node = game.field_building
	game.player.active = false
	construction.cancel()
	check(not game.player.active, "Planes: cancelling an inactive building tool never reactivates the player")
	game.player.active = true
	game.inventory.open()
	key(KEY_B, true)
	await frames()
	key(KEY_B, false)
	check(game.inventory.is_open and not construction.kit_menu.visible and paused, "Planes: B cannot open a second menu behind inventory")
	game.inventory.close()
	game.set_menu(true)
	key(KEY_B, true)
	await frames()
	key(KEY_B, false)
	check(game.hud.overlay.visible and not construction.kit_menu.visible and not game.player.active, "Planes: B cannot open kits from the pause screen")
	game.set_menu(false)
	game.progression.kit_stock.palisade = 1
	key(KEY_B, true)
	await frames()
	key(KEY_B, false)
	check(construction.kit_menu.visible and not game.player.active and paused, "Planes: B opens the kit menu and safely pauses solo combat")
	var old_process: Array = [run_director.is_processing(), game.weather.is_processing(), game.day_night.is_processing(), game.waves.is_processing()]
	for system in [run_director, game.weather, game.day_night, game.waves]: system.set_process(true)
	game.player.class_combat.buff("exp_focus", 6.0)
	var clocks: Array = [run_director.elapsed, game.weather.elapsed, game.day_night.clock_seconds, game.waves.timer, game.cornfield.fires.clock, game.player.class_combat.timers.exp_focus]
	await create_timer(0.2, true).timeout
	check(clocks == [run_director.elapsed, game.weather.elapsed, game.day_night.clock_seconds, game.waves.timer, game.cornfield.fires.clock, game.player.class_combat.timers.exp_focus], "Planes: solo kit pause freezes mission, weather, sun, wave, crop-fire and class-buff timers")
	var systems: Array = [run_director, game.weather, game.day_night, game.waves]
	for i in systems.size(): systems[i].set_process(old_process[i])
	key(KEY_ESCAPE, true)
	await frames()
	key(KEY_ESCAPE, false)
	check(not construction.kit_menu.visible and game.player.active and not paused and not game.hud.overlay.visible, "Planes: Escape closes kits and restores gameplay without opening another menu")
	key(KEY_B, true)
	await frames()
	key(KEY_B, false)
	game.waves.set_process(true)
	key(KEY_ENTER, true)
	await frames()
	key(KEY_ENTER, false)
	check(construction.placing and not construction.kit_menu.visible and game.player.active and not paused, "Planes: Enter activates the focused kit and resumes placement")
	check(game.waves.phase == "idle" and game.waves.timer > 50.0, "Planes: confirming a kit with Enter does not start the next wave")
	game.waves.set_process(false)
	check(game.progression.kit_stock.palisade == 1, "Planes: selecting a kit does not consume it before placement")
	key(KEY_ESCAPE, true)
	await frames()
	key(KEY_ESCAPE, false)
	check(not construction.placing and not construction.ghost.visible and game.player.active and not game.hud.overlay.visible, "Planes: cancelling placement restores control and hides the preview")
	game.player.global_position = run_director.camp()+Vector3(25, 0, 0)
	var saved_items: Dictionary = run_director.structures.items.duplicate(true)
	for i in 40: run_director.structures.items[i+100] = {}
	check(construction.placement_error(game.player.global_position+Vector3(5,0,0), 0) == "Fortification limit reached.", "Planes: legacy kits share the forty-fortification limit with expedition structures")
	run_director.structures.items = saved_items

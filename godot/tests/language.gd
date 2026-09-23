# Language: English by default, German from locale/de.po, live switching through the settings, portable
# co-op text, and a sweep over every menu that fails on untranslated text (German run) or on German left
# in the English game (English run). Run both:
# Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=language --smoke-test --no-intro --no-music --no-foliage
# Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=language --smoke-test --no-intro --no-music --no-foliage --lang=de
extends SceneTree

# Words that are spelled the same in both languages or are names; a text made only of these (plus
# numbers and punctuation) needs no catalogue entry.
const SAME := ["R", "RemZ", "FPS", "ms", "HP", "LP", "Rem", "Dollars", "REM", "DOLLARS", "Vendor", "Mechanic", "Secret",
	"Mara", "MP5", "AK", "MG", "MAC", "SD", "Minigun", "M134", "Desert", "Eagle", "Revolver", "Host", "Hamachi", "LAN",
	"UDP", "IP", "IPv4", "Ping", "PING", "WASD", "Shift", "Enter", "Esc", "Tab", "TAB", "ADS", "NPC", "Koop", "KONM",
	"Games", "Remetschwil", "Oberrohrdorf", "Sennhof", "Sennhofstrasse", "Heitersberg", "Sorchen", "Oberer", "English",
	"Deutsch", "VSync", "Normal", "Mods", "Skins", "Training", "Briefing", "OK", "Level", "Titan", "Titans", "Phantom",
	"Talisman", "Parasol", "Zombies", "Zombie", "KILLS", "HEADSHOTS", "DEATHS", "ASSISTS", "TITAN", "LEADERBOARD",
	"Leaderboard", "Marksman", "Autorefill", "XL", "Cheat", "Tesla", "Mortar", "Sentinel"]
# German that must never show up in the English game.
const GERMAN_WORDS := ["und", "nicht", "mit", "für", "Welle", "Wellen", "Hütte", "Spieler", "Aufträge", "Auftrag",
	"Munition", "Schaden", "kaufen", "Gekauft", "Verkaufen", "bauen", "Turm", "Türme", "Barrikade", "Leben", "Granaten",
	"Waffe", "Waffen", "noch", "jetzt", "wird", "sind", "zurück", "Zurück", "Einstellungen", "Schwierigkeit",
	"Steuerung", "Bestenliste", "Erfolge", "Händler", "Belohnung", "Stufe", "Runde", "Schlüssel", "Pilz", "Nachladen",
	"Reichweite", "Vorrat", "Vorräte", "Lagerfeuer", "Rückstoss", "Streuung", "Spiel", "starten", "Taste"]

var failures := 0
var checks := 0
var game: Node
var german := false
var _reported := {}
var _word := RegEx.new()
var _slot := RegEx.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	_word.compile("[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß'-]*")
	_slot.compile("%(?:%|[-+0#]*\\d*(?:\\.\\d+)?[scdoxXfv])")
	german = Lang.current == "de"
	var wanted := "de" if "--lang=de" in OS.get_cmdline_user_args() else "en"
	check(Lang.current == wanted and TranslationServer.get_locale() == wanted, "Starts in %s whatever the Windows locale (%s)" % [wanted, OS.get_locale()])
	_basics()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready:
		await process_frame
	await _settings_switch()
	await _sweep_menus()
	print("LANGUAGE_DONE lang=%s checks=%d failures=%d" % [Lang.current, checks, failures])
	quit(1 if failures else 0)

# ---------------------------------------------------------------- the machinery itself
func _basics() -> void:
	var catalogue = Lang._catalogues.get("de")
	var count: int = catalogue.po.get_message_count() if catalogue and catalogue.po else 0
	check(count > 800, "German catalogue is loaded (%d messages)" % count)
	check(Lang.resolve("Start game", "de") == "Spiel starten" and Lang.resolve("Start game", "en") == "Start game", "Plain msgid resolves per language")
	var wave := Lang.t("Wave %d", [3])
	check(Lang.resolve(wave, "de") == "Welle 3" and Lang.resolve(wave, "en") == "Wave 3", "Formatted segment resolves per language")
	var breach := Lang.t("Barricade %s breached!", ["Meadow Gate"])
	check(Lang.resolve(breach, "de") == "Barrikade Wiesentor durchbrochen!", "String arguments are translated on the receiving side: " + Lang.resolve(breach, "de"))
	var nested := Lang.t("%s · %s", [Lang.t("Wave %d", [2]), "Ready"])
	check(Lang.resolve(nested, "de") == "Welle 2 · Bereit", "Nested segments and msgid arguments resolve")
	var glued := "[b]" + Lang.t("Wave %d", [4]) + "[/b]  " + Lang.t("Ready")
	check(Lang.resolve(glued, "de") == "[b]Welle 4[/b]  Bereit", "Segments embedded in BBCode and concatenations resolve")
	check(Lang.resolve(Lang.t("%s%s  ·  %s", [Lang.raw("Ready"), "", "Ready"]), "de") == "Ready  ·  Bereit", "Lang.raw keeps a player name untouched")
	check(Lang.resolve(Lang.t("Wave %d", [1, 2]), "en") == "Wave %d", "A wrong argument count falls back instead of breaking the frame")
	check(Lang.resolve("Some text nobody translated", "de") == "Some text nobody translated", "Unknown text stays as it is")
	var before := Lang.current
	Lang.set_language("de")
	check(TranslationServer.translate(wave) == "Welle 3" and TranslationServer.translate("Start game") == "Spiel starten", "TranslationServer (what labels use) follows the language")
	Lang.set_language("en")
	check(TranslationServer.translate(wave) == "Wave 3" and TranslationServer.translate("Start game") == "Start game", "Switching back restores English")
	Lang.set_language(before)

# The language control in the settings tab switches live and the menu follows without a rebuild.
func _settings_switch() -> void:
	var picker: OptionButton = null
	for node in game.hud.settings_box.find_children("*", "OptionButton", true, false):
		if node.item_count == Lang.LANGUAGES.size() and node.get_item_text(0) == "English":
			picker = node
	check(picker != null, "Settings offer a language choice")
	if picker == null: return
	check(picker.get_item_text(1) == "Deutsch" and picker.selected == Lang.language_codes().find(Lang.current), "Language names are native and the current one is selected")
	var other := 1 - picker.selected
	var start_button: Button = game.hud.overlay_button
	picker.select(other)
	picker.item_selected.emit(other)
	await process_frame
	var code: String = Lang.language_codes()[other]
	check(Lang.current == code and TranslationServer.get_locale() == code, "Choosing %s switches the language" % Lang.LANGUAGES[code])
	check(TranslationServer.translate(start_button.text) == ("Spiel starten" if code == "de" else "Start game"), "Start button follows the switch live")
	check(game.settings._save_timer.is_stopped(), "Test runs never write the player's settings file")
	picker.select(1 - other)
	picker.item_selected.emit(1 - other)
	await process_frame
	check(Lang.current == ("de" if german else "en"), "Switching back restores the test language")

# ---------------------------------------------------------------- sweep
func _sweep_menus() -> void:
	var hud: Hud = game.hud
	for id in ["briefing", "multiplayer", "difficulty", "controls", "settings", "records", "achievements"]:
		hud.show_tab(id)
		await _frames(2)
		await _sweep("start menu / " + id, hud.overlay)
	game._on_start()
	game.waves.set_process(false)
	await _frames(20)
	await _sweep("HUD", hud)
	await _sweep("quest tracker", game.progression)
	# every sign, name tag and price tag in the world, near or far
	var world_labels: Array = []
	for label: Label3D in game.find_children("*", "Label3D", true, false):
		if not label.text.is_empty(): world_labels.append(label.text)
	_sweep_texts("world labels", world_labels)
	var inventory = game.inventory
	inventory.open()
	await _frames(3)
	await _sweep("inventory", inventory)
	inventory.close()
	# away from Mechanic the skill key only explains where training is (the training rows are swept below)
	game.skills.open()
	await _frames(3)
	check(Lang.text(game.hud.msg_label.text) == Lang.resolve("Mechanic, north of the campfire, offers training.", Lang.current), "Skill key away from Mechanic explains where training is")
	await _sweep("HUD message", game.hud)
	game.skills.close()
	await _frames(2)
	var shop: Progression = game.progression
	game.player.score = 20000
	# the Mist Peddler only roams from wave five on
	game.waves.wave = 5
	game.waves.completed = 4
	for i in 8: shop.rare_market._physics_process(0.1)
	for npc in Progression.NPCS:
		game.player.global_position = shop.npcs[npc].global_position + Vector3(0, 0.1, 2.3)
		await physics_frame
		await physics_frame
		shop.interact(npc)
		await _frames(2)
		if not shop.is_open:
			check(false, "Dialogue with %s opens" % npc)
			continue
		for page in shop._tabs.keys():
			shop.page = page
			shop._render()
			await _frames(2)
			await _sweep("%s / %s" % [npc, page], shop)
		shop.close()
		await _frames(2)
	game.barricade_menu.open()
	await _frames(3)
	await _sweep("barricade planner", game.barricade_menu)
	game.barricade_menu.close()
	await _frames(2)
	game.cheat_menu.open()
	await _frames(3)
	await _sweep("cheat menu", game.cheat_menu)
	game.cheat_menu.close()
	await _frames(2)
	game.leaderboard.panel.show()
	await _frames(3)
	await _sweep("leaderboard", game.leaderboard)
	game.leaderboard.panel.hide()
	game._pause()
	for id in ["briefing", "difficulty", "controls", "settings", "achievements"]:
		hud.show_tab(id)
		await _frames(2)
		await _sweep("pause / " + id, hud.overlay)
	game._on_start()
	await _frames(4)
	game.waves.completed = 3
	game.player.damage(100000.0)
	await _frames(6)
	await _sweep("game over / summary", hud.overlay)
	hud.show_tab("records")
	await _frames(2)
	await _sweep("game over / high scores", hud.overlay)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _sweep(screen: String, from: Node) -> void:
	var texts: Array = []
	_collect(from, texts)
	_sweep_texts(screen, texts)
	# windowed run with --render-language: every swept screen as artifacts/language/<lang>/<screen>.png
	if "--render-language" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://").path_join("../artifacts/language/" + Lang.current)
		DirAccess.make_dir_recursive_absolute(folder)
		var file := screen.replace(" / ", "-").replace(" ", "_") + ".png"
		root.get_texture().get_image().save_png(folder.path_join(file))

func _sweep_texts(screen: String, texts: Array) -> void:
	var bad := 0
	for entry in texts:
		var problem := _problem(str(entry))
		if problem.is_empty() or _reported.has(problem): continue
		_reported[problem] = true
		bad += 1
		print("  ", screen, ": ", problem)
	check(bad == 0, "%s: %d texts, %s" % [screen, texts.size(), "all translated" if german else "no German left"] if bad == 0 else "%s: %d problem(s) above" % [screen, bad])

func _collect(node: Node, out: Array) -> void:
	if node is CanvasItem and not node.is_visible_in_tree(): return
	if node is Node3D and not node.is_visible_in_tree(): return
	if node is Label or node is Button or node is Label3D or node is RichTextLabel:
		if not node.text.is_empty(): out.append(node.text)
	if node is OptionButton:
		for i in node.item_count: out.append(node.get_item_text(i))
	if node is Control and not node.tooltip_text.is_empty(): out.append(node.tooltip_text)
	if node is LineEdit and not node.placeholder_text.is_empty(): out.append(node.placeholder_text)
	for child in node.get_children():
		_collect(child, out)

# Empty when fine, otherwise a short description of what is wrong with one displayed text.
func _problem(value: String) -> String:
	var shown := Lang.text(value)
	if shown.contains(Lang.OPEN) or shown.contains(Lang.CLOSE) or shown.contains(Lang.SEP):
		return "broken segment: " + shown.c_escape()
	if german:
		for piece in _pieces(value):
			if not _needs_entry(piece): continue
			if String(Lang._catalogues["de"].po.get_message(piece)).is_empty():
				return "no German for %s  (shown: %s)" % [piece.c_escape(), shown.c_escape()]
		return ""
	for word in _word.search_all(shown):
		var w := word.get_string()
		if w in GERMAN_WORDS or RegEx.create_from_string("[äöüÄÖÜß]").search(w):
			return "German in the English game: %s" % shown.c_escape()
	return ""

# The translatable parts of a label text: plain text outside segments, each segment's msgid and its
# string arguments (recursively). Lang.raw arguments are names and are skipped.
func _pieces(value: String) -> Array:
	var out: Array = []
	var at := 0
	while true:
		var start := value.find(Lang.OPEN, at)
		var stop := value.find(Lang.CLOSE, start + 1) if start >= 0 else -1
		if start < 0 or stop < 0:
			out.append(value.substr(at))
			break
		out.append(value.substr(at, start - at))
		var body := value.substr(start + 1, stop - start - 1)
		var cut := body.find(Lang.SEP)
		out.append(body if cut < 0 else body.substr(0, cut))
		if cut >= 0:
			var args = bytes_to_var(Marshalls.base64_to_raw(body.substr(cut + 1)))
			if args is Array:
				for arg in args:
					if arg is String: out.append_array(_pieces(arg))
		at = stop + 1
	return out

func _needs_entry(piece: String) -> bool:
	var bare := _slot.sub(piece, " ", true)
	# BBCode tags are markup, not words
	bare = RegEx.create_from_string("\\[/?[a-z_]+(=[^\\]]*)?\\]").sub(bare, " ", true)
	for word in _word.search_all(bare):
		var w := word.get_string()
		if w.length() > 1 and not w in SAME:
			return true
	return false

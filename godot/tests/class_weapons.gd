extends SceneTree

# Structural guard for the class weapons of 30 Sep 2026 (SIG P226, Nighthawk .45, AR-15, Tommy gun, SPAS-12,
# sawed-off) and the four models the user's Meshy web exports replaced (pistol, MP5, Desert Eagle, knife).
# Same idea as new_weapons.gd: every table a weapon has to appear in actually carries it, the class it
# belongs to lists it, the recording plays, the model and the mount data exist, and it fires.
#
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=class_weapons --smoke-test --no-intro --no-music --no-foliage
#   ... --render-weapons (windowed): artifacts/class-weapons/<id>-{hip,ads,shot}.png for the new ones and the
#   replaced ones, to judge grips, sight line and muzzle by eye.
const Classes = preload("res://scripts/character_classes.gd")
const NEW := ["sig_p226", "nighthawk", "ar15", "tommy_gun", "spas12", "sawed_off"]
const REPLACED := ["pistol", "smg", "deagle", "knife"]
const CLASS_OF := {"sig_p226": "gunslinger", "nighthawk": "gunslinger", "ar15": "assault", "tommy_gun": "assault",
	"spas12": "breacher", "sawed_off": "breacher"}
# The recordings baked by tools/build_class_weapon_audio.py: weapon id -> Sfx name -> weapons/<file>.wav
const RECORDINGS := {"sig_p226": "sig_p226", "nighthawk": "nighthawk", "ar15": "ar15", "tommy_gun": "tommy_gun",
	"spas12": "spas12", "sawed_off": "sawed_off", "smg": "mp5", "titanbreaker": "titanbreaker"}
const REQUIRED := ["name", "model", "height", "mag", "reserve", "damage", "rate", "reload", "pellets",
	"spread", "range", "auto", "sfx", "pos", "ads", "kick_pitch", "kick_yaw", "kick_back", "recover"]

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)
		push_error("FAIL: " + label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var w: Weapons = game.weapons
	var p: Player = game.player
	p.set_physics_process(false)
	w.set_process(false)

	# --- catalogue -------------------------------------------------------------------------
	for id in NEW:
		check(Weapons.DEFS.has(id), id + " steht in Weapons.DEFS")
		if not Weapons.DEFS.has(id): continue
		var d: Dictionary = Weapons.DEFS[id]
		var missing := PackedStringArray()
		for field in REQUIRED:
			if not d.has(field): missing.append(field)
		check(missing.is_empty(), id + " hat alle Pflichtfelder" + ("" if missing.is_empty() else ": fehlt " + ", ".join(missing)))
		check(id in Weapons.ORDER, id + " steht in Weapons.ORDER")
		check(str(d.model) == id, id + ": Modellname = Waffen-id (haelt GRIPS/PROFILES und MountData/MAGAZINE zusammen)")
		check(Progression.GOODS.has(id), id + " ist beim Haendler kaufbar")
		if Progression.GOODS.has(id):
			var goods: Dictionary = Progression.GOODS[id]
			check(goods.has("quest") and goods.has("wave") and goods.has("price") and goods.has("ammo") and goods.has("desc"), id + ": GOODS-Eintrag vollstaendig")
			check(Progression.QUESTS.has(str(goods.quest)), id + ": Quest '%s' existiert" % goods.quest)
			check(str(goods.get("npc", "")) in ["camp", "secret"], id + ": Verkaeufer ist Vendor oder Secret Vendor")
			# ammo pays for two magazines: 13-33 R per 1000 damage like the rest of the catalogue
			var per_thousand := float(goods.ammo) / maxf(1.0, float(d.mag) * 2.0 * float(d.damage) * float(d.pellets)) * 1000.0
			check(per_thousand >= 12.0 and per_thousand <= 34.0, id + ": Munitionskosten %.1f R je 1000 Schaden liegen im Korridor" % per_thousand)
		check(int(d.get("mag", 0)) >= 1 and float(d.get("reload", 0.0)) > 0.0 and float(d.get("rate", 0.0)) > 0.0, id + ": Magazin, Nachladen und Feuerrate gesetzt")
		check(w.reserve_limit(id) >= int(d.mag) * 2, id + ": Reservelimit fasst zwei Magazine (%d)" % w.reserve_limit(id))
		# Every gun but shotguns and pistols fires full auto (the user's rule of 30 Sep 2026).
		var pistol_or_shotgun: bool = id in ViewmodelHands.HANDGUNS or int(d.pellets) > 1
		check(bool(d.auto) == (not pistol_or_shotgun), id + ": %s" % ("halbautomatisch (Pistole/Flinte)" if pistol_or_shotgun else "vollautomatisch"))
		# class membership: every new weapon is a specialist weapon of exactly one class
		var owners := []
		for cls in Classes.CLASSES:
			if id in Classes.CLASSES[cls].weapons: owners.append(cls)
		check(owners == [CLASS_OF[id]], id + ": Spezialwaffe der Klasse %s (gefunden: %s)" % [CLASS_OF[id], owners])

	# --- assets ----------------------------------------------------------------------------
	for id in NEW + REPLACED:
		var model := str(Weapons.DEFS[id].model)
		check(ResourceLoader.exists("res://assets/models/%s.glb" % model), id + ": Modell %s.glb vorhanden" % model)
		if Weapons.is_melee(id): continue
		check(WeaponMountData.WEAPONS.has(model), id + ": Muendung/Magazin von %s ist vermessen (weapon_geometry.mjs --bake)" % model)
		check(WeaponEffects.PROFILES.has(id), id + ": eigenes Muendungsfeuer-Profil")
		check(ViewmodelHands.GRIPS.has(id), id + ": eigene Handpositionen")
		check(WeaponAttachments.MAGAZINE.has(model), id + ": Magazinart fuer die Mods bekannt")
		check(Sfx.FILES.has(str(Weapons.DEFS[id].sfx)), id + ": Schusssound '%s' registriert" % Weapons.DEFS[id].sfx)
		check(ResourceLoader.exists("res://assets/ui/items/%s.png" % id), id + ": Inventar-Icon vorhanden")
	check(ResourceLoader.exists("res://assets/ui/items/knife.svg") or ResourceLoader.exists("res://assets/ui/items/knife.png"), "knife: Inventar-Icon vorhanden (die Nahkampfwaffen tragen SVGs)")
	# the replaced models really are the new web exports: the pipeline writes a state.json receipt
	for id in ["pistol", "smg", "deagle", "knife_real"]:
		var receipt := "res://../assets/raw/%s_web/state.json" % id
		check(FileAccess.file_exists(receipt), id + ": Pipeline-Beleg assets/raw/%s_web/state.json" % id)
	# the sounds: the user's recordings, imported as 44.1 kHz WAVs with their tails
	for id in RECORDINGS:
		var sound: String = str(Weapons.DEFS[id].sfx)
		var stream := Sfx.get_stream(sound) as AudioStreamWAV
		check(stream != null and stream.resource_path == "res://assets/audio/sfx/weapons/%s.wav" % RECORDINGS[id], id + " laedt seine Aufnahme weapons/%s.wav" % RECORDINGS[id])
		if stream: check(stream.mix_rate == 44100 and stream.get_length() > 0.25, id + ": Aufnahme mit Ausklang (%.2f s)" % stream.get_length())
	check(not Weapons.DEFS.titanbreaker.has("sfx_pitch"), "Titanbreaker spielt seine Aufnahme ohne den alten Revolver-Pitch")
	check(Sfx.FILES.smg == ["weapons/mp5"], "Die MP5 spielt die neue Aufnahme (ein Schuss aus der Salve)")

	# --- how it looks in the hands ----------------------------------------------------------
	if "--render-weapons" in OS.get_cmdline_user_args():
		game.achievements.hide()
		game.day_night.set_time_hours(11.0)
		p.active = true
		p.global_position = Map.ground_pos(6, -10) + Vector3.UP * 0.2
		var folder := ProjectSettings.globalize_path("res://../artifacts/class-weapons/")
		DirAccess.make_dir_recursive_absolute(folder)
		for id in NEW + REPLACED:
			w.unlock(id)
			w.set_weapon(id)
			for aimed in [false, true]:
				if aimed: Input.action_press("aim")
				else: Input.action_release("aim")
				for i in 40: w._process(1.0 / 60.0)
				for i in 4: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder + id + ("-ads.png" if aimed else "-hip.png"))
			Input.action_release("aim")
			if Weapons.is_melee(id): continue
			w.cur().cooldown = 0.0
			w.try_fire()
			for i in 2: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder + id + "-shot.png")
		print("RENDERED class weapons -> artifacts/class-weapons/")

	# --- the weapon actually fires ----------------------------------------------------------
	p.active = true
	p.global_position = Map.ground_pos(6, -10) + Vector3.UP * 0.2
	for id in NEW + ["pistol", "smg", "deagle"]:
		w.unlock(id)
		w.set_weapon(id)
		check(w.current == id, id + ": laesst sich ausruesten")
		w._switch_t = 0.0   # the 0.25 s draw delay of the class system would swallow the test shot
		var s := w.cur()
		s.ammo = int(s.def.mag)
		s.cooldown = 0.0
		s.reloading = 0.0
		var before: int = s.ammo
		w.try_fire()
		check(int(s.ammo) < before, id + ": Schuss verbraucht Munition")
		var muzzle := w.muzzle_transform().origin
		check(muzzle.z < -0.1 and absf(muzzle.x) < 0.6 and absf(muzzle.y) < 0.6, id + ": Muendung sitzt vorn an der Waffe (%.2f, %.2f, %.2f)" % [muzzle.x, muzzle.y, muzzle.z])
		var holder: Node3D = w.cur()["node"]
		var bounds: AABB = w.cur()["bounds"]
		var local_tip: Vector3 = holder.transform.affine_inverse() * muzzle
		var sideways := absf(local_tip.x - bounds.get_center().x)
		check(sideways < bounds.size.x * 0.5 + 0.005, id + ": Muendung liegt in der Waffensilhouette (%.3f m seitlich, halbe Breite %.3f)" % [sideways, bounds.size.x * 0.5])
		# the measured bore sits at the front face of the weapon, never behind a light or a sight
		check(local_tip.z < bounds.position.z + 0.02, id + ": Muendung liegt an der Vorderkante (%.3f vs %.3f)" % [local_tip.z, bounds.position.z])
		var voices: Array = Sfx._voices.get(str(s.def.sfx), [])
		check(not voices.is_empty() and voices.back().playing, id + ": der Schuss spielt seine Aufnahme")
		w.cur().cooldown = 0.0
		w.cur().reloading = 0.0
	# the knife swings with its new model
	w.set_weapon("knife")
	check(w.current == "knife" and w.cur().node.find_children("*", "MeshInstance3D", true, false).size() > 0, "knife: das neue Messer haengt im Blickmodell")
	var knife_bounds: AABB = w.cur()["bounds"]
	check(knife_bounds.size.y > 0.3 and knife_bounds.size.y < 0.45 and knife_bounds.size.x < 0.08, "knife: 37 cm lang, Klinge entlang der Hochachse (%.2f x %.2f x %.2f)" % [knife_bounds.size.x, knife_bounds.size.y, knife_bounds.size.z])

	# --- buying one ------------------------------------------------------------------------
	var shop: Progression = game.progression
	var data := shop.data(p.peer_id)
	for id in Progression.QUESTS: data.claimed[id] = true
	game.waves.completed = 20
	for id in NEW:
		var spec: Dictionary = Progression.GOODS[id]
		w.unlocked[id] = false
		p.global_position = shop.npcs[str(spec.npc)].global_position + Vector3(0, 0, 1)
		p.score = int(spec.price) + 500
		var reply := shop.transact(p, str(spec.npc), "weapon", id)
		check(w.unlocked.get(id, false), id + ": Kauf beim %s schaltet die Waffe frei (%s)" % [spec.npc, reply])
		check(p.score == 500, id + ": der Kauf kostet genau %d R" % int(spec.price))
		check(int(w.state[id].reserve) <= w.reserve_limit(id), id + ": das Startmagazin sprengt das Reservelimit nicht")

	# --- mods: only what makes sense ---------------------------------------------------------
	for id in NEW:
		for mod_id in Weapons.Mods.DEFS:
			if not Weapons.Mods.compatible(mod_id, id, Weapons.DEFS[id]): continue
			var spec: Dictionary = Weapons.Mods.DEFS[mod_id]
			var ok := true
			for key in spec.get("mul", {}):
				if not Weapons.DEFS[id].has(key): ok = false
			check(ok, "%s + %s: Mod veraendert nur vorhandene Felder" % [id, mod_id])
			var definition := Weapons.Mods.definition(Weapons.DEFS[id], {str(spec.slot): mod_id})
			check(int(definition.mag) >= 1, "%s + %s: Magazin bleibt >= 1" % [id, mod_id])
	check(not Weapons.Mods.compatible("extended", "sawed_off", Weapons.DEFS.sawed_off), "sawed_off: kein erweitertes Magazin an der Kipplaufflinte")
	check(Weapons.Mods.compatible("suppressor", "sig_p226", Weapons.DEFS.sig_p226) and Weapons.Mods.compatible("suppressor", "ar15", Weapons.DEFS.ar15), "Schalldaempfer passt auf SIG und AR-15")

	# --- the class bonus reaches the new weapons ---------------------------------------------
	for id in NEW:
		var cls: String = CLASS_OF[id]
		var build := Classes.loadout(cls, Classes.threshold(10), [0, 0, -1, -1, -1, -1])
		p.class_combat.configure(build)
		check(p.class_combat.specialist(id), "%s zaehlt als Spezialwaffe des %s" % [id, cls])
		check(p.class_combat.mastery_multiplier(id) > 1.0, "%s bekommt den Meisterschaftsbonus des %s (x%.2f)" % [id, cls, p.class_combat.mastery_multiplier(id)])
		var other: String = "marksman" if cls != "marksman" else "gunslinger"
		p.class_combat.configure(Classes.loadout(other, Classes.threshold(10), [0, 0, -1, -1, -1, -1]))
		check(not p.class_combat.specialist(id), "%s ist keine Spezialwaffe des %s" % [id, other])

	print("CLASS_WEAPONS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

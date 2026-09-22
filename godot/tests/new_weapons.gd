extends SceneTree

# Structural guard for the eight-weapon expansion (2 pistols, 2 SMGs, 2 snipers, 2 heavies).
# It does not judge whether a weapon is fun - it proves that every table a weapon has to appear in
# actually carries it, because almost every omission in this codebase fails silently: an id missing
# from Weapons.ORDER still shoots but disappears from shop, inventory, quick bar and autorefill;
# a missing WeaponEffects profile quietly borrows the AK's muzzle flash; a missing Sfx entry plays a
# 0.1 s procedural click; a model missing from WeaponMountData drops the measured muzzle.
#
#   Godot.exe --path godot --script res://tests/run.gd -- --suite=new_weapons --smoke-test --no-intro --no-music
const NEW := ["deagle", "flare_pistol", "mac10", "cryo_smg", "plasma_sniper", "lever_rifle", "minigun", "graviton_cannon"]
# Every field weapons.gd indexes directly; a missing one crashes on the first shot.
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
		check(id in Weapons.ORDER, id + " steht in Weapons.ORDER (sonst unsichtbar in Shop, Inventar, Quickbar)")
		check(Progression.GOODS.has(id), id + " ist beim Händler kaufbar")
		if Progression.GOODS.has(id):
			var goods: Dictionary = Progression.GOODS[id]
			check(goods.has("quest") and goods.has("wave") and goods.has("price") and goods.has("ammo") and goods.has("desc"),
				id + ": GOODS-Eintrag vollständig (quest, wave, price, ammo, desc)")
			check(str(goods.get("npc", "")) in ["camp", "secret"], id + ": Verkäufer ist Vendor oder Secret Vendor")
			check(int(goods.get("price", 0)) > 0 and int(goods.get("ammo", 0)) > 0, id + ": Preis und Munitionspreis gesetzt")
		# mag 0 would make refill_quote divide by zero and the weapon unshootable (progression.gd)
		check(int(d.get("mag", 0)) >= 1, id + ": Magazin >= 1 (mag 0 zerstört die Munitionsrechnung)")
		check(float(d.get("reload", 0.0)) > 0.0, id + ": Nachladezeit > 0 (balance_report teilt sonst durch null)")
		check(float(d.get("rate", 0.0)) > 0.0, id + ": Feuerrate > 0")
		check(w.reserve_limit(id) >= int(d.mag), id + ": Reservelimit fasst mindestens ein Magazin")

	# --- assets ----------------------------------------------------------------------------
	for id in NEW:
		if not Weapons.DEFS.has(id): continue
		var model := str(Weapons.DEFS[id].model)
		check(ResourceLoader.exists("res://assets/models/%s.glb" % model), id + ": Modell %s.glb vorhanden" % model)
		check(WeaponMountData.WEAPONS.has(model), id + ": Mündung/Magazin von %s ist vermessen (weapon_geometry.mjs --bake)" % model)
		check(WeaponEffects.PROFILES.has(id), id + ": eigenes Mündungsfeuer-Profil (sonst AK-Blitz)")
		check(ViewmodelHands.GRIPS.has(id), id + ": eigene Handpositionen")
		check(Sfx.FILES.has(str(Weapons.DEFS[id].sfx)), id + ": Schusssound '%s' registriert" % Weapons.DEFS[id].sfx)
		check(ResourceLoader.exists("res://assets/ui/items/%s.png" % id) or ResourceLoader.exists("res://assets/ui/items/%s.svg" % id),
			id + ": Inventar-Icon vorhanden")

	# --- how it looks in the hands ----------------------------------------------------------
	# Windowed run with --render-weapons: one hip shot and one aimed shot per weapon, so the grips,
	# the sight line and the muzzle can be judged by eye instead of by number.
	if "--render-weapons" in OS.get_cmdline_user_args():
		game.achievements.hide()
		game.day_night.set_time_hours(11.0)
		p.active = true
		p.global_position = Map.ground_pos(6, -10) + Vector3.UP * 0.2
		var folder := ProjectSettings.globalize_path("res://../artifacts/new-weapons/")
		DirAccess.make_dir_recursive_absolute(folder)
		for id in NEW:
			if not Weapons.DEFS.has(id): continue
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
			# And one with the muzzle lit, to see where flash and smoke actually leave the weapon.
			w.cur().cooldown = 0.0
			w.try_fire()
			for i in 2: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder + id + "-shot.png")
		print("RENDERED new weapons -> artifacts/new-weapons/")

	# --- the weapon actually fires ----------------------------------------------------------
	p.active = true
	p.global_position = Map.ground_pos(6, -10) + Vector3.UP * 0.2
	for id in NEW:
		if not Weapons.DEFS.has(id): continue
		w.unlock(id)
		w.set_weapon(id)
		check(w.current == id, id + ": lässt sich ausrüsten")
		var s := w.cur()
		# The render pass above may have emptied a single shot weapon and left its cooldown running.
		s.ammo = int(s.def.mag)
		s.cooldown = 0.0
		s.reloading = 0.0
		s.erase("heat")
		s.erase("vent")
		var before: int = s.ammo
		w.try_fire()
		var fired: bool = int(s.ammo) < before
		check(fired, id + ": Schuss verbraucht Munition")
		# The muzzle must sit in front of the weapon, never inside the receiver or the scope.
		var muzzle := w.muzzle_transform().origin
		check(muzzle.z < -0.1 and absf(muzzle.x) < 0.6 and absf(muzzle.y) < 0.6, id + ": Mündung sitzt vorn an der Waffe (%.2f, %.2f, %.2f)" % [muzzle.x, muzzle.y, muzzle.z])
		# The measured bore has to sit inside the weapon's own silhouette, not beside it: a six
		# barrel cluster can pull the probe onto one of its barrels. muzzle_transform() is relative
		# to the camera, so the holder offset comes out first.
		var holder: Node3D = w.cur()["node"]
		var bounds: AABB = w.cur()["bounds"]
		var local_tip: Vector3 = holder.transform.affine_inverse() * muzzle
		var sideways := absf(local_tip.x - bounds.get_center().x)
		check(sideways < bounds.size.x * 0.5 + 0.005,
			id + ": Mündung liegt in der Waffensilhouette (%.3f m seitlich, halbe Breite %.3f)" % [sideways, bounds.size.x * 0.5])
		w.cur().cooldown = 0.0
		w.cur().reloading = 0.0

	# --- actually buying one -----------------------------------------------------------------
	# The whole chain the player walks through: level, quest, wave, price, unlock, starting ammo.
	var shop: Progression = game.progression
	var data := shop.data(p.peer_id)
	for id in Progression.QUESTS: data.claimed[id] = true
	game.waves.completed = 20
	for id in NEW:
		if not Progression.GOODS.has(id): continue
		var spec: Dictionary = Progression.GOODS[id]
		w.unlocked[id] = false
		p.global_position = shop.npcs[str(spec.npc)].global_position + Vector3(0, 0, 1)
		p.score = int(spec.price) - 1
		var poor := shop.transact(p, str(spec.npc), "weapon", id)
		check(not w.unlocked.get(id, false) and poor.to_lower().contains("rem dollars"), id + ": zu wenig Geld verhindert den Kauf")
		p.score = int(spec.price) + 500
		var reply := shop.transact(p, str(spec.npc), "weapon", id)
		check(w.unlocked.get(id, false), id + ": Kauf beim %s schaltet die Waffe frei (%s)" % [spec.npc, reply])
		check(p.score == 500, id + ": der Kauf kostet genau %d R" % int(spec.price))
		check(int(w.state[id].ammo) == int(w.state[id].def.mag) and int(w.state[id].reserve) >= int(Weapons.DEFS[id].mag) * 2,
			id + ": die Waffe kommt geladen mit zwei Reservemagazinen")
		check(int(w.state[id].reserve) <= w.reserve_limit(id), id + ": das Startmagazin sprengt das Reservelimit nicht")

	# --- mods: only what makes sense ---------------------------------------------------------
	for id in NEW:
		if not Weapons.DEFS.has(id): continue
		for mod_id in Weapons.Mods.DEFS:
			var allowed := Weapons.Mods.compatible(mod_id, id, Weapons.DEFS[id])
			if not allowed: continue
			var spec: Dictionary = Weapons.Mods.DEFS[mod_id]
			# A mod may only multiply fields the weapon actually has, or definition() crashes.
			var ok := true
			for key in spec.get("mul", {}):
				if not Weapons.DEFS[id].has(key): ok = false
			check(ok, "%s + %s: Mod verändert nur vorhandene Felder" % [id, mod_id])
			var definition := Weapons.Mods.definition(Weapons.DEFS[id], {str(spec.slot): mod_id})
			check(int(definition.mag) >= 1, "%s + %s: Magazin bleibt >= 1" % [id, mod_id])

	print("NEW_WEAPONS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

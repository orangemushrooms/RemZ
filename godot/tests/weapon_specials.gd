extends SceneTree

# The mechanics of the eight expansion weapons, headless: barrel heat and venting, the rotary
# spin-up, the freeze that builds up hit by hit, the flare and the graviton blast. Structure (does
# every table carry the weapon) is the job of tests/new_weapons.gd; this suite asks whether the
# mechanics actually behave, including the ways a player could cheat them.
#
#   Godot.exe --path godot --script res://tests/run.gd -- --suite=weapon_specials --smoke-test --no-intro --no-music

var game: Node
var targets: Array[Zombie] = []
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", description)
	else:
		failures += 1
		print("FAIL: ", description)
		push_error("FAIL: " + description)

func equip(w: Weapons, id: String) -> Dictionary:
	w.unlock(id)
	w.set_weapon(id)
	var s := w.cur()
	s.cooldown = 0.0
	s.reloading = 0.0
	s.ammo = int(s.def.mag)
	s.erase("heat")
	s.erase("vent")
	s.erase("spin")
	s.erase("spin_idle")
	return s

func fire_once(w: Weapons) -> void:
	w.cur().cooldown = 0.0
	# No _process runs in this suite, so the recoil from the previous shot would never settle and
	# later shots in a burst would sail over the target.
	w._aim_kick = Vector2.ZERO
	w.try_fire()

func spawn(kind: String, at: Vector3) -> Zombie:
	var z := Zombie.new()
	z.setup(kind, game.player, [], 1.0, Callable())
	z.model_path = ""
	game.zombies_root.add_child(z)
	z.set_physics_process(false)
	z.agent.avoidance_enabled = false
	z.global_position = at
	z.collision_layer = 2
	# A body without hit boxes is invisible to the shot ray (Zombie.from_hit).
	var area := Area3D.new()
	area.collision_layer = Zombie.HITBOX_LAYER
	area.collision_mask = 0
	area.set_meta("zombie", z)
	area.set_meta("headshot", false)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	area.add_child(shape)
	z.add_child(area)
	area.position = Vector3(0, Player.EYE, 0)
	z._hitboxes.append(area)
	targets.append(z)
	return z

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var p: Player = game.player
	var w: Weapons = game.weapons
	p.set_physics_process(false)
	w.set_process(false)
	p.active = true
	p.global_position = Vector3(0, 60, 0)
	p.rotation = Vector3.ZERO
	p.head.rotation = Vector3.ZERO
	p.camera.rotation = Vector3.ZERO
	check(w.specials != null, "Die Sondermechanik-Schicht haengt an der Szene")

	# ---------------------------------------------------------------- plasma: heat and venting
	var s := equip(w, "plasma_sniper")
	var shots := 0
	while shots < 20 and float(s.get("reloading", 0.0)) <= 0.0:
		fire_once(w)
		shots += 1
	check(shots <= int(s.def.mag) + 1, "Plasmabuechse ueberhitzt nach hoechstens einem Magazin (%d Schuss)" % shots)
	check(float(s.get("heat", 0.0)) >= 1.0 and bool(s.get("vent", false)), "Ueberhitzung setzt Hitze auf Anschlag und startet die Entlueftung")
	# Hand the weapon rounds back, otherwise "no shot falls" would be true simply because the
	# magazine is empty - the lock itself has to be what stops the shot.
	s.ammo = 3
	s.cooldown = 0.0
	fire_once(w)
	check(int(s.ammo) == 3, "Waehrend der Entlueftung faellt kein Schuss (Munition 3 -> %d)" % int(s.ammo))
	# The exploit the reviewers found: switching clears state.reloading, so the lock may not hang
	# on that value.
	w.set_weapon("pistol")
	w.set_weapon("plasma_sniper")
	s = w.cur()
	s.ammo = 3
	s.cooldown = 0.0
	check(float(s.reloading) <= 0.0, "Der Wechsel loescht die Nachladeanzeige - die Sperre haengt an der Hitze")
	fire_once(w)
	check(int(s.ammo) == 3, "Waffenwechsel bricht die Ueberhitzung nicht ab (Munition 3 -> %d)" % int(s.ammo))
	# Cooling: the barrel cools even while the weapon is stowed.
	w.set_weapon("pistol")
	for i in 400: w.specials.tick(w, 0.05)
	s = w.state["plasma_sniper"]
	check(float(s.get("heat", 1.0)) <= 0.05, "Verstaute Plasmabuechse kuehlt vollstaendig ab (Hitze %.2f)" % float(s.get("heat", 1.0)))
	check(int(s.ammo) > 0, "Die Zellen laden sich aus der Reserve nach (%d Zellen)" % int(s.ammo))
	w.set_weapon("plasma_sniper")
	s = w.cur()
	s.cooldown = 0.0
	s.reloading = 0.0
	fire_once(w)
	check(float(s.get("heat", 0.0)) > 0.0, "Nach dem Abkuehlen feuert sie wieder")
	# R dumps the heat early instead of doing nothing at all.
	s.reloading = 0.0
	s.vent = false
	# Full weapon, full pack: the reserve limit counts spare cells only, so venting must not clamp
	# the sum against it and swallow a whole magazine.
	s.ammo = int(s.def.mag)
	s.reserve = w.reserve_limit("plasma_sniper")
	s.heat = 0.5
	var carried: int = int(s.ammo) + int(s.reserve)
	w.reload()
	check(float(s.reloading) > 0.0, "R entlueftet von Hand statt ins Leere zu laufen")
	check(int(s.ammo) + int(s.reserve) == carried, "Das Entlueften kostet Zeit, keine Zellen (%d -> %d)" % [carried, int(s.ammo) + int(s.reserve)])
	var running: float = float(s.reloading)
	w.reload()
	check(is_equal_approx(float(s.reloading), running), "R waehrend der Entlueftung verlaengert die Wartezeit nicht")
	# Bar and trigger have to end together: the player may not stare at an empty bar and a dead gun.
	check(str(w.specials.hud_state(w, "plasma_sniper").get("text", "")).contains("ENTL"), "Waehrend der Entlueftung sagt die Anzeige das auch")
	# The real path: _tick_ammo counts the bar down, refills the magazine and ticks the specials.
	for i in 400:
		w._tick_ammo(0.02)
		if not bool(s.get("vent", false)): break
	check(int(s.ammo) > 0, "Nach der Entlueftung sind wieder Zellen geladen (%d)" % int(s.ammo))
	check(not w.specials.blocks_fire(w, "plasma_sniper"), "Wenn der Balken leer ist, feuert die Waffe wieder")
	check(int(s.ammo) + int(s.reserve) == carried, "Der ganze Vorgang kostet keine einzige Zelle (%d)" % (int(s.ammo) + int(s.reserve)))

	# The wire format: a client is told about a hot barrel through this and nothing else.
	s = equip(w, "plasma_sniper")
	fire_once(w)
	var wire := WeaponSpecials.net_state(w, "plasma_sniper")
	check(wire.size() == 2 and is_equal_approx(float(wire[0]), snappedf(float(s.heat), 0.01)), "Die Hitze faehrt im Snapshot mit (%s)" % str(wire))
	w.specials.apply_net_state(w, "plasma_sniper", [0.9, 0.0])
	check(is_equal_approx(float(s.heat), 0.9), "Der Host korrigiert die Hitze des Clients")
	check(WeaponSpecials.net_state(w, "pistol").is_empty(), "Waffen ohne Sondermechanik belasten den Snapshot nicht")

	# ---------------------------------------------------------------- minigun: spin-up
	s = equip(w, "minigun")
	var first_interval := 0.0
	fire_once(w)
	first_interval = float(s.cooldown)
	var penalty: float = float(Weapons.DEFS.minigun.special.penalty)
	check(first_interval > float(s.def.rate) * (penalty - 0.5), "Der erste Schuss kommt mit voller Anlaufbremse (%.3f s)" % first_interval)
	check(int(s.ammo) == int(s.def.mag) - 1, "Der erste Schuss faellt trotzdem, er ist nur langsam")
	# Hold the trigger: the barrels come up to speed within the advertised time.
	for i in 30:
		w.specials.tick(w, 0.05)
		fire_once(w)
	check(float(s.get("spin", 0.0)) > 0.9, "Dauerfeuer bringt die Laeufe auf Touren (%.2f)" % float(s.get("spin", 0.0)))
	s.cooldown = 0.0
	fire_once(w)
	check(float(s.cooldown) < float(s.def.rate) * 1.25, "Auf Drehzahl feuert sie mit voller Rate (%.3f s)" % float(s.cooldown))
	check(w.specials.movement_multiplier(w) < 0.5, "Feuernd ist der Spieler fast festgenagelt")
	# Sustained fire has to open the cone, or the rotary gun would be a laser pointer.
	w.spread_mul = 1.0
	w._bloom = 0.0
	var spread_cold := w.effective_spread()
	for i in 12: fire_once(w)
	check(w.effective_spread() > spread_cold * 1.2, "Dauerfeuer weitet die Streuung (%.4f -> %.4f)" % [spread_cold, w.effective_spread()])
	w.spread_mul = 0.0
	# The belt change: the barrels must run down while the weapon is being reloaded.
	s.ammo = 0
	w.reload()
	check(float(s.reloading) > 0.0, "Der Gurtwechsel laeuft")
	for i in 20: w.specials.tick(w, 0.05)
	check(float(s.get("spin", 1.0)) < 0.5, "Waehrend des Gurtwechsels laufen die Laeufe aus (%.2f)" % float(s.get("spin", 1.0)))
	s.reloading = 0.0
	# Letting go: the spin falls without any key being held (the host runs a teammate this way).
	for i in 40: w.specials.tick(w, 0.05)
	check(float(s.get("spin", 1.0)) <= 0.01, "Ohne Schuesse laufen die Laeufe aus")
	check(w.specials.movement_multiplier(w) > 0.5, "Getragen ist sie langsam, aber nicht festgenagelt")
	# And the weight has to arrive where the player actually moves, not only in its own function.
	w.set_weapon("pistol")
	var light_speed := p.effective_speed_mul()
	w.set_weapon("minigun")
	var heavy_speed := p.effective_speed_mul()
	check(heavy_speed < light_speed * 0.8, "Mit der Minigun laeuft der Spieler wirklich langsamer (%.2f -> %.2f)" % [light_speed, heavy_speed])
	w.set_weapon("pistol")
	check(is_equal_approx(p.effective_speed_mul(), light_speed), "Nach dem Wegstecken ist das Tempo wieder normal")
	w.set_weapon("minigun")
	s = w.cur()

	# ---------------------------------------------------------------- lever action: cycling
	s = equip(w, "lever_rifle")
	fire_once(w)
	check(float(s.get("cycle_t", -1.0)) > 0.0, "Der Unterhebel wird nach dem Schuss geworfen (%.3f s)" % float(s.get("cycle_t", -1.0)))
	# The roll rides on the same damped spring as the recoil, so it is measured on its own: the
	# shot's own sideways impulse would otherwise mask it.
	var roll_before := w._model_velocity.y
	w.specials.on_shot(w, "lever_rifle", Vector3.ZERO, Vector3.FORWARD)
	check(w._model_velocity.y - roll_before >= float(Weapons.DEFS.lever_rifle.special.roll) - 0.001, "Das Modell rollt beim Repetieren (%.2f)" % (w._model_velocity.y - roll_before))
	for i in 40: w.specials.tick(w, 0.02)
	check(float(s.get("cycle_t", 1.0)) <= 0.0, "Nach der Repetierzeit ist der Hebel wieder unten")

	# ---------------------------------------------------------------- cryo: freeze builds up
	var target := spawn("brute", Vector3(0, 60, -6))
	target.hp = 100000.0
	await physics_frame
	await physics_frame
	s = equip(w, "cryo_smg")
	w.spread_mul = 0.0
	p.camera.look_at(target.global_position + Vector3.UP * Player.EYE)
	var slow_seen := false
	for i in 12:
		fire_once(w)
		if target.frost_mul < 0.99 and not target.rare_status.contains("frost"): slow_seen = true
		if target.rare_status.contains("frost"): break
	check(slow_seen, "Treffer kuehlen den Koerper sichtbar herunter, bevor er einfriert")
	check(target.rare_status.contains("frost"), "Genug Treffer frieren ihn ein")
	check(target.frost_mul <= 0.8, "Eingefroren laeuft er deutlich langsamer (%.2f)" % target.frost_mul)
	var frozen_hp := target.hp
	fire_once(w)
	var expected := float(w.cur().def.damage) * w.effective_damage_mul()
	check(frozen_hp - target.hp > expected * 1.05, "Im gefrorenen Zustand richtet derselbe Schuss mehr Schaden an")

	# ---------------------------------------------------------------- graviton: area damage
	var pack: Array[Zombie] = []
	for i in 4:
		var z := spawn("shambler", Vector3(1.6 * i - 2.4, 60, -14))
		z.hp = 100000.0
		pack.append(z)
	s = equip(w, "graviton_cannon")
	await physics_frame
	await physics_frame
	p.camera.look_at(pack[1].global_position + Vector3.UP * Player.EYE)
	var hp_before: Array[float] = []
	for z in pack: hp_before.append(z.hp)
	fire_once(w)
	var hurt := 0
	for i in pack.size():
		if pack[i].hp < hp_before[i]: hurt += 1
	check(hurt >= 3, "Ein Schuss trifft die ganze Gruppe (%d von 4)" % hurt)
	check(pack[1].hp < hp_before[1] - float(Weapons.DEFS.graviton_cannon.special.damage) * 0.5, "Im Zentrum trifft der volle Flaechenschaden")
	# The blast is deliberately independent of the damage multipliers, or it would scale to 5700.
	var solo := spawn("shambler", Vector3(0, 60, -30))
	solo.hp = 100000.0
	await physics_frame
	await physics_frame
	var before_mul := w.damage_mul
	w.damage_mul = 3.0
	p.camera.look_at(solo.global_position + Vector3.UP * Player.EYE)
	s.ammo = int(s.def.mag)
	s.cooldown = 0.0
	var solo_hp := solo.hp
	fire_once(w)
	var dealt := solo_hp - solo.hp
	w.damage_mul = before_mul
	check(dealt < float(Weapons.DEFS.graviton_cannon.damage) * 3.0 + float(Weapons.DEFS.graviton_cannon.special.damage) * 1.2,
		"Der Flaechenschaden skaliert nicht mit Schusskraft (%.0f Schaden)" % dealt)

	# Point blank: the gravity well takes a bite out of the shooter as well.
	var near := spawn("shambler", Vector3(0, 60, 2.6))
	near.hp = 100000.0
	await physics_frame
	await physics_frame
	p.camera.look_at(near.global_position + Vector3.UP * Player.EYE)
	s.ammo = int(s.def.mag)
	s.cooldown = 0.0
	var player_hp := p.hp
	fire_once(w)
	check(p.hp < player_hp, "Ein Schuss vor die eigenen Fuesse kostet Leben (%.0f Schaden)" % (player_hp - p.hp))
	check(p.hp > player_hp - float(Weapons.DEFS.graviton_cannon.special.self_damage) - 1.0, "Der Eigenschaden bleibt unter dem Maximum")
	p.hp = player_hp

	# ---------------------------------------------------------------- flare: fire and light
	var burn_target := spawn("shambler", Vector3(9, 60, -7))   # clear line, the brute above is at z -6
	burn_target.hp = 100000.0
	await physics_frame
	await physics_frame
	s = equip(w, "flare_pistol")
	p.camera.look_at(burn_target.global_position + Vector3.UP * Player.EYE)
	var before_children := game.get_child_count()
	# The pumpkin lanterns are OmniLight3D children of the scene from the start, so only the
	# difference proves that the flare planted one of its own.
	var lights_before := 0
	for node in game.get_children():
		if node is OmniLight3D: lights_before += 1
	var hp_at_shot := burn_target.hp
	fire_once(w)
	check(game.get_child_count() > before_children, "Der Schuss setzt ein brennendes Geschoss in die Welt")
	var star: Node = game.get_child(game.get_child_count() - 1)
	for i in 240:
		await physics_frame
		if not is_instance_valid(star): break
	check(not is_instance_valid(star), "Das Geschoss schlaegt ein statt endlos zu fliegen")
	check(hp_at_shot - burn_target.hp >= float(Weapons.DEFS.flare_pistol.damage), "Der Treffer selbst tut weh (%.0f Schaden)" % (hp_at_shot - burn_target.hp))
	check(burn_target.rare_status.contains("fire"), "Die Leuchtpistole setzt ihr Ziel in Brand")
	# Counted straight after the impact: an explosion light from the graviton section fades out
	# during the burn wait below and would turn the difference negative.
	var lights_after := 0
	for node in game.get_children():
		if node is OmniLight3D: lights_after += 1
	check(lights_after > lights_before, "Das Leuchtfeuer setzt ein neues Licht in die Szene (%d -> %d)" % [lights_before, lights_after])
	var status: Dictionary = game.progression.rare_market.statuses[burn_target]
	check(float(status.burn) > 3.05, "Sie brennt laenger als eine gekaufte Brandkugel (%.2f s)" % float(status.burn))
	var burning_hp := burn_target.hp
	for i in 300: await physics_frame        # five seconds, safely past the four the flare burns
	check(burning_hp - burn_target.hp >= 46.0, "Das Feuer frisst vier Sekunden weiter (%.0f Schaden)" % (burning_hp - burn_target.hp))
	check(not burn_target.rare_status.contains("fire"), "Danach ist das Feuer aus")
	# ---------------------------------------------------------------- mods that must not fit
	for pair in [["extended", "plasma_sniper"], ["endless", "graviton_cannon"], ["extended", "minigun"],
			["suppressor", "mac10"], ["match_barrel", "flare_pistol"], ["endless", "deagle"]]:
		check(not Weapons.Mods.compatible(str(pair[0]), str(pair[1]), Weapons.DEFS[str(pair[1])]),
			"%s passt nicht auf %s" % [pair[0], pair[1]])
	for pair in [["compensator", "deagle"], ["quick_action", "lever_rifle"], ["titan_core", "graviton_cannon"]]:
		check(Weapons.Mods.compatible(str(pair[0]), str(pair[1]), Weapons.DEFS[str(pair[1])]),
			"%s passt auf %s" % [pair[0], pair[1]])

	print("WEAPON_SPECIALS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

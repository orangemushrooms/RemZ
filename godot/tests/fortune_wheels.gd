# The wheels of fortune in the Holzlager (27 Sep 2026): prize table, landing, payouts, co-op snapshot.
# godot --headless --path godot --script res://tests/run.gd -- --suite=fortune_wheels --smoke-test --no-intro --no-music --no-foliage
# Windowed with --render-fortune: artifacts/fortune/{hall,wheel,spin,win,night}.png
extends SceneTree

var game: Node3D
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 240000:
		print("FORTUNE_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func run_wheel(f: FortuneWheels, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		for wheel in f.wheels: wheel._process(1.0 / 60.0)
		f._process(1.0 / 60.0)
		t += 1.0 / 60.0

func run() -> void:
	var render := "--render-fortune" in OS.get_cmdline_user_args()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.set_process(false)
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	var f: FortuneWheels = game.fortune
	check(f != null and f.wheels.size() == 2, "two wheels stand in the Holzlager")
	if f == null:
		_finish()
		return

	# --- the table
	var odds := FortuneWheels.table()
	var total := 0.0
	for key in odds: total += float(odds[key])
	check(absf(total - 1.0) < 0.0001, "the chances add up to 100 % (%.5f)" % total)
	check(float(odds.nothing) > 0.3 and float(odds.nothing) < 0.5, "a blank on %.1f %% of the spins" % (float(odds.nothing) * 100.0))
	var pool := FortuneWheels.weapon_pool()
	check(pool.size() == Progression.GOODS.size() and not pool.has("pistol") and not pool.has("knife"), "every traded weapon is on the wheel, not the starting pistol and knife (%d)" % pool.size())
	var monotonic := true
	for a in pool:
		for b in pool:
			if int(Progression.GOODS[a].price) < int(Progression.GOODS[b].price) and FortuneWheels.weapon_chance(a) <= FortuneWheels.weapon_chance(b): monotonic = false
	check(monotonic, "the dearer the weapon, the rarer it is")
	var minigun := 1.0 / FortuneWheels.weapon_chance("minigun")
	check(minigun > 2000.0 and minigun < 5000.0, "the minigun comes once in %d spins" % int(minigun))
	check(FortuneWheels.weapon_chance("graviton_cannon") < FortuneWheels.weapon_chance("minigun"), "the graviton cannon is the rarest prize")
	check(FortuneWheels.weapon_chance("hatchet") > 0.008, "the axe comes once in %d spins" % int(1.0 / FortuneWheels.weapon_chance("hatchet")))
	for key in odds: print("FORTUNE_ODDS %s %.4f%%" % [key, float(odds[key]) * 100.0])

	# --- rolling matches the table
	var random := RandomNumberGenerator.new()
	random.seed = 2709
	var counts := {}
	var n := 200000
	for i in n:
		var result := FortuneWheels.roll(random)
		var key: String = "weapon:" + result.weapon if result.has("weapon") else result.kind
		counts[key] = int(counts.get(key, 0)) + 1
		if result.has("weapon") and result.kind != FortuneWheels.tier_of(result.weapon): counts["bad_tier"] = 1
	var close := true
	for key in ["nothing", "mushroom", "ammo", "free_spin", "grenade", "weapon:hatchet", "weapon:ak47"]:
		var seen := float(counts.get(key, 0)) / n
		if absf(seen - float(odds[key])) > maxf(0.004, float(odds[key]) * 0.15): close = false
		print("FORTUNE_ROLL %s expected %.4f seen %.4f" % [key, float(odds[key]), seen])
	check(close, "200 000 rolls follow the table")
	check(not counts.has("bad_tier"), "every weapon lands in its price tier")

	# --- landing: every kind stops on a segment of its own kind
	var wheel: FortuneWheel = f.wheels[0]
	var landed_ok := true
	var near_miss := 0
	for kind in FortuneWheels.LOOK:
		for k in 12:
			var land := f.landing(kind)
			wheel.start(100 + k, int(land.x), land.y, 5.0, 3, ["", "", kind])
			for step in 320: wheel._process(1.0 / 60.0)
			var at := FortuneWheel.segment_at(wheel.angle)
			if wheel.spinning or FortuneWheels.SEGMENTS[at] != kind: landed_ok = false
			if kind == "nothing" and absf(wheel.angle - wheel.a1) < 0.0001 and FortuneWheels.SEGMENTS[posmod(at + 1, 24)] == "weapon_legendary": near_miss += 1
	check(landed_ok, "the wheel stops on a segment of the drawn prize, for every kind")
	var turned := wheel.a1 - wheel.a0
	check(turned > 3.0 * TAU and turned < 6.0 * TAU, "a spin turns the wheel 3-5 times (%.1f)" % (turned / TAU))
	print("FORTUNE_NEAR_MISS %d of 12 blanks beside the jackpot" % near_miss)

	# --- the flapper rides on the pegs
	var flap_max := 0.0
	wheel.start(200, 3, 0.5, 5.0, 3, ["", "", "ammo"])
	for step in 300:
		wheel._process(1.0 / 60.0)
		flap_max = maxf(flap_max, absf(wheel.flapper.rotation.z))
	check(flap_max > 0.2, "the pegs push the flapper aside (%.2f rad)" % flap_max)

	# --- the scene: stand, disc, floor
	check(wheel._meshy_stand, "the Meshy stand is loaded")
	check(wheel.disc.get_child_count() > 60, "the disc carries face, rim, pegs, marks (%d parts)" % wheel.disc.get_child_count())
	for i in 4: await physics_frame
	var q := PhysicsRayQueryParameters3D.create(wheel.global_position + Vector3(0, 1.5, 0.9), wheel.global_position + Vector3(0, -2, 0.9), 1)
	var hit := root.get_world_3d().direct_space_state.intersect_ray(q)
	check(not hit.is_empty() and absf(hit.position.y - wheel.global_position.y) < 0.12, "the wheels stand on the shed floor (%.2f)" % (hit.position.y - wheel.global_position.y if not hit.is_empty() else 99.0))
	var shed_door := Vector3.ZERO
	for l in game.loots:
		if l is Door and l.key_id == "holzlager": shed_door = l.global_position
	check(shed_door != Vector3.ZERO and shed_door.distance_to(wheel.global_position) < 14.0, "the wheels are inside the Holzlager (door %.1f m away)" % shed_door.distance_to(wheel.global_position))

	# --- a paid spin, solo
	var p: Player = game.player
	var w: Weapons = game.weapons
	p.global_position = wheel.stand_point() + Vector3(0, 0.2, 0)
	p.score = 1000
	check(f.nearest(p) == 0, "the player stands at the first wheel")
	check(Lang.text(f.prompt(p)).contains("[E]"), "the prompt offers the spin: " + Lang.text(f.prompt(p)).replace("\n", " / "))
	var answer := f.spin(p, 0)
	check(answer.is_empty() and p.score == 990, "a spin costs 10 R (%d)" % p.score)
	check(wheel.spinning and not f.pending[0].is_empty(), "the wheel turns and the prize waits")
	check(not f.spin(p, 0).is_empty() and p.score == 990, "a turning wheel takes no second stake")
	check(not Lang.text(f.prompt(p)).contains("[E]"), "while it turns the prompt offers nothing")
	f.last_message = ""
	run_wheel(f, 8.0)
	check(not wheel.spinning and f.pending[0].is_empty() and not f.last_message.is_empty(), "the prize is paid when the wheel stops: " + Lang.text(f.last_message))
	var far := p.global_position
	p.global_position = wheel.stand_point() + Vector3(0, 0, 6)
	check(not f.spin(p, 0).is_empty() and f.prompt(p).is_empty(), "no spin from across the shed")
	p.global_position = far
	p.score = 5
	check(not f.spin(p, 0).is_empty() and p.score == 5, "no spin without 10 R")
	p.score = 1000

	# --- every payout
	var stock: Dictionary = game.progression.mushroom_stock(p)
	var mushrooms_before := 0
	for kind in stock: mushrooms_before += int(stock[kind])
	f.grant(p, {"kind": "mushroom"})
	var mushrooms_after := 0
	for kind in stock: mushrooms_after += int(stock[kind])
	check(mushrooms_after == mushrooms_before + 1, "a mushroom lands in the inventory")
	w.state["pistol"].reserve = 0
	w.set_weapon("pistol")
	f.grant(p, {"kind": "ammo"})
	check(int(w.state["pistol"].reserve) == 24, "ammo: two magazines for the gun in hand (%d)" % int(w.state["pistol"].reserve))
	var score := p.score
	f.grant(p, {"kind": "free_spin"})
	check(p.score == score + 10, "a free spin gives the stake back")
	f.grant(p, {"kind": "cash100"})
	check(p.score == score + 110, "100 R are paid")
	w.grenades = 0
	f.grant(p, {"kind": "grenade"})
	check(w.grenades == 1, "a grenade goes into the pouch")
	w.grenades = w.grenades_max
	score = p.score
	f.grant(p, {"kind": "grenade"})
	check(w.grenades == w.grenades_max and p.score == score + 10, "a full pouch gets the stake back")
	p.hp = 20.0
	f.grant(p, {"kind": "medkit"})
	check(is_equal_approx(p.hp, 80.0), "a medkit heals 60 (%.0f)" % p.hp)
	w.unlocked["minigun"] = false
	var text := f.grant(p, {"kind": "weapon_legendary", "weapon": "minigun"})
	check(w.unlocked.get("minigun", false) and int(w.state["minigun"].reserve) == 450, "the minigun is won with three spare belts: " + Lang.text(text))
	w.state["minigun"].reserve = 0
	text = f.grant(p, {"kind": "weapon_legendary", "weapon": "minigun"})
	check(int(w.state["minigun"].reserve) == 450, "a second minigun pays its ammo instead: " + Lang.text(text))
	w.unlocked["hatchet"] = true
	w.state["pistol"].reserve = 0
	text = f.grant(p, {"kind": "weapon_common", "weapon": "hatchet"})
	check(int(w.state["pistol"].reserve) > 0, "a second axe pays ammo for a gun: " + Lang.text(text))
	for id in w.state:
		if not Weapons.is_melee(id) and w.unlocked.get(id, false): w.state[id].reserve = w.reserve_limit(id)
	score = p.score
	text = f.grant(p, {"kind": "weapon_rare", "weapon": "minigun"})
	check(p.score == score + 10, "full pockets get the stake back: " + Lang.text(text))

	# --- co-op snapshot: a second wheel replays the first
	f.pending[0] = {}
	wheel.start(777, 11, 0.4, 6.0, 4, ["ak47", "AK-47", "weapon_rare"])
	for step in 90: wheel._process(1.0 / 60.0)
	var other: FortuneWheel = f.wheels[1]
	other.apply_snapshot(wheel.snapshot())
	check(other.serial == 777 and other.spinning and absf(other.a1 - wheel.a1) < 0.0001, "a client picks up a running spin from the snapshot")
	for step in 400:
		wheel._process(1.0 / 60.0)
		other._process(1.0 / 60.0)
	check(FortuneWheel.segment_at(other.angle) == 11 and FortuneWheel.segment_at(wheel.angle) == 11, "host and client wheel stop on the same segment")
	check(other._pop_label.visible and other._pop_label.text == "AK-47", "the client shows the won weapon above the wheel")
	var late := FortuneWheel.new()
	late.build(f, 5)
	f.add_child(late)
	late.apply_snapshot(wheel.snapshot())
	check(not late.spinning and FortuneWheel.segment_at(late.angle) == 11, "a late joiner sees the wheel where it stopped")
	late.queue_free()

	if render: await _render(f)
	_finish()

func _finish() -> void:
	print("FORTUNE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _render(f: FortuneWheels) -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	for layer in root.find_children("*", "CanvasLayer", true, false): layer.visible = false
	game.weapons.viewmodel.hide()
	for wheel in f.wheels:
		wheel._pop_t = -1.0
		wheel._pop.hide()
		wheel._pop_label.hide()
		wheel.flash = 0.0
		wheel._highlight.hide()
	var dir := ProjectSettings.globalize_path("res://../artifacts/fortune/")
	DirAccess.make_dir_recursive_absolute(dir)
	var cam := Camera3D.new()
	cam.fov = 62.0
	game.add_child(cam)
	cam.make_current()
	game.player.camera.current = false
	var shed: Node3D = f.get_parent()
	var views := {
		"hall": [Vector3(0.2, 1.65, 2.2), Vector3(0, 1.2, -6.0), 17.0],
		"wheel": [Vector3(-1.2, 1.45, -3.9), Vector3(-1.55, 1.2, -6.1), 17.0],
		"night": [Vector3(0.6, 1.7, -1.2), Vector3(0, 1.4, -6.2), 22.5],
	}
	for key in views:
		var v: Array = views[key]
		game.day_night.set_time_hours(v[2])
		cam.global_position = shed.global_transform * (v[0] + Vector3(0, f.position.y, 0))
		cam.look_at(shed.global_transform * (v[1] + Vector3(0, f.position.y, 0)), Vector3.UP)
		for i in 40: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(dir + key + ".png")
		print("FORTUNE_SHOT " + key)
	# mid spin and the win, close up on the first wheel
	var wheel: FortuneWheel = f.wheels[0]
	game.day_night.set_time_hours(17.0)
	cam.global_position = wheel.global_transform * Vector3(0.25, 1.35, 1.9)
	cam.look_at(wheel.global_transform * Vector3(0, 1.2, 0), Vector3.UP)
	wheel.start(900, 23, 0.5, 3.0, 1, ["minigun", "Minigun M134", "weapon_legendary"])
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir + "spin.png")
	while wheel.spinning: await process_frame
	for i in 25: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir + "win.png")
	print("FORTUNE_SHOT spin win")

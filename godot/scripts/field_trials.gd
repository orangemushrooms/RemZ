class_name FieldTrials
extends Node3D

# Host-owned intermissions. The arena is wholly south of the forest edge.
const FIELD := Rect2(-80, 82, 200, 54)
const ARRIVAL := Vector2(20, 111)
const ROSTERS := {
	10: ["titan_hunter", "titan"],
	15: ["titan_hunter", "titan_siege", "titan_ash", "titan"],
	20: ["titan_hunter", "titan_siege", "titan_ash", "titan", "titan_elder", "earthworm", "earthworm_ancient"],
}
const SPAWNS := [Vector2(-65, 96), Vector2(104, 121), Vector2(-30, 125), Vector2(67, 92), Vector2(-61, 126), Vector2(99, 93), Vector2(10, 88)]
const SECRETS := [
	{"name": "THE QUIET GROVE", "at": Vector2(-52, -64), "wave": 6, "reward": 350, "flower": "golden_yarrow", "drink": "brew_fleet"},
	{"name": "ROOT MEMORY", "at": Vector2(-108, -169), "wave": 12, "reward": 700, "flower": "violet_bell", "drink": "brew_frost"},
]
var main: Node
var active := false
var next_wave := 0
var completed: Array = []
var secret_done: Array = []
var secret := -1
var stage := 0 # 0 arrival/offering, 1 combat, 2 claim the shrine
var countdown := 0.0
var pending: Array = []
var enemies: Array[Zombie] = []
var remaining := 0
var spawn_delay := 0.0
var saved_timer := 30.0
var joined: Dictionary = {}
var border: Node3D
var panel: Label
var shrines: Array[Node3D] = []
var teleport_serial := 0

func setup(game: Node) -> void:
	main = game
	name = "FieldTrials"
	add_to_group("render_dynamic")
	border = Node3D.new()
	add_child(border)
	# A low amber cord follows the soil. Confinement is shared by host and client
	# physics, so jumping or a remote movement packet cannot cross the boundary.
	var mat := Barricade._marker_material(Color(0.94, 0.57, 0.13), 0.65)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ribbon := SurfaceTool.new()
	ribbon.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [FIELD.position, Vector2(FIELD.end.x, FIELD.position.y), FIELD.end, Vector2(FIELD.position.x, FIELD.end.y)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var segments := ceili(a.distance_to(b) / 4.0)
		for i in segments:
			var p := a.lerp(b, float(i) / segments)
			var q := a.lerp(b, float(i + 1) / segments)
			var from := Map.ground_pos(p.x, p.y) + Vector3.UP * 0.18
			var to := Map.ground_pos(q.x, q.y) + Vector3.UP * 0.18
			var points := [from, to, to + Vector3.UP * 0.45, from + Vector3.UP * 0.45]
			for index in [0, 1, 2, 0, 2, 3]:
				ribbon.set_normal((to - from).cross(Vector3.UP).normalized())
				ribbon.add_vertex(points[index])
	DefenceTower.piece(border, ribbon.commit(), Vector3.ZERO, mat)
	border.hide()
	var canvas := CanvasLayer.new()
	canvas.layer = 9
	add_child(canvas)
	panel = Label.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top = 170
	panel.offset_left = 240
	panel.offset_right = -240
	panel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_theme_font_size_override("font_size", 22)
	panel.add_theme_color_override("font_color", Color(1, 0.83, 0.5))
	panel.add_theme_color_override("font_outline_color", Color.BLACK)
	panel.add_theme_constant_override("outline_size", 5)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	panel.hide()
	for spec in SECRETS:
		var shrine := Node3D.new()
		add_child(shrine)
		shrine.position = Map.ground_pos(spec.at.x, spec.at.y)
		var stone := CylinderMesh.new()
		stone.top_radius = 0.65
		stone.bottom_radius = 0.85
		stone.height = 0.65
		stone.radial_segments = 7
		DefenceTower.piece(shrine, stone, Vector3.UP * 0.325, DefenceTower.material(Color(0.25, 0.28, 0.22)))
		WorldModels.attach(shrine, "field_flower_3" if shrines.is_empty() else "field_flower_6", Vector3.UP * 0.65, 0.42)
		shrines.append(shrine)

func due(n: int) -> bool:
	return ROSTERS.has(n) and not completed.has(n)

func actors() -> Array:
	return NetSession.world.actors.values() if NetSession.enabled and NetSession.world else [main.player]

func begin(n: int) -> bool:
	if NetSession.is_client() or active or not due(n) or main.over: return false
	active = true
	secret = -1
	next_wave = n
	stage = 0
	countdown = 8.0
	pending = ROSTERS[n].duplicate()
	enemies.clear()
	joined.clear()
	remaining = pending.size()
	main.waves.phase = "field_trial"
	main.waves.queue.clear()
	main.waves.boss_fight = true
	main.day_night.set_time_hours(6.7)
	main.music.fight(true)
	_prepare_local()
	border.show()
	teleport_serial += 1
	for p: Player in actors(): _bring_player(p)
	main.broadcast_message(Lang.t("DAWN OF THE TITANS\nHold the field together. Defeat every boss to break the seal."), 7.0)
	return true

func _prepare_local() -> void:
	for menu in [main.inventory, main.progression, main.defences, main.skills, main.cheat_menu, main.brewing.menu, main.secret_night.bar]:
		if menu and "is_open" in menu and menu.is_open: menu.close()
	if main._notice_open: main._close_notice()

func _bring_player(p: Player) -> void:
	if joined.has(p.peer_id): return
	joined[p.peer_id] = true
	if p.mounted_tower and main.defences.towers.has(p.mounted_tower): main.defences.release_tower(main.defences.towers[p.mounted_tower])
	if p.controlling_drone: main.drones.recall(p)
	if not p.alive or p.downed: p.revive(p.max_hp * 0.65)
	var offset := Vector2((joined.size() - 1) * 2.4 - 3.6, 0)
	p.global_position = Map.ground_pos(ARRIVAL.x + offset.x, ARRIVAL.y) + Vector3.UP * 0.3
	p.velocity = Vector3.ZERO
	p._motion_ready = false
	main.progression.weapon_for(p).refill_all()

func confine(p: Player) -> void:
	if not active or secret >= 0: return
	var safe := FIELD.grow(-1.2)
	var at := Vector2(p.global_position.x, p.global_position.z)
	var clamped := at.clamp(safe.position, safe.end)
	if clamped == at: return
	p.global_position.x = clamped.x
	p.global_position.z = clamped.y
	p.global_position.y = Map.ground_height(clamped.x, clamped.y) + 0.3
	p.velocity = Vector3.ZERO
	p._motion_ready = false

func permits(point: Vector3) -> bool:
	return not active or secret >= 0 or FIELD.grow(-1.2).has_point(Vector2(point.x, point.z))

func _process(delta: float) -> void:
	if not active:
		panel.hide()
		return
	if main.over:
		border.hide()
		panel.hide()
		return
	panel.show()
	if not NetSession.is_client():
		if secret < 0:
			for p: Player in actors():
				_bring_player(p)
				confine(p)
			countdown = maxf(0, countdown - delta)
			if countdown <= 0: stage = 1
		if stage == 1:
			spawn_delay -= delta
			if not pending.is_empty() and spawn_delay <= 0:
				_spawn_next()
				spawn_delay = 0.6
			remaining = pending.size()
			for z in enemies:
				if is_instance_valid(z) and z.alive: remaining += 1
			if remaining == 0:
				if secret < 0: finish()
				else: stage = 2
	if not active: return
	if secret < 0:
		panel.text = Lang.t("DAWN OF THE TITANS · BEFORE WAVE %d\n%s", [next_wave, Lang.t("Arriving in %d s · Stay inside the amber boundary", [ceili(countdown)]) if countdown > 0 else Lang.t("%d bosses remain · The field is sealed", [remaining])])
		main.hud.set_wave(next_wave, "FIELD TRIAL")
	else:
		var spec: Dictionary = SECRETS[secret]
		var task := Lang.t("Offer 3 × %s at the stone. [E]", [main.brewing.Recipes.FLOWERS[spec.flower].name]) if stage == 0 else (Lang.t("Defend the grove · %d enemies remain", [remaining]) if stage == 1 else Lang.t("Return to the stone and claim the forest's gift. [E]"))
		panel.text = Lang.t(spec.name) + "\n" + task

func _spawn_next() -> void:
	var index := enemies.size()
	var at: Vector2 = SPAWNS[index % SPAWNS.size()] if secret < 0 else SECRETS[secret].at + Vector2(cos(index * 2.4), sin(index * 2.4)) * 11.0
	if not main.spawn_zombie(pending[0], at, 1.0): return
	var z := main.zombies_root.get_child(main.zombies_root.get_child_count() - 1) as Zombie
	z.set_meta("intermission_enemy", true)
	z.begin_hunt()
	enemies.append(z)
	pending.pop_front()

func finish(skipped := false) -> void:
	if NetSession.is_client() or not active: return
	if secret < 0: completed.append(next_wave)
	else: secret_done.append(secret)
	if skipped:
		# Removing the encounter is a cheat, not a kill or a quest reward.
		for z in enemies:
			if is_instance_valid(z): z.queue_free()
	else:
		var reward: int = next_wave * 35 if secret < 0 else SECRETS[secret].reward
		if main.get("classes"): main.classes.objective("field_%d_%d" % [secret, next_wave], maxi(750, reward * 2))
		for p: Player in actors():
			p.add_score(reward)
			if secret >= 0:
				var drinks: Dictionary = main.brewing.stock(p.peer_id).drinks
				var id: String = SECRETS[secret].drink
				drinks[id] = mini(main.brewing.Recipes.DRINK_LIMIT, int(drinks.get(id, 0)) + 2)
		main.broadcast_message(Lang.t("TRIAL COMPLETE · +%d R per player\nThe path is open. Prepare for the next wave.", [reward]), 6.0)
	active = false
	pending.clear()
	border.hide()
	panel.hide()
	main.waves.phase = "idle"
	main.waves.timer = 30.0 if secret < 0 else maxf(20, saved_timer)
	main.waves.boss_fight = false
	main.music.play(main.music.intermission_track(main.day_night.clock_seconds / 3600.0))

func nearby_shrine(p: Player) -> int:
	for i in shrines.size():
		if main.hunting.reachable(p, shrines[i].global_position + Vector3.UP * 0.8, 3.0): return i
	return -1

func prompt(p: Player) -> String:
	var i := nearby_shrine(p)
	if i < 0 or secret_done.has(i) or main.waves.completed < int(SECRETS[i].wave): return ""
	if active:
		if secret != i or stage == 1: return ""
		return "[E] Offer flowers to the grove" if stage == 0 else "[E] Claim the forest's gift"
	if main.waves.phase != "idle" or main.secret_night.active: return ""
	return Lang.t("[E] Read the hidden stone · %s", [SECRETS[i].name])

func interact(p: Player) -> void:
	if NetSession.is_client() or not p.alive or p.downed or prompt(p).is_empty(): return
	var i := nearby_shrine(p)
	if not active:
		active = true
		secret = i
		stage = 0
		enemies.clear()
		pending.clear()
		saved_timer = main.waves.timer
		main.waves.phase = "secret_grove"
		main.broadcast_message(Lang.t("%s\nThe stone whispers: bring three flowers, then guard the roots.", [SECRETS[i].name]), 7.0)
	elif stage == 0:
		var stock: Dictionary = main.brewing.stock(p.peer_id).flowers
		var id: String = SECRETS[i].flower
		if int(stock.get(id, 0)) < 3: return
		stock[id] -= 3
		stage = 1
		pending = ["runner", "shambler", "zombie_stag", "soldier"] if i == 0 else ["forest_spirit", "stalker", "stalker"]
		remaining = pending.size()
		main.music.fight(i == 1)
	elif stage == 2: finish()

func snapshot() -> Dictionary:
	return {"active": active, "next": next_wave, "done": completed.duplicate(), "secrets": secret_done.duplicate(), "secret": secret, "stage": stage, "countdown": countdown, "remaining": remaining, "teleport": teleport_serial}

func apply_snapshot(data: Dictionary) -> void:
	if data.is_empty(): return
	var entered := not active and bool(data.active)
	active = bool(data.active)
	next_wave = int(data.next)
	completed = data.done.duplicate()
	secret_done = data.secrets.duplicate()
	secret = int(data.secret)
	stage = int(data.stage)
	countdown = float(data.countdown)
	remaining = int(data.remaining)
	teleport_serial = int(data.teleport)
	border.visible = active and secret < 0
	panel.visible = active
	if entered:
		main.music.fight(secret < 0 or secret == 1)
		if secret < 0: _prepare_local()

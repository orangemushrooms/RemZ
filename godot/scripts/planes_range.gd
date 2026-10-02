extends Node3D
## OSM way 118083383. Exterior follows the supplied Street View and club photo;
## the interior is a playable reconstruction, not a surveyed interior.
const HOUSE_ID := 118083383
const CENTER := Vector2(-122.015,309.58)
const LOOT := ["marksman","titanbreaker","shotgun"]
const KEY_CHANCE := 1.0
var game: Node3D
var house: Node3D
var door: StaticBody3D
var shutters: Array[StaticBody3D] = []
var key: ForestKey
var key_spawned := false
var key_owned := false
var opened := false
var people := {}
var picked := {}
var loot_nodes := {}
var targets: Array[Area3D] = []
var board: Label3D
var last_night := -1
var entrance_link: NavigationLink3D
var monitors: Array[Label3D] = []
var lane_scores: Array[Dictionary] = []

func setup(scene: Node3D) -> void:
	game = scene
	house = Node3D.new()
	add_child(house)
	var axis := Vector3(0.31,0,0.95).normalized()
	house.basis = Basis(axis,Vector3.UP,axis.cross(Vector3.UP))
	house.position = Map.ground_pos(CENTER.x,CENTER.y)
	var floor_y := house.position.y
	for x in [-7.7,7.7]:
		for z in [-3.3,3.3]:
			var p := house.to_global(Vector3(x,0,z))
			floor_y = maxf(floor_y,Map.ground_height(p.x,p.z)+0.12)
	house.position.y = floor_y
	_build_house()
	for node in game.landscape.get_children():
		if not node.has_meta("target_panels"): continue
		for frame: Transform3D in node.get_meta("target_panels"):
			var target := Area3D.new()
			target.collision_layer = Zombie.HITBOX_LAYER
			target.collision_mask = 0
			target.monitoring = false
			target.monitorable = false
			target.set_meta("range_target",targets.size())
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.2,1.24,0.08)
			cs.shape = shape
			target.add_child(cs)
			add_child(target)
			target.transform = frame.translated_local(Vector3(0,0,0.1))
			targets.append(target)
	# Number lanes left-to-right as seen from inside the house, independently
	# of the survey polygon's winding and target construction order.
	var ordered := targets.duplicate()
	ordered.sort_custom(func(a: Area3D,b: Area3D): return house.to_local(a.global_position).x < house.to_local(b.global_position).x)
	for i in ordered.size(): ordered[i].set_meta("range_lane",i)
	key = ForestKey.new()
	add_child(key)
	key.key_id = "shooting_house"
	key.hide()
	var hint := Label3D.new()
	hint.text = "Schützenhaus · Key"
	hint.position.y = 1.1
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.modulate = Hud.GOLD
	hint.font_size = 28
	hint.pixel_size = 0.004
	hint.visibility_range_end = 32
	key.add_child(hint)
	reset_run()

func _piece(size: Vector3, at: Vector3, material: Material, solid := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	house.add_child(body)
	body.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	DefenceTower.piece(body,mesh,Vector3.ZERO,material)
	if solid:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
	return body

func _build_house() -> void:
	var timber := Foliage.pbr("planks",0.65,Color(0.65,0.47,0.32))
	var concrete := Foliage.pbr("ph_gravel",0.35,Color(0.63,0.61,0.55))
	var roof := Foliage.pbr("roof",0.65,Color(0.8,0.56,0.43))
	for material in [timber,concrete,roof]: material.uv1_triplanar = true
	var trim := DefenceTower.material(Color(0.52,0.48,0.37))
	_piece(Vector3(15.4,2.4,6.6),Vector3(0,-1.2,0),concrete)
	# West road facade: dark vertical timber, central pale door and posted notices.
	_piece(Vector3(6.2,2.5,0.18),Vector3(-4.6,1.25,3.3),timber)
	_piece(Vector3(7.8,2.5,0.18),Vector3(3.8,1.25,3.3),timber)
	_piece(Vector3(1.4,0.3,0.18),Vector3(-0.8,2.35,3.3),timber)
	door = _piece(Vector3(1.35,2.2,0.16),Vector3(-0.8,1.1,3.3),DefenceTower.material(Color(0.56,0.59,0.56)))
	for x in [-7.7,7.7]: _piece(Vector3(0.18,2.5,6.6),Vector3(x,1.25,0),timber)
	# Narrow vertical boards match the roadside facade; one instanced draw.
	var boards := MultiMesh.new()
	boards.transform_format = MultiMesh.TRANSFORM_3D
	boards.use_colors = true
	var plank := BoxMesh.new()
	plank.size = Vector3(0.135,2.48,0.025)
	var board_material := DefenceTower.material(Color(0.23,0.20,0.16))
	board_material.vertex_color_use_as_albedo = true
	plank.material = board_material
	boards.mesh = plank
	var frames: Array[Transform3D] = []
	for i in 108:
		var x := -7.6+i*0.142
		if absf(x+0.8)<0.8: continue
		frames.append(Transform3D(Basis.IDENTITY,Vector3(x,1.25,3.403)))
	boards.instance_count = frames.size()
	for i in frames.size():
		boards.set_instance_transform(i,frames[i])
		boards.set_instance_color(i,Color.WHITE*(0.84+fposmod(i*0.618,1)*0.22))
	var siding := MultiMeshInstance3D.new()
	siding.multimesh = boards
	house.add_child(siding)
	# Six shooting ports face the real 300 m targets east-northeast.
	_piece(Vector3(15.4,0.8,0.18),Vector3(0,0.4,-3.3),timber)
	_piece(Vector3(15.4,0.4,0.18),Vector3(0,2.3,-3.3),timber)
	for i in 7: _piece(Vector3(0.18,1.3,0.18),Vector3(-7.7+i*15.4/6,1.45,-3.3),timber)
	for i in 6:
		var x := -7.7+(i+0.5)*15.4/6
		shutters.append(_piece(Vector3(2.39,1.3,0.12),Vector3(x,1.45,-3.3),timber))
		_piece(Vector3(1.65,0.1,1.35),Vector3(x,0.8,-2.4),timber)
		for side in [-0.62,0.62]: _piece(Vector3(0.08,0.75,0.08),Vector3(x+side,0.375,-2),trim,false)
		var monitor := _piece(Vector3(0.5,0.34,0.04),Vector3(x+0.6,1.05,-2.9),DefenceTower.material(Color(0.015,0.035,0.025)),false)
		monitor.rotation.x = -0.2
		var display := Label3D.new()
		monitor.add_child(display)
		display.position.z = 0.023
		display.font_size = 24
		display.pixel_size = 0.0017
		display.outline_size = 0
		display.modulate = Color(0.45,1.0,0.7)
		display.no_depth_test = false
		display.visibility_range_end = 20
		monitors.append(display)
	# Pitched tile roof and solid gables, no overlapping facade shells.
	for side in [-1,1]:
		var panel := _piece(Vector3(16.3,0.16,4.0),Vector3(0,3.35,side*1.68),roof)
		panel.rotation.x = side*deg_to_rad(27)
		_piece(Vector3(16.4,0.15,0.15),Vector3(0,2.42,side*3.58),trim,false)
	for x in [-7.7,7.7]:
		for i in 14:
			var z := (i-6.5)*0.47
			var h := maxf(0.1,1.7-absf(z)*0.5)
			_piece(Vector3(0.16,h,0.48),Vector3(x,2.5+h/2,z),timber,false)
	# Shallow steps follow the surveyed roadside ground into the doorway.
	var outside := house.to_global(Vector3(-0.8,0,6.2))
	var rise := maxf(0.1,house.position.y-Map.ground_height(outside.x,outside.z))
	var steps := maxi(1,ceili(rise/0.18))
	for i in steps:
		var h := rise*(steps-i)/steps
		_piece(Vector3(2.2,h+0.2,0.35),Vector3(-0.8,-rise+h/2-0.1,3.48+i*0.35),concrete,false)
	# Smooth collision under the shallow visible steps, also usable by zombies.
	var ramp := StaticBody3D.new()
	house.add_child(ramp)
	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for x in [-1.9,0.3]:
		points.append(Vector3(x,0.02,3.22))
		points.append(Vector3(x,-rise-0.15,3.22))
		points.append(Vector3(x,-rise-0.15,maxf(6.2,3.48+steps*0.35)))
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ramp.add_child(collider)
	var notice := Label3D.new()
	_piece(Vector3(0.8,0.85,0.04),Vector3(-6,1.64,3.44),DefenceTower.material(Color(0.8,0.79,0.71)),false)
	house.add_child(notice)
	notice.text = "SG REMETSCHWIL\n300 m\nSCHIESSANLAGE"
	notice.position = Vector3(-6,1.65,3.466)
	notice.font_size = 24
	notice.pixel_size = 0.0019
	notice.modulate = Color(0.13,0.15,0.12)
	board = Label3D.new()
	house.add_child(board)
	board.text = "!  300 m CHALLENGE\n[E] Read shooting log"
	board.position = Vector3(-5,1.5,1.8)
	board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	board.font_size = 32
	board.pixel_size = 0.006
	board.modulate = Hud.GOLD
	_piece(Vector3(3,0.12,0.9),Vector3(3.8,0.78,1.8),timber)
	for i in LOOT.size():
		var id: String = LOOT[i]
		var model: Node3D = load("res://assets/models/%s.glb" % Weapons.DEFS[id].model).instantiate()
		house.add_child(model)
		Weapons._fit_height(model,0.35)
		model.position = Vector3(2.8+i,0.9,1.8)
		loot_nodes[id] = model
	var ammo := _piece(Vector3(0.7,0.5,0.5),Vector3(5.7,0.25,1.8),DefenceTower.material(Color(0.24,0.28,0.14)))
	loot_nodes.ammo = ammo

func reset_run() -> void:
	people.clear(); picked.clear()
	lane_scores.clear()
	for i in 6: lane_scores.append({"score":0,"hits":0,"last":0})
	refresh_scores()
	key_owned = false; opened = false; key_spawned = false; last_night = -1
	for node in loot_nodes.values(): node.show()
	if not NetSession.is_client(): roll_key()
	refresh()

func grant_key() -> bool:
	if key_owned: return false
	key_owned = true
	refresh()
	return true

func roll_key() -> void:
	if key_owned or key_spawned: return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if rng.randf()>KEY_CHANCE and not "--all-forest-keys" in game._flags: return
	var trunks := get_tree().get_nodes_in_group("planes_tree_trunks")
	for attempt in 1000:
		var p := Vector2(rng.randf_range(10,250),rng.randf_range(-20,80))
		if not _key_clear(p, trunks): continue
		key.position = Map.ground_pos(p.x,p.y) + Vector3.UP * 0.12
		key_spawned = true
		break
	# A deterministic second pass prevents an unlucky random search losing the key.
	if not key_spawned:
		for x in range(10,250,3):
			for z in range(-20,80,3):
				var p := Vector2(x,z)
				if not _key_clear(p, trunks): continue
				key.position = Map.ground_pos(x,z) + Vector3.UP * 0.12
				key_spawned = true
				break
			if key_spawned: break
	refresh()

func _key_clear(p: Vector2, trunks: Array) -> bool:
	if not preload("res://scripts/planes_boundary.gd").contains(p) or not game.nature.clear_ground(p,true): return false
	for trunk in trunks:
		if p.distance_to(Vector2(trunk.position.x,trunk.position.z)) < 1.6: return false
	return true

func data(peer: int) -> Dictionary:
	if not people.has(peer): people[peer] = {"accepted":false,"hits":[],"claimed":false}
	return people[peer]

func nearby(p: Player) -> String:
	if not p.alive or p.downed: return ""
	if opened:
		var eye := p.global_position+Vector3.UP*Player.EYE
		for i in monitors.size():
			var offset := monitors[i].global_position-eye
			if offset.length()<1.8 and (-p.head.global_basis.z).dot(offset.normalized())>0.55: return "score_%d" % i
	if key_spawned and not key_owned and key.can_interact(p): return "key"
	if p.global_position.distance_to(door.global_position)<3: return "door"
	if not opened: return ""
	if p.global_position.distance_to(board.global_position)<3: return "quest"
	for id in loot_nodes:
		if not picked.has(id) and p.global_position.distance_to(loot_nodes[id].global_position)<2.3: return id
	return ""

func prompt(id: String) -> String:
	if id.begins_with("score_"): return Lang.t("[E] Reset score · Lane %d",[int(id.trim_prefix("score_"))+1])
	if id=="key": return "[E] Take key · Schützenhaus"
	if id=="door": return "[E] Open Schützenhaus" if key_owned else "Schützenhaus locked · find the key in the woodland"
	if id=="quest":
		var d := data(game.player.peer_id)
		return Lang.t("[E] 300 m challenge · %d / 6 targets",[d.hits.size()])
	return "[E] Collect ammunition cache" if id=="ammo" else Lang.t("[E] Collect %s",[Weapons.DEFS[id].name])

func request(id: String) -> void:
	if NetSession.enabled: NetSession.command("range",[id])
	else: game.hud.message(transact(game.player,id),4)

func transact(p: Player, id: String) -> String:
	if NetSession.is_client() or game.over or not game.started or nearby(p)!=id: return "Move closer."
	if id.begins_with("score_"):
		var lane := int(id.trim_prefix("score_"))
		if lane<0 or lane>=lane_scores.size(): return "Move closer."
		lane_scores[lane] = {"score":0,"hits":0,"last":0}
		refresh_scores()
		return Lang.t("Score reset · Lane %d",[lane+1])
	var w: Weapons = NetSession.world.weapons[p.peer_id] if NetSession.is_host() else game.weapons
	match id:
		"key": key_owned = true; Sfx.event(game,p.peer_id,"pickup")
		"door":
			if not key_owned: return "Find the Schützenhaus key in the woodland."
			opened = true
			Sfx.event(game,p.peer_id,"pickup")
		"quest":
			var d := data(p.peer_id)
			if d.claimed: return "300 m challenge completed."
			if not d.accepted:
				d.accepted = true
				Sfx.event(game,p.peer_id,"quest_accept")
				return "From inside the shooting house, hit all six targets with a sniper rifle. Return to this log for 350 R and class XP."
			if d.hits.size()<6: return Lang.t("Hit all six targets from inside this house: %d / 6",[d.hits.size()])
			d.claimed = true
			p.add_score(350)
			game.classes.quest(p.peer_id,"planes:range",350)
			game.achievements.event("planes_marksman")
			Sfx.event(game,p.peer_id,"quest_complete")
			return "300 m challenge completed · +350 R and class XP"
		"ammo":
			picked.ammo = true
			w.refill_all()
			Sfx.event(game,p.peer_id,"pickup")
		_:
			if id not in LOOT: return "Nothing to collect."
			picked[id] = true
			w.unlock(id)
			w.state[id].ammo = int(w.state[id].def.mag)
			w.state[id].reserve = w.reserve_limit(id)
			Sfx.event(game,p.peer_id,"weapon_pickup")
	refresh()
	return "Schützenhaus unlocked." if id=="door" else Lang.t("Collected: %s",["Schützenhaus key" if id=="key" else "Ammunition" if id=="ammo" else Weapons.DEFS[id].name])

func hit(collider: Object, peer: int, weapon: String, impact := Vector3.INF) -> bool:
	if NetSession.is_client() or not collider.has_meta("range_target"): return false
	var id := int(collider.get_meta("range_target"))
	var p: Player = NetSession.world.actor(peer) if NetSession.is_host() else game.player
	if not p: return false
	game.achievements.event("planes_targets")
	var at := house.to_local(p.global_position)
	if opened and absf(at.x)<7.6 and absf(at.z)<3.4 and at.y>=-0.2 and at.y<2.4 and impact.is_finite():
		var lane := int(collider.get_meta("range_lane",id))
		var local: Vector3 = collider.to_local(impact)
		var points := clampi(10-floori(Vector2(local.x,local.y).length()/0.06),1,10)
		lane_scores[lane].score += points
		lane_scores[lane].hits += 1
		lane_scores[lane].last = points
		refresh_scores()
	var d := data(peer)
	if opened and d.accepted and not d.claimed and weapon in ["marksman","titanbreaker","plasma_sniper"] and absf(at.x)<7.6 and absf(at.z)<3.4 and at.y>=-0.2 and at.y<2.4 and not id in d.hits:
		d.hits.append(id)
		p.hud.message(Lang.t("300 m challenge · %d / 6 targets",[d.hits.size()]),3)
	return true

func refresh_scores() -> void:
	for i in mini(monitors.size(),lane_scores.size()):
		var score := lane_scores[i]
		monitors[i].text = Lang.t("LANE %d\nSCORE %d\nHITS %d · LAST %d\n[E] Reset",[i+1,score.score,score.hits,score.last])

func refresh() -> void:
	if entrance_link: entrance_link.enabled = opened
	key.visible = key_spawned
	key.taken = not key_spawned or key_owned
	key.pickup_visual.visible = not key.taken
	for child in key.get_children():
		if child is StaticBody3D: child.collision_layer = 1 if key_spawned else 0
		if child is Label3D: child.visible = not key.taken
	door.visible = not opened
	door.collision_layer = 0 if opened else 1
	for shutter in shutters:
		shutter.visible = not opened
		shutter.collision_layer = 0 if opened else 1
	for id in loot_nodes: loot_nodes[id].visible = not picked.has(id)

func connect_navigation() -> void:
	# The narrow real doorway is smaller than Recast's padded agent diameter.
	# A doorway link guides actors through its centre over the physical ramp.
	if entrance_link: return
	entrance_link = NavigationLink3D.new()
	game.add_child(entrance_link)
	var outside := house.to_global(Vector3(-0.8,0,7))
	entrance_link.start_position = Map.ground_pos(outside.x,outside.z)
	entrance_link.end_position = house.to_global(Vector3(-0.8,0,1.0))
	entrance_link.bidirectional = true
	entrance_link.enabled = opened

func _process(_delta: float) -> void:
	if not game or not game.started or not game.survival_active: return
	if not NetSession.is_client() and game.day_night.night_index!=last_night:
		if last_night>=0: roll_key(); refresh()
		last_night = game.day_night.night_index

func snapshot() -> Dictionary:
	return {"key_spawned":key_spawned,"key_owned":key_owned,"at":key.position,"opened":opened,"people":people.duplicate(true),"picked":picked.duplicate(),"scores":lane_scores.duplicate(true)}

func apply_snapshot(s: Dictionary) -> void:
	if s.is_empty(): return
	key_spawned = s.key_spawned; key_owned = s.key_owned; key.position = s.at
	opened = s.opened; people = s.people.duplicate(true); picked = s.picked.duplicate()
	if s.has("scores"):
		lane_scores.assign(s.scores.duplicate(true))
		refresh_scores()
	refresh()

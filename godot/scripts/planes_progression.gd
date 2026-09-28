extends Progression
## A run-local economy. Forest catalogues supply prices; field quests have no hut dependencies.
const SITES := {"camp":Vector2(22,3),"mechanic":Vector2(27,13),"secret":Vector2(151,-7)}
const FIELD_QUESTS := {
	"welcome":{"npc":"camp","name":"A place of your own","desc":"Choose your ground. Buy and place two defence kits.","goal":"built_wall","count":2,"reward":90,"wave":0},
	"bouquet":{"npc":"camp","name":"Colour in the fields","desc":"Collect six marked wildflower bundles on the meadow paths.","goal":"flowers","count":6,"reward":120,"wave":1},
	"engineer":{"npc":"mechanic","name":"Your first strongpoint","desc":"Place a tower using T. Towers can stand anywhere suitable.","goal":"built","count":1,"reward":100,"wave":1},
	"watch":{"npc":"camp","name":"Open sky, steady hands","desc":"Defeat thirty zombies. The camp does not need defending.","goal":"kills","count":30,"reward":120,"wave":2},
	"forage":{"npc":"secret","name":"Under the canopy","desc":"Collect four marked mushroom baskets in the woodland.","goal":"mushrooms","count":4,"reward":160,"wave":3},
	"repair":{"npc":"mechanic","name":"Make it last","desc":"Repair three damaged fortifications.","goal":"repairs","count":3,"reward":150,"wave":4},
	"precision":{"npc":"secret","name":"Quiet work","desc":"Defeat twenty enemies with headshots.","goal":"headshots","count":20,"reward":200,"wave":5},
	"brutes":{"npc":"secret","name":"Heavy footsteps","desc":"Defeat eight brutes across the survival waves.","goal":"brutes","count":8,"reward":260,"wave":10},
	"veteran":{"npc":"camp","name":"The long harvest","desc":"Survive fifteen waves on your chosen ground.","goal":"waves","count":15,"reward":300,"wave":15}
}
var field_counts := {}
var accepted := {}
var claimed := {}
var kit_stock := {"palisade":0,"sandbags":0}
var discovered_secret := false
var field_panel: PanelContainer
var field_rows: VBoxContainer
var collectibles: Array[Dictionary] = []
var sample_time := 0.0
var nearest_collectible := -1
var nearest_wild_plant := -1

func setup(main: Node) -> void:
	game = main
	layer = 8
	rare_market = load("res://scripts/rare_market.gd").new()
	rare_market.game = game
	add_child(rare_market)
	rare_market.set_physics_process(false)
	for id in SITES:
		var npc := WorldNpc.new()
		game.add_child(npc)
		npc.setup(id,game)
		npc.position = Map.ground_pos(SITES[id].x,SITES[id].y)
		npcs[id] = npc
	var fire := Foliage.campfire(Map.ground_pos(18,11))
	game.add_child(fire)
	field_panel = PanelContainer.new()
	add_child(field_panel)
	field_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	field_panel.offset_left = -350; field_panel.offset_right = 350
	field_panel.offset_top = -290; field_panel.offset_bottom = 290
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.045,0.04,0.98)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	field_panel.add_theme_stylebox_override("panel",style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	field_panel.add_child(scroll)
	field_rows = VBoxContainer.new()
	field_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_rows.add_theme_constant_override("separation",9)
	scroll.add_child(field_rows)
	field_panel.hide()
	_spawn_collectibles()

func reset_run() -> void:
	close()
	field_counts.clear(); accepted.clear(); claimed.clear()
	kit_stock = {"palisade":0,"sandbags":0}
	discovered_secret = false
	if game.nature: game.nature.reset_harvest()
	rare_market.people.clear()
	for item in collectibles:
		item.taken = false
		item.node.show()

func close_enough(p: Player, id: String) -> bool:
	return npcs.has(id) and p.alive and p.global_position.distance_to(npcs[id].global_position)<4.5

func nearest(p: Player) -> String:
	for id in SITES:
		if close_enough(p,id): return id
	return ""

func event(kind: String) -> void:
	field_counts[kind] = int(field_counts.get(kind,0))+1

func has_available_quest(npc_id: String) -> bool:
	for id in FIELD_QUESTS:
		if FIELD_QUESTS[id].npc==npc_id and not accepted.has(id) and not claimed.has(id): return true
	return false

func has_ready_quest(npc_id: String) -> bool:
	for id in accepted:
		if FIELD_QUESTS[id].npc==npc_id and quest_ready(id) and not claimed.has(id): return true
	return false

func quest_ready(id: String) -> bool:
	if not accepted.has(id): return false
	var q: Dictionary = FIELD_QUESTS[id]
	var wave: int = game.waves.completed if game.waves else 0
	return wave>=int(q.wave) and int(field_counts.get(q.goal,0) if q.goal!="waves" else wave)>=int(q.count)

func open_field(id: String) -> void:
	if not game.survival_active:
		game.hud.message("Start survival from the pause menu to trade and build.",4)
		return
	if not close_enough(game.player,id): return
	shop = id; is_open = true
	if id=="secret": discovered_secret = true
	game.player.active = false
	game.player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	field_panel.show()
	refresh_field()

func close() -> void:
	is_open = false
	if field_panel: field_panel.hide()
	if game and game.player and not game.over and not get_tree().paused:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _field_row(text: String, action: Callable = Callable()) -> void:
	if action.is_valid():
		var button := Button.new()
		button.text = text
		button.pressed.connect(action)
		field_rows.add_child(button)
	else:
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 620
		field_rows.add_child(label)

func refresh_field(message := "") -> void:
	for child in field_rows.get_children():
		field_rows.remove_child(child); child.queue_free()
	_field_row(Lang.t("%s  |  %d R",[NPCS[shop].name,game.player.score]))
	if not message.is_empty(): _field_row(Lang.text(message))
	var tabs := HBoxContainer.new()
	field_rows.add_child(tabs)
	for tab in ["Trade","Quests"]:
		var button := Button.new()
		button.text = tab
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): page = tab; refresh_field())
		tabs.add_child(button)
	if page=="Trade":
		if shop=="mechanic":
			_field_row("Carry kits anywhere. B opens your kit inventory; R rotates, E places.")
			for id in ["palisade","sandbags"]:
				_field_row(Lang.t("%s kit · %d R · carried: %d",[id,kit_price(id),kit_stock[id]]),func(): refresh_field(buy_kit(id)))
			for spec in Skills.UPGRADES:
				_field_row(Lang.t("%s | %d R",[spec.name,Skills.training_cost(spec,game.skills.levels.get(spec.id,0))]),func(): refresh_field(game.skills.purchase(game.player,game.weapons,spec.id)))
			for index in game.barricades.size():
				var bar: Barricade = game.barricades[index]
				_field_row(Lang.t("Fortification #%d | tier %d | Upgrade",[index+1,bar.level]),func(): refresh_field(game.field_building.upgrade_bar(index)))
			for id in game.defences.towers:
				var tower: DefenceTower = game.defences.towers[id]
				_field_row(Lang.t("%s #%d · Tier %d · Upgrade %d R",[tower.spec().name,id,tower.level,tower.upgrade_cost()]),func(): refresh_field(game.defences.maintain(game.player,id,"upgrade",true)))
		else:
			_field_row("Ammunition refill",func(): refresh_field(buy_supply("ammo")))
			_field_row("Field dressing · 35 R",func(): refresh_field(buy_supply("health")))
			_field_row("Grenade · 30 R",func(): refresh_field(buy_supply("grenade")))
			for id in GOODS:
				if GOODS[id].npc!=shop: continue
				var owned: bool = game.weapons.unlocked.get(id,false)
				_field_row(Lang.t("%s · %d R · wave %d%s",[Weapons.DEFS[id].name,GOODS[id].price,GOODS[id].wave," · owned" if owned else ""]),func(): refresh_field(buy_weapon(id)))
		if shop in ["mechanic","secret"]:
			var wid: String = game.weapons.current
			_field_row(Lang.t("Weapon mods · %s",[Weapons.DEFS[wid].name]))
			for id in Weapons.Mods.DEFS:
				var spec: Dictionary = Weapons.Mods.DEFS[id]
				if spec.npc==shop and Weapons.Mods.compatible(id,wid,Weapons.DEFS[wid]):
					_field_row(Lang.t("%s · %d R · wave %d",[spec.name,spec.price,spec.level]),func(): refresh_field(trade_mod(game.player,shop,id,wid)))
	else:
		_field_row("QUESTS · accept, then return for the reward")
		for id in FIELD_QUESTS:
			var q: Dictionary = FIELD_QUESTS[id]
			if q.npc!=shop: continue
			var state := "claimed" if claimed.has(id) else "ready" if quest_ready(id) else "active" if accepted.has(id) else "accept"
			var progress: int = game.waves.completed if q.goal=="waves" else int(field_counts.get(q.goal,0))
			_field_row(Lang.t("%s · %s · %d/%d · %d R\n%s (wave %d)",[q.name,state,progress,q.count,q.reward,q.desc,q.wave]),func(): refresh_field(quest_action(id)))
	_field_row("Close [Esc]",close)

func kit_price(id: String) -> int:
	return SandbagLine.DEPLOY_COST if id=="sandbags" else Barricade.COST_BUILD

func buy_kit(id: String) -> String:
	if not game.survival_active: return "Building unavailable."
	if not kit_stock.has(id) or not close_enough(game.player,"mechanic"): return "Go to Mechanic."
	if kit_stock.palisade+kit_stock.sandbags+game.barricades.size()>=40: return "Maximum 40 fortifications and carried kits."
	if game.player.score<kit_price(id): return "Not enough Rem Dollars."
	game.player.add_score(-kit_price(id)); kit_stock[id] += 1
	return "Kit packed. Press B at your chosen position."

func buy_weapon(id: String) -> String:
	if not game.survival_active: return "Building unavailable."
	if not GOODS.has(id) or not close_enough(game.player,GOODS[id].npc): return "Go to the trader."
	if game.weapons.unlocked.get(id,false): return "You already own this weapon."
	if game.waves.wave<int(GOODS[id].wave): return "Survive until the required wave."
	if game.player.score<int(GOODS[id].price): return "Not enough Rem Dollars."
	game.player.add_score(-int(GOODS[id].price))
	game.weapons.unlock(id)
	game.weapons.state[id].ammo = int(Weapons.DEFS[id].mag)
	game.weapons.state[id].reserve = int(Weapons.DEFS[id].mag)*3
	return "Weapon purchased. Use the mouse wheel to equip."

func buy_supply(id: String) -> String:
	if not game.survival_active: return "Building unavailable."
	if not close_enough(game.player,shop) or shop not in ["camp","secret"]: return "Go to Vendor."
	if id=="ammo":
		var quote := refill_quote(game.player)
		if int(quote.rounds)==0: return "No refill needed or insufficient funds."
		game.player.add_score(-int(quote.cost))
		for wid in quote.items:
			game.weapons.state[wid].ammo += int(quote.items[wid][0])
			game.weapons.state[wid].reserve += int(quote.items[wid][1])
		game.weapons.update_hud()
		return "Ammunition purchased."
	var price := 35 if id=="health" else 30
	if id not in ["health","grenade"]: return "Unknown supplies."
	if id=="health" and game.player.hp>=game.player.max_hp: return "Health already full."
	if id=="grenade" and game.weapons.grenades>=game.weapons.grenades_max: return "Grenade pouch full."
	if game.player.score<price: return "Not enough Rem Dollars."
	game.player.add_score(-price)
	if id=="health":
		game.player.hp = minf(game.player.max_hp,game.player.hp+50)
		game.hud.set_health(game.player.hp)
	else: game.weapons.grenades += 1
	game.weapons.update_hud()
	return "Supplies purchased."

func quest_action(id: String) -> String:
	if not game.survival_active: return "Building unavailable."
	if not FIELD_QUESTS.has(id) or not close_enough(game.player,FIELD_QUESTS[id].npc): return "Return to the quest giver."
	if claimed.has(id): return "Reward already claimed."
	if not accepted.has(id):
		accepted[id] = true
		return "Quest accepted. Earlier progress this run counts."
	if not quest_ready(id): return "Objectives not completed yet."
	claimed[id] = true
	game.player.add_score(int(FIELD_QUESTS[id].reward))
	return "Quest completed. Reward received."

func _spawn_collectibles() -> void:
	var locations := [Vector2(-90,40),Vector2(-70,48),Vector2(-48,58),Vector2(15,46),Vector2(70,37),Vector2(115,53),Vector2(-145,45),Vector2(45,165),Vector2(160,160),Vector2(-180,105),Vector2(48,12),Vector2(90,4),Vector2(132,-3),Vector2(173,-27),Vector2(224,-55),Vector2(195,65)]
	for i in locations.size():
		var p: Vector2 = locations[i]
		var model_id := "mushroom_cluster" if i>=10 else "field_flower_3"
		var model: Node3D = load("res://assets/models/%s.glb" % model_id).instantiate()
		var node := Node3D.new()
		game.add_child(node)
		node.add_child(model)
		Weapons._fit_height(model,0.45 if i>=10 else 0.7)
		node.position = Map.ground_pos(p.x,p.y)
		for mesh in node.find_children("*","MeshInstance3D",true,false):
			mesh.visibility_range_end = 55
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var marker := Label3D.new()
		marker.text = "✦"
		marker.font_size = 38
		marker.pixel_size = 0.009
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.position = Vector3.UP*1.0
		marker.visibility_range_end = 22
		node.add_child(marker)
		collectibles.append({"node":node,"kind":"mushrooms" if i>=10 else "flowers","taken":false,"at":p,"marker":marker})

func collect(index: int) -> bool:
	if index<0 or index>=collectibles.size() or not game.survival_active: return false
	var item: Dictionary = collectibles[index]
	if item.taken or game.player.global_position.distance_to(Map.ground_pos(item.at.x,item.at.y))>2.5: return false
	item.taken = true; item.node.hide(); event(item.kind)
	game.hud.message(Lang.t("Collected: %s (%d)",[item.kind,field_counts[item.kind]]),2)
	return true

func collect_wild(index: int) -> bool:
	var kind: String = game.nature.harvest(index)
	if kind.is_empty(): return false
	event(kind)
	game.hud.message(Lang.t("Collected: %s (%d)",[kind,field_counts[kind]]),2)
	return true

func sample_collectibles() -> void:
	nearest_collectible = -1
	var distance := 2.5
	for i in collectibles.size():
		var item: Dictionary = collectibles[i]
		var d: float = game.player.position.distance_to(Map.ground_pos(item.at.x,item.at.y))
		if not item.taken and d<distance:
			distance = d; nearest_collectible = i
	nearest_wild_plant = game.nature.nearest_plant(game.player.position) if game.nature else -1

func _process(delta: float) -> void:
	if not game or not game.ready_for_exploration: return
	if is_open and (not game.player.alive or game.over): close()
	sample_time -= delta
	if sample_time>0: return
	sample_time = 0.15
	sample_collectibles()
	for i in collectibles.size():
		var item: Dictionary = collectibles[i]
		var quest := "forage" if item.kind=="mushrooms" else "bouquet"
		item.marker.visible = accepted.has(quest) and not claimed.has(quest)
	for id in npcs:
		npcs[id].quest_marker.visible = game.survival_active and (id!="secret" or discovered_secret) and has_ready_quest(id)
	if not game.player.active or (game.defences and (game.defences.placing or game.player.mounted_tower)) or (game.field_building and game.field_building.placing): return
	var id := nearest(game.player)
	if not id.is_empty(): game.hud.set_prompt("[E] " + str(NPCS[id].name))
	elif nearest_collectible>=0: game.hud.set_prompt("[E] Collect " + str(collectibles[nearest_collectible].kind))
	elif nearest_wild_plant>=0: game.hud.set_prompt(Lang.t("[E] Collect %s",["mushrooms" if game.nature.plants[nearest_wild_plant].woodland else "flowers"]))
	elif game.defences and game.defences.nearest(game.player): game.hud.set_prompt("[E] Operate tower · [R] Align · [F] Repair")
	elif game.field_building and game.field_building.nearest_bar(): game.hud.set_prompt("[E] Repair fortification · [B] Building kits")
	else: game.hud.set_prompt("")

func _unhandled_input(event_input: InputEvent) -> void:
	if not game or not game.ready_for_exploration or not game.player.active or game.player.downed: return
	if game.defences and (game.defences.placing or game.player.mounted_tower): return
	if game.field_building and game.field_building.placing: return
	if event_input is InputEventKey and event_input.pressed and not event_input.echo and event_input.physical_keycode==KEY_J:
		show_journal()
		get_viewport().set_input_as_handled()
		return
	if event_input.is_action_pressed("interact"):
		sample_collectibles()
		var id := nearest(game.player)
		if not id.is_empty(): open_field(id)
		elif nearest_collectible>=0: collect(nearest_collectible)
		elif nearest_wild_plant>=0: collect_wild(nearest_wild_plant)
		elif game.defences and game.defences.nearest(game.player): game.defences.request_mount(game.defences.nearest(game.player))
		elif game.field_building: game.field_building.repair_nearest()
		get_viewport().set_input_as_handled()

func show_journal() -> void:
	if not game.survival_active: return
	for child in field_rows.get_children():
		field_rows.remove_child(child); child.queue_free()
	_field_row("FIELD JOURNAL")
	_field_row("Meet Vendor and Mechanic at the fork. The Secret Vendor waits in the woodland. Accept tasks in person; return there for your rewards.")
	for id in accepted:
		var q: Dictionary = FIELD_QUESTS[id]
		var value: int = game.waves.completed if q.goal=="waves" else int(field_counts.get(q.goal,0))
		_field_row(Lang.t("%s · %d/%d · %s\n%s",[q.name,value,q.count,"claimed" if claimed.has(id) else "ready" if quest_ready(id) else "active",q.desc]))
	_field_row("Close [Esc]",close)
	is_open = true
	game.player.active = false
	game.player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	field_panel.show()

func mod_lock_reason(p: Player, id: String, wid: String) -> String:
	if not Weapons.Mods.DEFS.has(id) or not game.weapons.unlocked.get(wid,false): return "Weapon not available."
	if not Weapons.Mods.compatible(id,wid,Weapons.DEFS[wid]): return "Not compatible with this weapon."
	if game.waves.wave<int(Weapons.Mods.DEFS[id].level): return "Survive until the required wave."
	return ""

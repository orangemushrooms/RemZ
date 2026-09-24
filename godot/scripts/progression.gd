class_name Progression
extends CanvasLayer

const QUEST_MARKER_COLOR := Color(1.0, 0.78, 0.2)
const VendorGuide = preload("res://scripts/vendor_tutorial.gd")

# One authoritative catalogue is shared by the UI, solo game and host validation.
const NPCS := {
	"wanderer": {"name": "Mist Peddler", "role": "Wandering trader · Legendary rarities", "model": "npc_secret_trader", "height": 1.9, "pos": Vector2(-35, -55), "line": "Here today, among other trees tomorrow. What I bring rarely comes twice."},
	"ranger": {"name": "Mara", "role": "Forester · Forest quests", "model": "npc_mechanic", "height": 1.7, "pos": Vector2(-58.8, 63.0), "quests_only": true, "line": "Sit by the fire for a moment. The forest shelters us, but we have to look after it."},
	"camp": {"name": "Vendor", "role": "Weapons & supplies", "model": "npc_quartermaster", "height": 1.82, "pos": Vector2(4.0, -16.0), "line": "Stay alive. I trade with people who pull their weight."},
	"mechanic": {"name": "Mechanic", "role": "Defense & training", "model": "npc_mechanic", "height": 1.7, "pos": Vector2(-5, -24), "line": "A barrier holds them up. A properly aimed sentinel does the rest."},
	"secret": {"name": "Secret Vendor", "role": "Rare equipment", "model": "npc_secret_trader", "height": 1.9, "pos": Vector2(-100, -140), "line": "You found me. Now show me you can handle these weapons."},
}
const GOODS := {
	"hatchet": {"npc": "camp", "price": 180, "wave": 1, "quest": "arrival", "ammo": 0, "desc": "Sturdy forest axe. Slow swing, heavy impact, no ammo."},
	"revolver": {"npc": "camp", "price": 220, "wave": 1, "quest": "arrival", "ammo": 24, "desc": "Precise and economical. Six heavy rounds."},
	"smg": {"npc": "camp", "price": 400, "wave": 2, "quest": "watch", "ammo": 30, "desc": "Stops fast runners. High ammo consumption."},
	"shotgun": {"npc": "camp", "price": 340, "wave": 2, "quest": "arrival", "ammo": 28, "desc": "Strong close-range defense. Weak at a distance."},
	"ak47": {"npc": "camp", "price": 780, "wave": 4, "quest": "line", "chain": "assault", "ammo": 44, "desc": "Versatile assault rifle with heavy recoil."},
	"marksman": {"npc": "camp", "price": 680, "wave": 3, "quest": "silent_deal", "chain": "marksman", "ammo": 40, "desc": "Bolt-action rifle. Slow, precise and with strong penetration."},
	"lmg": {"npc": "secret", "price": 1350, "wave": 5, "quest": "supplies", "chain": "engineer", "ammo": 90, "desc": "60 rounds against the horde. Long reload."},
	"breacher": {"npc": "secret", "price": 1650, "wave": 6, "quest": "titan", "ammo": 70, "desc": "Semi-automatic assault shotgun. Close range only."},
	"titanbreaker": {"npc": "secret", "price": 2400, "wave": 9, "quest": "titan", "chain": "marksman", "ammo": 110, "desc": "Titanbreaker .50. 75% bonus damage against titans, expensive ammo."},
	# Erweiterung September 2026. "ammo" ist der Preis fuer zwei Magazine; die Munitionskosten pro
	# 1000 Schaden bleiben im Korridor der bestehenden Waffen (13-33 R), die Leuchtpistole und die
	# Graviton-Kanone bewusst darueber - sie zahlen fuer Licht und Flaeche, nicht fuer Schaden.
	"flare_pistol": {"npc": "camp", "price": 220, "wave": 2, "quest": "arrival", "ammo": 10, "desc": "Sets targets on fire and lights up the area for eight seconds. One shot per load."},
	"deagle": {"npc": "camp", "price": 560, "wave": 4, "quest": "steady_aim", "ammo": 40, "desc": "Heavy .50 pistol. Kills runners with one hit, but brutal recoil."},
	"lever_rifle": {"npc": "camp", "price": 640, "wave": 5, "quest": "steady_aim", "ammo": 30, "desc": "Lever-action rifle with a 3x scope. Faster than the bolt-action rifle, long reload."},
	"mac10": {"npc": "camp", "price": 600, "wave": 5, "quest": "night_shift", "ammo": 34, "desc": "40 rounds, barely any recoil, muffled report. Close range only, wide spread."},
	"cryo_smg": {"npc": "secret", "price": 1000, "wave": 8, "quest": "titan", "ammo": 32, "desc": "Chills targets, freezes them and deals 40% more damage to frozen ones."},
	"plasma_sniper": {"npc": "secret", "price": 1750, "wave": 10, "quest": "silent_deal", "chain": "marksman", "ammo": 60, "desc": "Energy rifle with 5x optics. Overheats instead of reloading and cools itself down."},
	"minigun": {"npc": "secret", "price": 2100, "wave": 11, "quest": "clockwork", "ammo": 190, "desc": "150-round belt, highest rate of fire in the camp. Very heavy, has to spin up, no scope."},
	"graviton_cannon": {"npc": "secret", "price": 3000, "wave": 13, "quest": "giant_debt", "ammo": 120, "desc": "Six meters of area damage and 140% bonus damage against titans. Only twelve energy cells."},
}
const QUESTS := {
	"drone_training": {"min_level": 5, "min_wave": 5, "waves_after_accept": 0, "npc": "mechanic", "name": "First Flight", "requires": "", "reward": 150, "desc": "Use the drone station upstairs in the forest hut (key required). Fly 150 m and defeat 5 zombies with the Kestrel as a team. E at the station, then Ready to fly. Space/Ctrl: climb/descend. R: return. Earlier flights this round count. Return to Mechanic for your reward.", "goals": {"drone_scout_meters": 150, "drone_scout_kills": 5}},
	"drone_patrol": {"min_level": 10, "min_wave": 10, "waves_after_accept": 0, "npc": "mechanic", "name": "Armed Patrol", "requires": "drone_training", "reward": 250, "desc": "Fly 400 m and defeat 15 zombies with the Viper as a team. Available when wave 10 starts. Earlier flights this round count. Return to Mechanic for your reward.", "goals": {"drone_viper_meters": 400, "drone_viper_kills": 15}},
	"drone_air_support": {"min_level": 15, "min_wave": 15, "waves_after_accept": 0, "npc": "mechanic", "name": "Heavy Air Support", "requires": "drone_patrol", "reward": 400, "desc": "Fly 600 m and defeat 30 zombies with the Tempest as a team. Available when wave 15 starts. Earlier flights this round count. Return to Mechanic for your reward.", "goals": {"drone_tempest_meters": 600, "drone_tempest_kills": 30}},
	"forest_basket": {"min_level": 2, "waves_after_accept": 1,"npc": "ranger", "name": "What the Forest Gives Us", "requires": "arrival", "reward": 90, "desc": "Collect five porcini as a team. Mara shows you what to look out for in the forest. Mushrooms you already collected count, and you may keep them.", "goals": {"edible_mushrooms": 5}},
	"restless_paths": {"min_level": 5, "waves_after_accept": 1,"npc": "ranger", "name": "Unrest on the Paths", "requires": "forest_basket", "reward": 140, "desc": "Defeat twelve runners as a team. Their quick footsteps give nobody any rest, not even here by the small fire.", "goals": {"runner_kills": 12}},
	"forest_watch": {"min_level": 8, "waves_after_accept": 1,"npc": "ranger", "name": "While the Fire Burns", "requires": "restless_paths", "reward": 220, "desc": "Survive wave 6 and defeat 80 zombies in total. Then return to Mara at the small fire pit.", "goals": {"waves": 6, "kills": 80}},
	"arrival": {"min_level": 1, "waves_after_accept": 0,"npc": "camp", "name": "By the Fire", "requires": "", "reward": 20, "desc": "Vendor introduces you to the inventory, trading, tower building and barricades. Learn the basics, then collect your reward."},
	"watch": {"min_level": 2, "waves_after_accept": 1,"npc": "mechanic", "name": "The First Sentinel", "requires": "arrival", "reward": 110, "desc": "Build a barricade and a tower. Then re-aim the tower. T: preview · R/mouse wheel: rotate · E: confirm. At the tower R: aim, E: climb in, F: repair."},
	"line": {"min_level": 2, "waves_after_accept": 1,"npc": "camp", "name": "Hold the Line", "requires": "arrival", "reward": 140, "desc": "Survive two waves as a team and defeat 30 zombies. Return to Vendor."},
	"supplies": {"min_level": 4, "waves_after_accept": 1,"npc": "mechanic", "name": "The Lost Delivery", "requires": "watch", "reward": 180, "desc": "The toolbox got lost somewhere in the area. Where it lies changes every round and is marked on the map once you accept. Recover the delivery and return to Mechanic."},
	"titan": {"min_level": 7, "waves_after_accept": 1,"npc": "secret", "name": "What Lurks in the Field", "requires": "supplies", "reward": 300, "desc": "Defeat a field titan together. They appear from wave 6. Then collect your reward from the Secret Vendor."},
	"steady_aim": {"min_level": 2, "waves_after_accept": 1,"npc": "camp", "name": "A Steady Hand", "requires": "arrival", "reward": 90, "desc": "Kill 15 zombies with headshots as a team. Every well-aimed hit saves supplies.", "goals": {"headshot_kills": 15}},
	"marksman_training": {"min_level": 5, "waves_after_accept": 1,"npc": "camp", "name": "Precision Under Pressure", "requires": "steady_aim", "reward": 140, "desc": "Get 25 headshot kills as a team and survive wave 3. Pistol and revolver are enough. Then Vendor sends you to the final test with the Secret Vendor.", "goals": {"headshot_kills": 25, "waves": 3}},
	"night_shift": {"min_level": 5, "waves_after_accept": 1,"npc": "camp", "name": "The Long Shift", "requires": "line", "reward": 160, "desc": "Survive wave 4 as a team. Vendor needs people who stay on after the first onslaught.", "goals": {"waves": 4}},
	"last_light": {"min_level": 11, "waves_after_accept": 2,"npc": "camp", "name": "The Last Light", "requires": "night_shift", "reward": 240, "desc": "Survive wave 8 and defeat 150 zombies in total. Keep the camp alive.", "goals": {"waves": 8, "kills": 150}},
	"crossfire": {"min_level": 4, "waves_after_accept": 1,"npc": "mechanic", "name": "Crossfire", "requires": "watch", "reward": 100, "desc": "Have two active gun turrets standing at the same time. Both must still stand when you turn in.", "goals": {"active_towers": 2}},
	"reinforced": {"min_level": 7, "waves_after_accept": 1,"npc": "mechanic", "name": "Better Safe Than Sorry", "requires": "crossfire", "reward": 140, "desc": "Reinforce two barricades to at least tier 2. Keep both standing until you turn in.", "goals": {"reinforced_barricades": 2}},
	"clockwork": {"min_level": 10, "waves_after_accept": 2,"npc": "mechanic", "name": "Like Clockwork", "requires": "reinforced", "reward": 220, "desc": "Upgrade a gun turret to tier 3 and let your towers defeat 40 zombies in total. The upgraded tower must still be standing.", "goals": {"elite_towers": 1, "tower_kills": 40}},
	"silent_deal": {"min_level": 8, "waves_after_accept": 1,"npc": "secret", "name": "A Discreet Job", "requires": "marksman_training", "reward": 180, "desc": "Get 40 headshot kills as a team. Collect your Marksman permit from the Secret Vendor. It allows you to buy precision rifles; waves, extra quests and the price still apply.", "goals": {"headshot_kills": 40}},
	"giant_debt": {"min_level": 11, "waves_after_accept": 1,"npc": "secret", "name": "The Giants' Debt", "requires": "titan", "reward": 260, "desc": "Defeat three field titans in total. Some debts can only be paid with courage.", "goals": {"titans": 3}},
	"nameless": {"min_level": 16, "waves_after_accept": 2,"npc": "secret", "name": "A Name No One Knows", "requires": "giant_debt", "reward": 380, "desc": "Survive wave 12 and defeat five field titans in total. After that we speak as equals.", "goals": {"waves": 12, "titans": 5}},
}
const QUEST_CHAINS := {
	"arrival": {"name": "Arrival", "quests": ["arrival"]},
	"assault": {"name": "Assault", "quests": ["line", "night_shift"]},
	"marksman": {"name": "Marksman", "quests": ["steady_aim", "marksman_training", "silent_deal"]},
	"engineer": {"name": "Defense Engineering", "quests": ["watch", "crossfire", "reinforced", "clockwork"]},
	"forest": {"name": "Forest Watch", "quests": ["forest_basket", "restless_paths", "forest_watch"]},
	"supplies": {"name": "Supply", "quests": ["supplies"]},
	"titans": {"name": "Titan Hunt", "quests": ["titan", "giant_debt", "nameless"]},
	"survival": {"name": "Protect the Camp", "quests": ["last_light"]},
	"drones": {"name": "Drone Operations", "quests": ["drone_training", "drone_patrol", "drone_air_support"]},
}
const GOAL_LABELS := {"drone_scout_meters": "Kestrel flight (m)", "drone_scout_kills": "Kestrel kills", "drone_viper_meters": "Viper flight (m)", "drone_viper_kills": "Viper kills", "drone_tempest_meters": "Tempest flight (m)", "drone_tempest_kills": "Tempest kills", "edible_mushrooms": "Porcini mushrooms", "runner_kills": "Runners", "headshot_kills": "Headshot kills", "waves": "Waves", "kills": "Zombies", "active_towers": "Active towers", "reinforced_barricades": "Barricades tier 2+", "elite_towers": "Towers tier 3", "tower_kills": "Tower kills", "titans": "Titans"}
const SKINS := {
	"forest": {"name": "Forest Camo", "price": 160, "npc": "camp", "quest": "line", "desc": "Moss, olive and dark earth. Purely cosmetic."},
	"bronze": {"name": "Soot Bronze", "price": 300, "npc": "secret", "quest": "supplies", "desc": "Blackened metal with bronze panels. Purely cosmetic."},
	"bone": {"name": "Titan Bone", "price": 480, "npc": "secret", "quest": "titan", "desc": "Pale bone stripes on dark steel. Purely cosmetic."},
}
var game: Node
var npcs: Dictionary = {}
var people: Dictionary = {}
var team := {"kills": 0, "titans": 0, "built": 0, "turned": 0, "cache": false}
var cache_node: Node3D
var cache_ready := false
var is_open := false
var shop := ""
var page := "Trade"
var panel: Control
var rows: VBoxContainer
var title: Label
var subtitle: Label
var balance: Label
const GAIN_GOLD := Color(1.0, 0.79, 0.33)
const GAIN_RED := Color(1.0, 0.47, 0.36)
const GAIN_SECONDS := 1.25

var status: Label
var _gain_popup: Label
var _gain_t := 0.0
var _gain_at := Vector2.ZERO
var _balance_pulse := 0.0
var tracker: RichTextLabel
var tutorial: Label
var vendor_guide: VendorGuide
var _arrival_guide_read := false
var _arrival_guide_pending := false
var _arrival_inventory_seen := false
var _arrival_build_menu_seen := false
var _tabs: Dictionary = {}
var _row_nodes: Array = []
var _row_index := 0
var _layout_key := ""
var _building_layout := false
var _refresh_time := 0.0
var _last_signature := ""
var _journal := true
const NPC_SIGHT_RANGE := 30.0
# Exploration belongs to this local player, never to the host's shared quest snapshot.
var _seen_npcs: Dictionary = {}
var rare_market: Node
var notifications: Control
var _notification_baseline_pending := false

# The original quests predate the data-driven goal lists. Keep their completion
# rules in one place so notifications and reward eligibility use the same goals.
const LEGACY_GOALS := {
	"arrival": {"arrival": 1},
	"watch": {"built": 1, "turned": 1, "built_barricades": 1},
	"line": {"waves": 2, "kills": 30},
	"supplies": {"cache": 1},
	"titan": {"titans": 1},
}
const LEGACY_GOAL_LABELS := {"arrival": "Meet Vendor", "built": "Build a tower",
	"turned": "Aim a tower", "built_barricades": "Build a barricade", "cache": "Recover the delivery"}

func has_seen_npc(id: String) -> bool:
	return _seen_npcs.get(id, false)

func _discover_visible_npcs() -> void:
	if not game.started or game.over or not game.player.active: return
	var camera: Camera3D = game.player.camera
	if not camera.is_current(): return
	var eye := camera.global_position
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	for id in npcs:
		if has_seen_npc(id): continue
		var npc: WorldNpc = npcs[id]
		if not npc.is_visible_in_tree(): continue
		for height: float in [1.0, float(NPCS[id].height) * 0.9]:
			var target := npc.global_position + Vector3.UP * height
			if eye.distance_squared_to(target) > NPC_SIGHT_RANGE * NPC_SIGHT_RANGE or not camera.is_position_in_frustum(target): continue
			var query := PhysicsRayQueryParameters3D.create(eye, target, 1 | 8, [game.player.get_rid()])
			var hit := space.intersect_ray(query)
			if hit.is_empty() or hit.collider == npc.body:
				_seen_npcs[id] = true
				break

var _tower_tutorial_remaining := 12.0

static func clear_space() -> void:
	# Deterministic clearings, before forests and navmesh are constructed on every peer.
	var centers: Array = []
	for spec in NPCS.values(): centers.append(spec.pos)
	for items: Array in [Map.TREES, Map.SHRUBS, Map.FERNS, Map.LOGS]:
		for i in range(items.size() - 1, -1, -1):
			var p := Vector2(items[i][0], items[i][1])
			for center: Vector2 in centers:
				if p.distance_to(center) < 4.0:
					items.remove_at(i)
					break

func setup(main: Node) -> void:
	game = main
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in NPCS:
		var npc := WorldNpc.new()
		game.add_child(npc)
		npc.setup(id, game)
		npcs[id] = npc
	rare_market = preload("res://scripts/rare_market.gd").new()
	rare_market.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(rare_market)
	rare_market.setup(game, npcs.wanderer)
	cache_node = Node3D.new()
	cache_node.hide() # Position is chosen once the navigation map is ready.
	cache_node.add_to_group("render_dynamic")
	game.add_child(cache_node)
	var wood := DefenceTower.material(Color(0.23, 0.17, 0.08))
	DefenceTower.box(cache_node, Vector3(0.8, 0.6, 0.55), Vector3(0, 0.3, 0), wood)
	var band := DefenceTower.material(Color(0.62, 0.43, 0.12))
	for x in [-0.25, 0.25]:
		DefenceTower.box(cache_node, Vector3(0.07, 0.62, 0.57), Vector3(x, 0.31, 0), band)
	var marker := Label3D.new()
	marker.text = "DELIVERY · MECHANIC"
	marker.position.y = 1.1
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.font_size = 30
	marker.pixel_size = 0.006
	marker.visibility_range_end = 15
	cache_node.add_child(marker)
	_build_ui()
	notifications = preload("res://scripts/quest_notifications.gd").new()
	add_child(notifications)
	notifications.hide()

func data(peer: int) -> Dictionary:
	if not people.has(peer): people[peer] = {"accepted": {}, "accepted_wave": {}, "claimed": {}, "skins": {}, "discovered": false}
	return people[peer]

func local_data() -> Dictionary:
	return data(NetSession.local_id() if NetSession.enabled else game.player.peer_id)

func has_available_quest(npc_id: String) -> bool:
	var d := local_data()
	if npc_id == "secret" and not d.discovered: return false
	var peer: int = NetSession.local_id() if NetSession.enabled else game.player.peer_id
	for id in QUESTS:
		var quest: Dictionary = QUESTS[id]
		if quest.npc != npc_id or d.accepted.get(id, false) or d.claimed.get(id, false): continue
		if quest_lock_reason(peer, id).is_empty(): return true
	return false

func has_ready_quest(npc_id: String) -> bool:
	var d := local_data()
	if npc_id == "secret" and not d.discovered: return false
	for id in QUESTS:
		var quest: Dictionary = QUESTS[id]
		if quest.npc != npc_id or not d.accepted.get(id, false) or d.claimed.get(id, false): continue
		if not quest.requires.is_empty() and not d.claimed.get(quest.requires, false): continue
		if complete(id): return true
	return false

func has_claim(peer: int, quest: String) -> bool:
	return quest.is_empty() or data(peer).claimed.get(quest, false)

static func quest_chain(id: String) -> String:
	for chain in QUEST_CHAINS:
		if id in QUEST_CHAINS[chain].quests: return chain
	return ""

static func ordered_quests() -> Array:
	var ids: Array = []
	for chain in QUEST_CHAINS: ids.append_array(QUEST_CHAINS[chain].quests)
	return ids

func chain_complete(peer: int, chain: String) -> bool:
	for id in QUEST_CHAINS[chain].quests:
		if not has_claim(peer, id): return false
	return true

static func chain_unlocks(chain: String) -> String:
	var names := PackedStringArray()
	for id in GOODS:
		if GOODS[id].get("chain", "") == chain: names.append(Lang.t(Weapons.DEFS[id].name))
	return ", ".join(names)

static func quest_reference(id: String) -> String:
	return Lang.t("“%s” from %s", [QUESTS[id].name, NPCS[QUESTS[id].npc].name])

func next_quest_step(peer: int, id: String) -> String:
	var next := id
	while not QUESTS[next].requires.is_empty() and not has_claim(peer, QUESTS[next].requires):
		next = QUESTS[next].requires
	var action := Lang.t("accept")
	if mission_level() < int(QUESTS[next].min_level): action = Lang.t("unlocks at mission level %d (currently %d)", [QUESTS[next].min_level, mission_level()])
	elif QUESTS[next].has("min_wave") and maxi(game.waves.completed, int(game.waves.wave)) < int(QUESTS[next].min_wave):
		action = Lang.t("available from wave %d", [QUESTS[next].min_wave])
	if data(peer).accepted.get(next, false):
		action = Lang.t("collect reward") if complete(next, peer) else Lang.t("finish: %s", [quest_progress(next, peer)])
	return quest_reference(next) + " – " + action

func prerequisite_reason(peer: int, required: String) -> String:
	if has_claim(peer, required): return ""
	if has_claim(peer, QUESTS[required].requires):
		return Lang.t("Missing quest: %s.", [next_quest_step(peer, required)])
	return Lang.t("Missing quest: %s. Next step: %s.", [quest_reference(required), next_quest_step(peer, required)])

func chain_description(peer: int, chain: String, show_steps := true) -> String:
	var spec: Dictionary = QUEST_CHAINS[chain]
	var count := 0
	var steps := PackedStringArray()
	for id in spec.quests:
		var claimed := has_claim(peer, id)
		if claimed: count += 1
		steps.append(("✓ " if claimed else "") + quest_reference(id))
	var text := Lang.t("Quest line %s · %d/%d turned in", [spec.name, count, spec.quests.size()])
	if show_steps: text += "\n" + " → ".join(steps)
	var unlocks := chain_unlocks(chain)
	if not unlocks.is_empty():
		text += "\n" + Lang.t("%s: purchase permit for %s. The price and extra conditions still apply.", ["Unlocked" if count == spec.quests.size() else "On completion", unlocks])
	return text

func weapon_for(p: Player) -> Weapons:
	return NetSession.world.weapons[p.peer_id] if NetSession.is_host() else game.weapons

func choose_cache_position(random: RandomNumberGenerator) -> Vector3:
	var nav: RID = game.nav_region.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(nav) == 0: return Vector3.INF
	var start := NavigationServer3D.map_get_closest_point(nav, Map.ground_pos(Map.PLAYER_START.x, Map.PLAYER_START.y))
	var area := Map.BOUNDS.grow(-8.0)
	var clearance := CapsuleShape3D.new()
	clearance.radius = 0.85
	clearance.height = 1.8
	for attempt in 600:
		var candidate := Vector2(random.randf_range(area.position.x, area.end.x), random.randf_range(area.position.y, area.end.y))
		var projected := NavigationServer3D.map_get_closest_point(nav, Map.ground_pos(candidate.x, candidate.y))
		var point := Vector2(projected.x, projected.z)
		if point.distance_to(candidate) > 2.0 or not area.has_point(point): continue
		if point.distance_to(Map.FIRE) < 35.0 or Map.in_building(point.x, point.y, 3.0): continue
		if game.perimeter and game.perimeter.excludes_spawn(point): continue
		if not Map.POND.is_empty() and point.distance_to(Map.POND.pos) < float(Map.POND.r) + 4.0: continue
		if Map.ground_normal(point.x, point.y).y < 0.9: continue
		var ground := Map.ground_pos(point.x, point.y)
		if absf(projected.y - ground.y) > 1.2: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = clearance
		query.transform.origin = ground + Vector3.UP * 1.1
		query.collision_mask = 1 | 8
		if not game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
		var route := NavigationServer3D.map_get_path(nav, start, projected, true)
		if route.is_empty() or route[route.size()-1].distance_to(projected) > 0.8: continue
		return ground
	return Vector3.INF

func place_cache() -> bool:
	if cache_ready or NetSession.is_client(): return true
	var random := RandomNumberGenerator.new()
	random.randomize()
	var point := choose_cache_position(random)
	if not point.is_finite(): return false
	cache_node.global_position = point
	cache_ready = true
	cache_node.visible = not team.cache
	return true

func close_enough(p: Player, id: String) -> bool:
	if not p.alive or not game.started or game.over: return false
	var target: Vector3
	var body: Object = null
	if id == "cache":
		if not cache_ready or team.cache: return false
		target = cache_node.global_position + Vector3.UP * 0.6
	elif npcs.has(id):
		if not npcs[id].is_visible_in_tree(): return false
		target = npcs[id].global_position + Vector3.UP * 1.3
		body = npcs[id].body
	else: return false
	if p.camera.global_position.distance_to(target) > 3.5: return false
	var query := PhysicsRayQueryParameters3D.create(p.camera.global_position, target, 1 | 8, [p.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == body

func nearest(p: Player) -> String:
	var found := ""
	var distance := INF
	for id in npcs:
		var d: float = p.global_position.distance_squared_to(npcs[id].global_position)
		if d < distance and close_enough(p, id):
			distance = d
			found = id
	if not team.cache and close_enough(p, "cache"): return "cache"
	return found

func prompt(id: String) -> String:
	return "[E] Recover Mechanic's delivery" if id == "cache" else Lang.t("[E] %s · %s", [NPCS[id].name, NPCS[id].role])

func event(kind: String) -> void:
	if NetSession.is_client(): return
	if kind in ["kills", "titans", "built", "turned", "headshot_kills", "tower_kills", "edible_mushrooms", "runner_kills"]:
		team[kind] = int(team.get(kind, 0)) + 1

func goal_value(kind: String) -> int:
	if kind == "arrival": return 1
	if kind == "cache": return int(team.cache)
	if kind == "built_barricades":
		for barricade: Barricade in game.barricades:
			if barricade.level > 0: return 1
		return 0
	if kind == "waves": return game.waves.completed
	if kind == "reinforced_barricades":
		var count := 0
		for b: Barricade in game.barricades:
			if b.level >= 2 and b.hp > 0: count += 1
		return count
	if kind in ["active_towers", "elite_towers"]:
		var count := 0
		for tower in game.defences.towers.values():
			if is_instance_valid(tower) and tower.hp > 0 and (kind == "active_towers" or tower.level >= 3): count += 1
		return count
	return int(team.get(kind, 0))

func mission_level() -> int:
	return game.waves.completed + 1

func record_drone_flight(kind: String, meters: float) -> void:
	if NetSession.is_client() or kind not in ["scout", "viper", "tempest"]: return
	if not is_finite(meters) or meters <= 0: return
	var key := "drone_" + kind + "_meters"
	team[key] = float(team.get(key, 0.0)) + meters

func record_drone_kill(kind: String) -> void:
	if NetSession.is_client() or kind not in ["scout", "viper", "tempest"]: return
	var key := "drone_" + kind + "_kills"
	team[key] = int(team.get(key, 0)) + 1

func quest_lock_reason(peer: int, id: String) -> String:
	var missing := prerequisite_reason(peer, QUESTS[id].requires)
	if not missing.is_empty(): return missing
	var level := int(QUESTS[id].min_level)
	if mission_level() >= level and QUESTS[id].has("min_wave"):
		var wave := int(QUESTS[id].min_wave)
		var active_wave: Variant = game.waves.get("wave")
		if maxi(game.waves.completed, int(active_wave) if active_wave != null else 0) < wave:
			return Lang.t("Available from wave %d.", [wave])
	return Lang.t("Mission level %d required (currently %d). Survive wave %d.", [level, mission_level(), level - 1]) if mission_level() < level else ""

func required_completion_wave(peer: int, id: String) -> int:
	return int(data(peer).get("accepted_wave", {}).get(id, game.waves.completed)) + int(QUESTS[id].waves_after_accept)

func complete(quest: String, peer := -1) -> bool:
	if peer < 0: peer = game.player.peer_id
	if not QUESTS.has(quest): return false
	if not data(peer).accepted.get(quest, false): return false
	if not quest_lock_reason(peer, quest).is_empty(): return false
	if game.waves.completed < required_completion_wave(peer, quest): return false
	return _objectives_complete(quest)

func _objectives_complete(quest: String) -> bool:
	if not QUESTS.has(quest): return false
	var goals := objective_goals(quest)
	for kind in goals:
		if goal_value(kind) < int(goals[kind]): return false
	return not goals.is_empty()

func objective_goals(id: String) -> Dictionary:
	return QUESTS[id].get("goals", LEGACY_GOALS.get(id, {}))

func completed_milestones(id: String, peer: int) -> Dictionary:
	var achieved := {}
	var goals := objective_goals(id)
	for kind in goals:
		var target := int(goals[kind])
		if goal_value(kind) >= target:
			var label: String = GOAL_LABELS.get(kind, LEGACY_GOAL_LABELS.get(kind, kind))
			achieved[kind] = Lang.t("%s %d/%d", [label, target, target])
	var waves := int(QUESTS[id].waves_after_accept)
	if waves > 0 and game.waves.completed >= required_completion_wave(peer, id):
		achieved["accepted_waves"] = Lang.t("%d wave survived since accepting", [waves]) if waves == 1 else Lang.t("%d waves survived since accepting", [waves])
	return achieved

static func _goal_text(text: String, done: bool, rich: bool) -> String:
	return "[color=#79df96]" + text + "[/color]" if rich and done else text

func quest_progress(id: String, peer := -1, rich := false) -> String:
	if peer < 0: peer = game.player.peer_id
	var claimed := has_claim(peer, id)
	var text := _objective_progress(id, rich, claimed)
	if data(peer).accepted.get(id, false) and not claimed and int(QUESTS[id].waves_after_accept) > 0:
		var remaining := maxi(0, required_completion_wave(peer, id) - game.waves.completed)
		text += ("\n" if rich else " · ") + _goal_text(Lang.t("After accepting: survive %d more wave(s)", [remaining]), remaining == 0, rich)
	return text

func _objective_progress(id: String, rich := false, claimed := false) -> String:
	var parts := PackedStringArray()
	if QUESTS.has(id) and QUESTS[id].has("goals"):
		for kind in QUESTS[id].goals:
			var target := int(QUESTS[id].goals[kind])
			parts.append(_goal_text(Lang.t("%s %d/%d", [GOAL_LABELS[kind], target if claimed else mini(goal_value(kind), target), target]), claimed or goal_value(kind) >= target, rich))
	else:
		match id:
			"watch":
				var wall := claimed
				for barricade in game.barricades:
					if barricade.level > 0: wall = true
				parts.append(_goal_text(Lang.t("Tower %d/1", [1 if claimed else mini(team.built, 1)]), claimed or team.built > 0, rich))
				parts.append(_goal_text(Lang.t("Aim %d/1", [1 if claimed else mini(team.turned, 1)]), claimed or team.turned > 0, rich))
				parts.append(_goal_text(Lang.t("Build barricade %d/1", [int(wall)]), wall, rich))
			"line":
				parts.append(_goal_text(Lang.t("Waves %d/2", [2 if claimed else mini(game.waves.completed, 2)]), claimed or game.waves.completed >= 2, rich))
				parts.append(_goal_text(Lang.t("Zombies %d/30", [30 if claimed else mini(team.kills, 30)]), claimed or team.kills >= 30, rich))
			"supplies": parts.append(_goal_text(Lang.t("Delivery recovered") if claimed or team.cache else Lang.t("Search for the delivery at the map marker"), claimed or team.cache, rich))
			"titan": parts.append(_goal_text(Lang.t("Titans %d/1", [1 if claimed else mini(team.titans, 1)]), claimed or team.titans > 0, rich))
			_: parts.append(_goal_text(Lang.t("Meet Vendor at the campfire"), true, rich))
	return ("\n" if rich else " · ").join(parts)

func lock_reason(p: Player, id: String) -> String:
	var spec: Dictionary = GOODS[id]
	var chain: String = spec.get("chain", "")
	if not chain.is_empty() and not chain_complete(p.peer_id, chain):
		for quest in QUEST_CHAINS[chain].quests:
			if not has_claim(p.peer_id, quest):
				return Lang.t("Permit missing: quest line %s. Next step: %s.", [QUEST_CHAINS[chain].name, next_quest_step(p.peer_id, quest)])
	var missing := prerequisite_reason(p.peer_id, spec.quest)
	if not missing.is_empty(): return missing
	if game.waves.completed < int(spec.wave): return Lang.t("Survive wave %d (%d/%d)", [spec.wave, game.waves.completed, spec.wave])
	return ""

func mushroom_stock(p: Player) -> Dictionary:
	return game.inventory.mushrooms if p == game.player else NetSession.world.mushrooms.get(p.peer_id, {})

static func ammo_sale_price(id: String) -> int:
	return maxi(1, int((int(GOODS[id].ammo) if GOODS.has(id) else 12) * 0.2))

func refill_quote(p: Player) -> Dictionary:
	var w := weapon_for(p)
	var order: Array = [w.ammo_weapon()]
	var expensive: Array = []
	for wid in Weapons.ORDER:
		if wid in order or Weapons.is_melee(wid): continue
		# Rounds dearer than ten Rem Dollars go last, so a single heavy weapon cannot eat the
		# budget before every ordinary magazine is full again.
		if float(GOODS[wid].ammo if GOODS.has(wid) else 12) / maxf(1.0, float(Weapons.DEFS[wid].mag) * 2.0) > 10.0:
			expensive.append(wid)
		else:
			order.append(wid)
	order.append_array(expensive)
	var result := {"cost": 0, "full_cost": 0, "rounds": 0, "missing": 0, "items": {}}
	var budget := maxi(0, p.score)
	for wid in order:
		if Weapons.is_melee(wid) or not w.unlocked.get(wid, false): continue
		var magazine := int(Weapons.DEFS[wid].mag)
		var missing_mag := maxi(0, int(w.state[wid].def.mag) - int(w.state[wid].ammo))
		var missing_reserve := maxi(0, w.reserve_limit(wid) - int(w.state[wid].reserve))
		var missing := missing_mag + missing_reserve
		var price := int(GOODS[wid].ammo) if GOODS.has(wid) else 12
		result.missing += missing
		result.full_cost += ceili(float(missing * price) / (magazine * 2))
		var amount := mini(missing, floori(float(budget * magazine * 2) / price))
		if amount <= 0: continue
		var cost := ceili(float(amount * price) / (magazine * 2))
		var load := mini(amount, missing_mag)
		result.items[wid] = [load, amount - load]
		result.rounds += amount
		result.cost += cost
		budget -= cost
	return result

func sell(p: Player, npc: String, action: String, id: String) -> String:
	if npc not in ["camp", "secret"]: return "You can sell to Vendor and Secret Vendor."
	var w := weapon_for(p)
	var price := 0
	var label := ""
	match action:
		"sell_meat":
			var stock: Dictionary = game.hunting.stock(p.peer_id)
			if not game.hunting.FOOD.has(id) or int(stock.get(id, 0)) <= 0: return "You don't have this meat."
			price = int(game.hunting.FOOD[id].sell)
			label = game.hunting.FOOD[id].name
			stock[id] -= 1
		"sell_mushroom":
			var stock := mushroom_stock(p)
			if not Inventory.MUSHROOMS.has(id) or int(stock.get(id, 0)) <= 0: return "You don't have this mushroom."
			price = int(Inventory.MUSHROOMS[id].sell)
			label = Inventory.MUSHROOMS[id].name
			stock[id] -= 1
		"sell_grenade":
			if w.grenades <= 0: return "No grenade in your inventory."
			w.grenades -= 1
			price = 15
			label = "Hand grenade"
		"sell_ammo":
			if not Weapons.DEFS.has(id) or Weapons.is_melee(id) or not w.unlocked.get(id, false): return "Ammo not available."
			var amount := int(Weapons.DEFS[id].mag)
			if int(w.state[id].reserve) < amount: return "You need a full spare magazine to sell."
			w.state[id].reserve -= amount
			price = ammo_sale_price(id)
			label = Lang.t("%d %s rounds", [amount, Weapons.DEFS[id].name])
		"sell_weapon":
			if not GOODS.has(id) or not w.unlocked.get(id, false): return "This weapon cannot be sold."
			price = int(int(GOODS[id].price) * 0.35)
			label = Weapons.DEFS[id].name
			if w.current == id: w.set_weapon("pistol")
			if w._last_firearm == id: w._last_firearm = "pistol"
			w.unlocked[id] = false
			w.state[id].ammo = 0
			w.state[id].reserve = 0
			w.state[id].reloading = 0.0
			w.state[id].cooldown = 0.0
		_: return "Unknown sale action."
	p.add_score(price)
	w.update_hud()
	Sfx.event(self, p.peer_id, "purchase")
	return Lang.t("Sold: %s · +%d R", [label, price])

func mod_lock_reason(p: Player, id: String, wid: String) -> String:
	var w := weapon_for(p)
	if not Weapons.DEFS.has(wid) or not w.unlocked.get(wid, false): return "You don't own this weapon."
	if not Weapons.Mods.compatible(id, wid, Weapons.DEFS[wid]): return "Not compatible with this weapon."
	var spec: Dictionary = Weapons.Mods.DEFS[id]
	var reasons := PackedStringArray()
	if mission_level() < int(spec.level): reasons.append(Lang.t("Mission level %d needed (currently %d).", [spec.level, mission_level()]))
	var quest := prerequisite_reason(p.peer_id, spec.quest)
	if not quest.is_empty(): reasons.append(quest)
	return "\n".join(reasons)

func trade_mod(p: Player, npc: String, id: String, wid: String, remove := false) -> String:
	if npc not in ["mechanic", "secret"]: return "Weapon mods are sold by Mechanic and Secret Vendor."
	var w := weapon_for(p)
	if not Weapons.DEFS.has(wid) or not w.unlocked.get(wid, false): return "You don't own this weapon."
	var slot := id
	var mod_id := ""
	var cost := 0
	if remove:
		if slot not in Weapons.Mods.SLOTS or not w.mod_loadout.get(wid, {}).has(slot): return "No mod is mounted in this slot."
	else:
		if not Weapons.Mods.DEFS.has(id): return "Unknown weapon mod."
		var spec: Dictionary = Weapons.Mods.DEFS[id]
		if spec.npc != npc: return "This mod is not offered here."
		var reason := mod_lock_reason(p, id, wid)
		if not reason.is_empty(): return reason
		slot = spec.slot
		mod_id = id
		if w.mod_loadout.get(wid, {}).get(slot, "") == id: return "Already mounted."
		if not w.mod_owned.get(wid + ":" + id, false): cost = int(spec.price)
	if p.score < cost: return Lang.t("Not enough Rem Dollars: %d R needed.", [cost])
	var updated := w.mod_definition(wid, slot, mod_id)
	var overflow := maxi(0, int(w.state[wid].ammo) - int(updated.mag))
	if int(w.state[wid].reserve) + overflow > w.reserve_limit(wid): return "Reserve full. Use up some ammo before the magazine gets smaller."
	p.add_score(-cost)
	if not remove: w.mod_owned[wid + ":" + id] = true
	w.equip_mod(wid, slot, mod_id)
	Sfx.event(self, p.peer_id, "purchase")
	return "Mod removed; you keep it." if remove else Lang.t("Mounted: %s", [Weapons.Mods.DEFS[id].name])

func transact(p: Player, npc: String, action: String, id: String, extra := "") -> String:
	if npc == "wanderer" and action not in ["visit", "rare"]: return "Only rarities here."
	if NetSession.is_client(): return "The host confirms the trade."
	if not close_enough(p, npc): return "Go to the trader. You can only trade in person."
	if NPCS.get(npc, {}).get("quests_only", false) and action not in ["visit", "quest"]:
		return "Mara hands out forest quests. You get supplies from Vendor."
	var d := data(p.peer_id)
	var w := weapon_for(p)
	if npc == "secret": d.discovered = true
	if action.begins_with("sell_"): return sell(p, npc, action, id)
	match action:
		"firework":
			if npc != "camp": return "Fireworks are sold by Vendor at the campfire."
			return game.fireworks.buy(p, id)
		"visit": return ""
		"rare":
			if npc != "wanderer": return "Only the Mist Peddler carries these rarities."
			return rare_market.buy(p, id)
		"mod", "remove_mod": return trade_mod(p, npc, id, extra, action == "remove_mod")
		"autorefill":
			if npc not in ["camp", "secret"]: return "Autorefill is offered by Vendor and Secret Vendor."
			var refill := refill_quote(p)
			if refill.missing == 0: return "All magazines and ammo reserves are full."
			if refill.rounds == 0: return "Not enough Rem Dollars for ammo."
			p.add_score(-int(refill.cost))
			for wid in refill.items:
				w.state[wid].ammo += int(refill.items[wid][0])
				w.state[wid].reserve += int(refill.items[wid][1])
				w.state[wid].reloading = 0.0
			w.update_hud()
			Sfx.event(self, p.peer_id, "pickup")
			return Lang.t("Autorefill: +%d rounds · −%d R · %s", [refill.rounds, refill.cost, "all full" if refill.rounds == refill.missing else "partial refill within your balance"])
		"cache":
			if npc != "cache" or team.cache: return "The delivery has already been recovered."
			if not d.accepted.get("supplies", false): return "Mechanic knows who this delivery belongs to. Talk to her."
			team.cache = true
			cache_node.hide()
			Sfx.event(self, p.peer_id, "pickup")
			return "Delivery recovered. Return to Mechanic."
		"quest":
			if not QUESTS.has(id) or QUESTS[id].npc != npc: return "This quest belongs to another trader."
			var q: Dictionary = QUESTS[id]
			if d.claimed.get(id, false): return "Quest reward already collected."
			var missing := quest_lock_reason(p.peer_id, id)
			if not missing.is_empty(): return missing
			if not d.accepted.get(id, false):
				d.accepted[id] = true
				if not d.has("accepted_wave"): d.accepted_wave = {}
				d.accepted_wave[id] = game.waves.completed
				Sfx.event(self, p.peer_id, "quest_accept")
				return Lang.t("Quest accepted: %s", [q.name])
			if not complete(id, p.peer_id): return Lang.t("Quest not completed yet. %s", [quest_progress(id, p.peer_id)])
			d.claimed[id] = true
			p.add_score(int(q.reward))
			if NetSession.enabled:
				NetSession.feedback(p.peer_id, "quest_complete", [id])
			else:
				notifications.rewarded(id)
			var chain := quest_chain(id)
			if not chain.is_empty() and chain_complete(p.peer_id, chain) and not chain_unlocks(chain).is_empty():
				return Lang.t("Quest line %s completed · +%d R · Purchase permit: %s", [QUEST_CHAINS[chain].name, q.reward, chain_unlocks(chain)])
			return Lang.t("Quest completed · +%d R · %s", [q.reward, q.name])
		"weapon":
			if not GOODS.has(id) or GOODS[id].npc != npc: return "This weapon is not offered here."
			if w.unlocked.get(id, false): return "You already own this weapon."
			var reason := lock_reason(p, id)
			if not reason.is_empty(): return reason
			if p.score < int(GOODS[id].price): return "Not enough Rem Dollars."
			p.add_score(-int(GOODS[id].price))
			w.unlock(id)
			w.state[id].ammo = w.state[id].def.mag
			w.state[id].reserve = int(Weapons.DEFS[id].mag) * 2
			game.achievements.event("weapons")
			Sfx.event(self, p.peer_id, "weapon_pickup")
			if Weapons.is_melee(id): return Lang.t("Bought: %s · select it in the inventory or with the mouse wheel", [Weapons.DEFS[id].name])
			return Lang.t("Bought: %s · magazine + 2 spare magazines", [Weapons.DEFS[id].name])
		"ammo":
			if Weapons.is_melee(id): return "Melee weapons need no ammo."
			if npc == "mechanic" or not Weapons.DEFS.has(id) or not w.unlocked.get(id, false): return "Weapon not available."
			var cost := int(GOODS[id].ammo) if GOODS.has(id) else 12
			if int(w.state[id].reserve) >= w.reserve_limit(id): return "Ammo supply full."
			if p.score < cost: return "Not enough Rem Dollars."
			p.add_score(-cost)
			w.add_ammo(id, int(Weapons.DEFS[id].mag) * 2)
			Sfx.event(self, p.peer_id, "pickup")
			return "Bought two spare magazines."
		"medicine", "grenade":
			if npc != "camp": return "Vendor sells supplies."
			var cost := 35 if action == "medicine" else 45
			if action == "medicine" and p.hp >= p.max_hp: return "Health already full."
			if action == "grenade" and w.grenades >= w.grenades_max: return "Grenade pouch full."
			if p.score < cost: return "Not enough Rem Dollars."
			p.add_score(-cost)
			if action == "medicine":
				p.hp = minf(p.max_hp, p.hp + 60)
				p.hud.set_health(p.hp)
			else: w.grenades += 1
			w.update_hud()
			Sfx.event(self, p.peer_id, "pickup")
			return "Supplies bought."
		"skin":
			if not SKINS.has(id) or SKINS[id].npc != npc or not w.unlocked.get(extra, false): return "Finish not available."
			var s: Dictionary = SKINS[id]
			var missing := prerequisite_reason(p.peer_id, s.quest)
			if not missing.is_empty(): return missing
			var key := extra + ":" + id
			if not d.skins.get(key, false):
				if p.score < int(s.price): return "Not enough Rem Dollars."
				p.add_score(-int(s.price))
				d.skins[key] = true
			w.apply_skin(extra, id)
			Sfx.event(self, p.peer_id, "purchase")
			return Lang.t("Finish applied: %s", [s.name])
		"stock_skin":
			if not w.unlocked.get(id, false): return "Weapon not available."
			w.apply_skin(id, "")
			Sfx.event(self, p.peer_id, "purchase")
			return "Original finish applied."
		"training":
			if npc != "mechanic": return "Mechanic offers training."
			return game.skills.purchase(p, w, id)
		"tower_upgrade", "tower_sell":
			if npc != "mechanic" or not id.is_valid_int(): return "Mechanic offers upgrades."
			return game.defences.maintain(p, int(id), action.trim_prefix("tower_"), true)
	return "Unknown action."

func request(action: String, id := "", extra := "") -> void:
	if action == "quest" and id == "arrival" and shop == "camp" and not _arrival_guide_read and not local_data().claimed.get(id, false):
		_arrival_guide_pending = true
		vendor_guide.open()
		return
	if NetSession.enabled:
		NetSession.command("shop", [shop, action, id, extra])
		status.text = "Request sent to the host …"
	else:
		var before: int = game.player.score
		status.text = transact(game.player, shop, action, id, extra)
		show_gain(game.player.score - before)
	_last_signature = ""

func _finish_vendor_guide() -> void:
	_arrival_guide_read = true
	var pending := _arrival_guide_pending
	_arrival_guide_pending = false
	if pending and is_open and shop == "camp": request("quest", "arrival")
	_last_signature = ""

func _replay_vendor_guide() -> void:
	_arrival_guide_pending = false
	vendor_guide.step = 0
	vendor_guide.open()

func interact(id: String) -> void:
	if id == "cache":
		if NetSession.enabled: NetSession.command("shop", [id, "cache", "", ""])
		else: game.hud.message(transact(game.player, id, "cache", ""), 3)
		return
	if not game.player.active or not close_enough(game.player, id): return
	shop = id
	_mod_weapon = game.weapons.ammo_weapon()
	_greet(id)
	page = "Quests" if not local_data().claimed.get("arrival", false) or id == "mechanic" or NPCS[id].get("quests_only", false) else "Trade"
	if id == "wanderer": page = "Rarities"
	is_open = true
	game.player.active = false
	game.weapons.viewmodel.hide()
	for part in game.hud.crosshair_parts: part.hide()
	game.hud.set_prompt("")
	get_tree().paused = not NetSession.enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.show()
	request("visit")
	status.text = "Co-op keeps running. Stay in cover." if NetSession.enabled else ""
	_render()

# Local dialogue greeting, also audible during the solo pause. Mara follows the HUD's world-time phases.
const VOCALS := {"camp": "vendor_vocal", "secret": "secret_vendor_vocal", "wanderer": "secret_vendor_vocal", "mechanic": "mechanic_vocal"}
const MARA_VOCALS := {"Morning": "mara_morning", "Day": "mara_day", "Evening": "mara_evening", "Night": "mara_night"}
var _greeting: AudioStreamPlayer

func _greet(id: String) -> void:
	var vocal: String = MARA_VOCALS[DayNightCycle.phase_at(game.day_night.clock_seconds / 3600.0)] if id == "ranger" else VOCALS.get(id, "")
	if vocal.is_empty(): return
	if is_instance_valid(_greeting):
		_greeting.stop()
		_greeting.queue_free()
	_greeting = AudioStreamPlayer.new()
	_greeting.stream = Sfx.get_stream(vocal)
	_greeting.volume_db = Sfx.EVENTS[vocal]
	_greeting.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_greeting)
	_greeting.play()
	_greeting.finished.connect(_greeting.queue_free)

func close() -> void:
	if not is_open: return
	vendor_guide.hide()
	_arrival_guide_pending = false
	is_open = false
	panel.hide()
	get_tree().paused = false
	game.player.active = game.player.alive and not game.over
	game.weapons.viewmodel.visible = game.player.active
	for part in game.hud.crosshair_parts: part.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if game.player.active else Input.MOUSE_MODE_VISIBLE
	game.defences.input_grace = 0.25

# A sale between two dozen rows barely registered before: the amount now flies up in gold
# right where the click landed and the balance line flashes with it.
func _update_balance() -> void:
	if balance: balance.text = Lang.t("%d REM DOLLARS  ·  MISSION LEVEL %d  ·  %d WAVES SURVIVED", [game.player.score, mission_level(), game.waves.completed])

func show_gain(amount: int) -> void:
	if amount == 0: return
	# The flash is worthless if the balance behind it still shows the old total for a quarter second.
	_update_balance()
	_balance_pulse = 1.0
	if not _gain_popup: return
	_gain_popup.text = ("+%d R" if amount > 0 else "%d R") % amount
	_gain_popup.add_theme_color_override("font_color", GAIN_GOLD if amount > 0 else GAIN_RED)
	_gain_at = panel.get_local_mouse_position()
	_gain_t = GAIN_SECONDS
	_gain_popup.modulate.a = 1.0
	_gain_popup.visible = true

func _animate_gain(delta: float) -> void:
	if _balance_pulse > 0.0 and balance:
		_balance_pulse = maxf(0.0, _balance_pulse - delta * 1.7)
		var glow := _balance_pulse * _balance_pulse
		balance.add_theme_color_override("font_color", Color(0.9, 0.9, 0.86).lerp(GAIN_GOLD, glow))
		balance.pivot_offset = Vector2(0.0, balance.size.y * 0.5)
		balance.scale = Vector2.ONE * (1.0 + glow * 0.11)
	if _gain_t <= 0.0:
		if _gain_popup and _gain_popup.visible: _gain_popup.visible = false
		return
	_gain_t = maxf(0.0, _gain_t - delta)
	var travelled := 1.0 - _gain_t / GAIN_SECONDS
	_gain_popup.pivot_offset = _gain_popup.size * 0.5
	# a quick punch on appearance, then a steady drift upwards while it fades
	_gain_popup.scale = Vector2.ONE * (1.45 - 0.45 * minf(1.0, travelled * 5.0))
	# A click near an edge must not push the number off screen.
	var target := _gain_at + Vector2(-_gain_popup.size.x * 0.5, -30.0 - travelled * 95.0)
	_gain_popup.position = target.clamp(Vector2(12.0, 12.0), (panel.size - _gain_popup.size - Vector2(12.0, 12.0)).max(Vector2(12.0, 12.0)))
	_gain_popup.modulate.a = clampf(_gain_t * 2.4, 0.0, 1.0)
	if _gain_t <= 0.0: _gain_popup.visible = false

func _label(text: String, size := 18) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _rich_label(text: String, size := 18) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.text = text
	label.add_theme_font_size_override("normal_font_size", size)
	label.add_theme_font_size_override("bold_font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _build_ui() -> void:
	tracker = _rich_label("", 14)
	tracker.position = Vector2(26, 154)
	tracker.size = Vector2(390, 0)
	tracker.add_theme_color_override("default_color", Color(0.93, 0.83, 0.61))
	tracker.add_theme_color_override("font_shadow_color", Color.BLACK)
	tracker.add_theme_constant_override("shadow_offset_x", 2)
	tracker.add_theme_constant_override("shadow_offset_y", 2)
	tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tracker)
	tutorial = _label("", 18)
	tutorial.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tutorial.position = Vector2(-330, -240)
	tutorial.size = Vector2(660, 70)
	tutorial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial.add_theme_constant_override("line_spacing", 10)
	tutorial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial.add_theme_color_override("font_shadow_color", Color.BLACK)
	tutorial.add_theme_constant_override("shadow_offset_x", 2)
	tutorial.add_theme_constant_override("shadow_offset_y", 2)
	tutorial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tutorial)
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var dim := ColorRect.new()
	dim.color = Color(0.018, 0.023, 0.02, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -465
	card.offset_right = 465
	card.offset_top = -305
	card.offset_bottom = 305
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.063, 0.055, 0.99)
	style.border_color = Color(0.55, 0.43, 0.23)
	style.set_border_width_all(1)
	style.set_content_margin_all(24)
	style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", style)
	panel.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	title = _label("", 30)
	title.add_theme_color_override("font_color", Color(0.97, 0.76, 0.43))
	column.add_child(title)
	subtitle = _label("", 16)
	column.add_child(subtitle)
	balance = _label("", 18)
	balance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	balance.autowrap_mode = TextServer.AUTOWRAP_OFF
	var wallet := HBoxContainer.new()
	wallet.add_theme_constant_override("separation", 8)
	wallet.add_child(preload("res://scripts/currency.gd").icon(32.0, GAIN_GOLD))
	wallet.add_child(balance)
	column.add_child(wallet)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	for tab in ["Trade", "Fireworks", "Sell", "Quests", "Training", "Towers", "Mods", "Skins", "Rarities"]:
		var button := Button.new()
		button.text = tab
		button.custom_minimum_size = Vector2(160, 38)
		button.pressed.connect(func(): page = tab; _render())
		tabs.add_child(button)
		_tabs[tab] = button
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 310)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	status = _label("", 17)
	status.custom_minimum_size.y = 38
	status.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	column.add_child(status)
	var done := Button.new()
	done.text = "Back to the forest · Esc"
	done.custom_minimum_size.y = 40
	done.pressed.connect(close)
	column.add_child(done)
	# Earned points are easy to miss between two dozen rows, so they fly up in gold over the card.
	_gain_popup = _label("", 40)
	_gain_popup.add_theme_color_override("font_color", GAIN_GOLD)
	_gain_popup.add_theme_constant_override("outline_size", 8)
	_gain_popup.add_theme_color_override("font_outline_color", Color(0.09, 0.05, 0.0, 0.95))
	_gain_popup.autowrap_mode = TextServer.AUTOWRAP_OFF
	_gain_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gain_popup.visible = false
	panel.add_child(_gain_popup)
	vendor_guide = VendorGuide.new()
	panel.add_child(vendor_guide)
	vendor_guide.finished.connect(_finish_vendor_guide)
	panel.hide()

func _row(heading: String, details: String, button_text: String, action: Callable, disabled := false, blocked_reason := "", rich := false) -> void:
	# Updating prices and quest counters must preserve the button receiving a click.
	if not _building_layout:
		var widgets: Array = _row_nodes[_row_index]
		widgets[0].text = heading
		widgets[1].text = details
		widgets[2].text = button_text
		widgets[2].disabled = disabled
		widgets[3].texture = ItemIcons.texture(ItemIcons.action_id(action))
		widgets[4].text = blocked_reason
		widgets[4].visible = not blocked_reason.is_empty()
		_row_index += 1
		return
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	rows.add_child(box)
	var icon := ItemIcons.view(ItemIcons.action_id(action), Vector2(112, 76))
	box.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var heading_label := _label(heading, 19)
	text.add_child(heading_label)
	var desc := _rich_label(details, 14)
	desc.bbcode_enabled = rich
	desc.add_theme_color_override("default_color", Color(0.72, 0.8, 0.72))
	text.add_child(desc)
	var warning := _label(blocked_reason, 14)
	warning.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	warning.visible = not blocked_reason.is_empty()
	text.add_child(warning)
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(205, 45)
	button.disabled = disabled
	button.pressed.connect(action)
	box.add_child(button)
	rows.add_child(HSeparator.new())
	_row_nodes.append([heading_label, desc, button, icon, warning])
	_row_index += 1

func _info(text: String, size := 18) -> void:
	if _building_layout: rows.add_child(_label(text, size))

func _render() -> void:
	# interact() leaves shop untouched when the player is out of reach or the trader is hidden,
	# so a render without an open trader would index NPCS with an empty id.
	if not NPCS.has(shop): return
	for tab in _tabs:
		if shop == "wanderer":
			_tabs[tab].visible = tab == "Rarities"
			continue
		_tabs[tab].visible = tab in (["Quests"] if NPCS[shop].get("quests_only", false) else (["Quests", "Training", "Towers", "Mods"] if shop == "mechanic" else (["Trade", "Sell", "Quests", "Mods", "Skins"] if shop == "secret" else ["Trade", "Fireworks", "Sell", "Quests", "Skins"])))
	var owners := []
	for tower: DefenceTower in game.defences.towers.values(): owners.append([tower.tower_id, tower.owner_peer])
	var layout := str([shop, page, game.weapons.current, game.weapons.unlocked, owners, _mod_weapon, rare_market.stock.keys(), local_data().claimed if page == "Quests" else {}])
	_building_layout = layout != _layout_key
	_layout_key = layout
	_row_index = 0
	if _building_layout:
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
		_row_nodes.clear()
	title.text = Lang.t("%s · %s", [Lang.raw(Lang.text(NPCS[shop].name).to_upper()), page])
	subtitle.text = NPCS[shop].line
	_update_balance()
	var p: Player = game.player
	var d := local_data()
	match page:
		"Fireworks":
			_info("LIGHTS OVER THE FOREST", 21)
			_info("Select them in the inventory [I], then left click to light. Right click: back to your weapon.\nRockets climb about 34 m. Pure fireworks without combat damage. Supplies last for this round.", 14)
			for id in Fireworks.DEFS:
				var spec: Dictionary = Fireworks.DEFS[id]
				var blocked: String = game.fireworks.buy_error(p, id)
				var detail: String = Lang.t("%s\n%d / %d in inventory · firework bag %d / %d", [spec.desc, game.fireworks.stock(p.peer_id)[id], spec.limit, game.fireworks.count(p.peer_id), Fireworks.CAPACITY])
				_row(spec.name, detail, Lang.t("%s · %d R", ["1 battery" if Fireworks.is_battery(id) else "5-pack" if spec.pack == 5 else "1 rocket", spec.price]), request.bind("firework", id), not blocked.is_empty(), blocked)
		"Rarities":
			_info(Lang.t("Stock changes with the wave, time of day and location · shared by all players.\nRight now: %s · %s. One talisman active. Selection and special ammo in the inventory [I]. Purchases last for this round.", ["Day" if rare_market.phase() == "day" else "Night", rare_market.region_name()]), 14)
			for id in rare_market.stock:
				var spec: Dictionary = rare_market.Items.DEFS[id]
				var owned: bool = rare_market.data(p.peer_id).owned.get(id, false)
				var blocked := ""
				if not owned:
					if mission_level() < int(spec.level): blocked = Lang.t("Mission level %d needed (currently %d).", [spec.level, mission_level()])
					elif int(rare_market.stock[id]) <= 0: blocked = "Sold out · New stock at the next stop or from the next wave."
					elif p.score < int(spec.price): blocked = Lang.t("Not enough Rem Dollars: %d R needed.", [spec.price])
				_row(spec.name, Lang.t("%s\nLevel %d · stock %d", [spec.desc, spec.level, rare_market.stock[id]]), "Activate" if owned else Lang.t("Buy · %d R", [spec.price]), request.bind("rare", id), not blocked.is_empty(), blocked)
		"Mods": _render_mods(p)
		"Sell":
			var w: Weapons = game.weapons
			var stock := mushroom_stock(p)
			for kind in game.hunting.FOOD:
				var spec: Dictionary = game.hunting.FOOD[kind]
				var count := int(game.hunting.stock(p.peer_id).get(kind, 0))
				_row(Lang.t("%s · %d in inventory", [spec.name, count]), spec.text, Lang.t("Sell 1 · %d R", [spec.sell]), request.bind("sell_meat", kind), count <= 0)
			for kind in Inventory.MUSHROOMS:
				var spec: Dictionary = Inventory.MUSHROOMS[kind]
				var count := int(stock.get(kind, 0))
				_row(Lang.t("%s · %d in inventory", [spec.name, count]), spec.text, Lang.t("Sell 1 · %d R", [spec.sell]), request.bind("sell_mushroom", kind), count <= 0)
			_row(Lang.t("Hand grenades · %d in inventory", [w.grenades]), "Sell one grenade.", Lang.t("Sell 1 · %d R", [15]), request.bind("sell_grenade"), w.grenades <= 0)
			for wid in Weapons.ORDER:
				if not w.unlocked.get(wid, false): continue
				if not Weapons.is_melee(wid):
					var amount := int(Weapons.DEFS[wid].mag)
					_row(Lang.t("Ammo · %s", [Weapons.DEFS[wid].name]), Lang.t("Sell %d rounds. Reserve: %d.", [amount, w.state[wid].reserve]), "+%d R" % ammo_sale_price(wid), request.bind("sell_ammo", wid), int(w.state[wid].reserve) < amount)
				if GOODS.has(wid):
					_row(Weapons.DEFS[wid].name, "Sell the weapon. Leftover ammo adds nothing to the price; sell the reserve separately first. Purchase permits are kept.", "+%d R" % int(int(GOODS[wid].price) * 0.35), request.bind("sell_weapon", wid))
		"Quests":
			if shop == "camp":
				_row("Basics with Vendor", "Inventory, Rem Dollars, towers and barricades · read up for free.", "View introduction", _replay_vendor_guide)
			for completed in [false, true]:
				var quest_ids: Array = []
				for id in ordered_quests():
					if QUESTS[id].npc == shop and bool(d.claimed.get(id, false)) == completed:
						quest_ids.append(id)
				if quest_ids.is_empty(): continue
				_info("Completed quests" if completed else "Open quests", 22)
				for id in quest_ids:
					var q: Dictionary = QUESTS[id]
					if q.npc != shop: continue
					var claimed: bool = d.claimed.get(id, false)
					var accepted: bool = d.accepted.get(id, false)
					var blocked := quest_lock_reason(p.peer_id, id)
					var locked := not blocked.is_empty()
					var text := "Done" if claimed else ("Locked" if locked else ("Collect reward" if accepted and complete(id) else ("In progress" if accepted else "Accept quest")))
					if id == "arrival" and not claimed and not locked and not _arrival_guide_read: text = "Start tutorial"
					var details: String = Lang.t(q.desc)
					var chain := quest_chain(id)
					var heading: String = Lang.t("%s · Level %d · %d R", [q.name, q.min_level, q.reward])
					if not chain.is_empty():
						heading = Lang.t("%s · %d/%d · %s", [QUEST_CHAINS[chain].name, QUEST_CHAINS[chain].quests.find(id) + 1, QUEST_CHAINS[chain].quests.size(), heading])
						details += "\n" + chain_description(p.peer_id, chain, false)
					if int(q.waves_after_accept) > 0: details += "\n" + Lang.t("After accepting, survive %d more wave(s). Team goals count retroactively; collect the reward yourself.", [q.waves_after_accept])
					_row(heading, details + "\n" + quest_progress(id, -1, true), text, request.bind("quest", id), claimed or locked or (accepted and not complete(id)), blocked if locked and not claimed else "", true)
		"Trade":
			if shop in ["camp", "secret"]:
				var refill := refill_quote(p)
				var details := Lang.t("Magazines and reserves of all your firearms. First %s, then the other weapons. Grenades separately.\nFull: %d R · With your balance: +%d rounds for %d R.", [Weapons.DEFS[game.weapons.ammo_weapon()].name, refill.full_cost, refill.rounds, refill.cost])
				_row("Autorefill · all ammo", details, "All full" if refill.missing == 0 else ("Not enough Rem Dollars" if refill.rounds == 0 else Lang.t("Refill · %d R", [refill.cost])), request.bind("autorefill"), refill.rounds == 0)
			if shop == "mechanic": _info("Mechanic offers training, tower upgrades and quests. Weapons and supplies are sold by Vendor at the campfire.")
			for id in GOODS:
				var spec: Dictionary = GOODS[id]
				if spec.npc != shop: continue
				var owned: bool = game.weapons.unlocked.get(id, false)
				var reason := lock_reason(p, id)
				var gun: Dictionary = Weapons.DEFS[id]
				var details := Lang.t("%s\n%d damage × %d · %d rounds · %.1f s reload", [spec.desc, int(gun.damage), gun.pellets, gun.mag, gun.reload])
				if Weapons.is_melee(id):
					details = Lang.t("%s\n%d damage · %.2f s per swing · %.2f m range", [spec.desc, int(gun.damage), gun.rate, gun.range])
				if spec.has("chain"): details += "\n" + chain_description(p.peer_id, spec.chain)
				if gun.has("pierce_targets"): details += "\n" + Lang.t(Weapons.piercing_description(id))
				var blocked := ""
				if not owned:
					if not reason.is_empty(): blocked = Lang.t("LOCKED · %s", [reason])
					if p.score < int(spec.price):
						blocked += ("\n" if not blocked.is_empty() else "") + Lang.t("You are %d Rem Dollars short for this purchase.", [int(spec.price) - p.score])
				var buy_text := "Owned" if owned else (Lang.t("Locked · %d R", [spec.price]) if not reason.is_empty() else Lang.t("Buy · %d R", [spec.price]))
				_row(gun.name, details, buy_text, request.bind("weapon", id), owned or not blocked.is_empty(), blocked)
			if shop != "mechanic":
				for wid in Weapons.ORDER:
					if Weapons.is_melee(wid): continue
					if not game.weapons.unlocked.get(wid, false): continue
					var cost := int(GOODS[wid].ammo) if GOODS.has(wid) else 12
					var reserve: int = game.weapons.state[wid].reserve
					var limit: int = game.weapons.reserve_limit(wid)
					var full := reserve >= limit
					var amount := int(Weapons.DEFS[wid].mag) * 2
					_row(Lang.t("Ammo · %s", [Weapons.DEFS[wid].name]), Lang.t("Two magazines (+%d rounds, up to the supply limit). Supply: %d / %d.", [amount, reserve, limit]), "Supply full" if full else "%d R" % cost, request.bind("ammo", wid), full or p.score < cost)
			if shop == "camp":
				_row("Bandage", "+60 health, up to the maximum", "35 R", request.bind("medicine"), p.score < 35 or p.hp >= p.max_hp)
				_row("Hand grenade", "One grenade, until the pouch is full", "45 R", request.bind("grenade"), p.score < 45 or game.weapons.grenades >= game.weapons.grenades_max)
		"Training":
			if shop != "mechanic": _info("Mechanic, north of the campfire, offers training.")
			else:
				for spec in Skills.UPGRADES:
					var level: int = game.skills.levels.get(spec.id, 0)
					var cost := int(spec.cost) + int(spec.cost) * level / 2
					_row(Lang.t("%s · %d/%d", [spec.name, level, spec.max]), spec.desc, "%d R" % cost, request.bind("training", spec.id), level >= int(spec.max) or p.score < cost)
		"Towers":
			if _building_layout: rows.add_child(ItemIcons.view("tower", Vector2(140, 90)))
			_info("T: choose a tower type · R/mouse wheel: rotate · E: place\nAt the tower: E climbs up, R aims, F repairs. On top: the mouse aims, left click fires, E climbs down. Without an operator the tower fires on its own. Sustained fire builds up heat.", 16)
			for kind in DefenceTower.TYPES:
				var spec: Dictionary = DefenceTower.SPECS[kind]
				var required: int = game.defences.unlock_waves(kind)
				_info(Lang.t("%s · %d R · %s\nTier 2 after wave %d · Tier 3 after wave %d", [spec.name, spec.cost, "From the start" if required == 0 else Lang.t("After wave %d", [required]), game.defences.unlock_waves(kind, 2), game.defences.unlock_waves(kind, 3)]), 16)
			if shop != "mechanic": _info("Mechanic offers tower upgrades.")
			else:
				for id in game.defences.towers:
					var tower: DefenceTower = game.defences.towers[id]
					var cost: int = tower.upgrade_cost()
					var reason: String = game.defences.upgrade_reason(p, tower)
					_row(Lang.t("%s #%d · Tier %d", [tower.spec().name, id, tower.level]), Lang.t("%d/%d HP · %d m range · %d m away", [ceili(tower.hp), tower.max_hp(), tower.attack_range(), p.global_position.distance_to(tower.global_position)]), "Maximum" if tower.level == 3 else Lang.t("Upgrade · %d R", [cost]), request.bind("tower_upgrade", str(id)), not reason.is_empty(), reason)
					# The builder's own towers can be dismantled (maintain "sell" checks it again). The row went
					# missing on 22 Sep while the guides kept describing it; a roof turret, which no zombie
					# reaches, otherwise held its slot of the team's six for the rest of the round.
					if tower.owner_peer == p.peer_id: _row(Lang.t("Dismantle %s #%d", [tower.spec().name, id]), Lang.t("The tower is removed. %d R back.", [tower.refund()]), "Dismantle", request.bind("tower_sell", str(id)), tower.operator_peer != 0, "The tower is being operated right now." if tower.operator_peer else "")
		"Skins":
			var wid: String = game.weapons.current
			_info(Lang.t("Finishes for: %s\nPick your weapon before the conversation. Skins don't change combat stats.", [Weapons.DEFS[wid].name]), 16)
			for id in SKINS:
				var spec: Dictionary = SKINS[id]
				if spec.npc != shop: continue
				var owned: bool = d.skins.get(wid + ":" + id, false)
				var allowed := has_claim(p.peer_id, spec.quest)
				_row(spec.name, Lang.t(spec.desc) + ("" if allowed else "\n" + prerequisite_reason(p.peer_id, spec.quest)), "Apply" if owned else Lang.t("Buy · %d R", [spec.price]), request.bind("skin", id, wid), not allowed or (not owned and p.score < int(spec.price)))
			_row("Original finish", "Switch back to the original material for free.", "Apply", request.bind("stock_skin", wid))

var _mod_weapon := "pistol"

func _render_mods(p: Player) -> void:
	if shop not in ["mechanic", "secret"]: return
	var w: Weapons = game.weapons
	if not w.unlocked.get(_mod_weapon, false): _mod_weapon = "pistol"
	if _building_layout:
		var chooser := OptionButton.new()
		chooser.custom_minimum_size.y = 40
		for wid in Weapons.ORDER:
			if Weapons.is_melee(wid) or not w.unlocked.get(wid, false): continue
			chooser.add_item(Weapons.DEFS[wid].name)
			var index := chooser.item_count - 1
			chooser.set_item_metadata(index, wid)
			if wid == _mod_weapon: chooser.select(index)
		chooser.item_selected.connect(func(index: int): _mod_weapon = chooser.get_item_metadata(index); _render())
		rows.add_child(chooser)
	_info("Mods apply per weapon for this round. One mod per slot; switch bought mods for free. Ammo sold separately.\nMission level = waves survived + 1.", 14)
	var wid := _mod_weapon
	var effective: Dictionary = w.state[wid].def
	_row(Weapons.DEFS[wid].name, Lang.t("%d damage × %d · %d rounds · %.2f s reload\n%s", [roundi(effective.damage * w.effective_damage_mul()), effective.pellets, effective.mag, effective.reload * w.effective_reload_mul(), Weapons.Mods.summary(w.mod_loadout.get(wid, {}))]), "Current stats", func(): pass, true)
	for id in Weapons.Mods.DEFS:
		var spec: Dictionary = Weapons.Mods.DEFS[id]
		if spec.npc != shop: continue
		var owned: bool = w.mod_owned.get(wid + ":" + id, false)
		var equipped: bool = w.mod_loadout.get(wid, {}).get(spec.slot, "") == id
		var reason := mod_lock_reason(p, id, wid)
		if reason.is_empty() and not owned and p.score < int(spec.price): reason = Lang.t("Not enough Rem Dollars: %d R needed.", [spec.price])
		_row(Lang.t("%s · Level %d", [spec.name, spec.level]), Lang.t("%s · %s", [spec.slot, spec.desc]), "Mounted" if equipped else ("Mount" if owned else Lang.t("Buy · %d R", [spec.price])), request.bind("mod", id, wid), equipped or not reason.is_empty(), reason)
	for slot in Weapons.Mods.SLOTS:
		var installed: String = w.mod_loadout.get(wid, {}).get(slot, "")
		_row(slot, Weapons.Mods.DEFS[installed].name if not installed.is_empty() else "Original equipment", "Remove", request.bind("remove_mod", slot, wid), installed.is_empty())

func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif game.started and not game.over and game.player.active and event.is_action_pressed("skills") and not event.is_echo():
		_journal = not _journal
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not game: return
	if _arrival_guide_read:
		_arrival_inventory_seen = _arrival_inventory_seen or game.inventory.is_open
		_arrival_build_menu_seen = _arrival_build_menu_seen or game.defences.is_open or game.defences.placing
	_animate_gain(delta)
	for id in npcs:
		npcs[id].quest_marker.visible = game.started and not game.over and has_ready_quest(id)
	if is_open and not close_enough(game.player, shop): close()
	var playing: bool = game.started and not game.over and game.player.active and not game.hud.overlay.visible
	var guiding: bool = game.intro != null and game.intro.showing_guidance()
	notifications.visible = game.started and not game.over and not game.hud.overlay.visible and not guiding
	tracker.visible = playing and _journal and not game.defences.placing and not guiding
	tutorial.visible = playing and not game.defences.placing and not game.defences.is_open and not game.player.mounted_tower and not game.player.controlling_drone and not guiding
	if tutorial.visible and local_data().claimed.get("arrival", false) and team.built == 0:
		_tower_tutorial_remaining = maxf(0.0, _tower_tutorial_remaining - delta)
	_refresh_time -= delta
	if _refresh_time > 0: return
	_refresh_time = 0.25
	if game.started:
		refresh_notifications()
	_discover_visible_npcs()
	cache_node.visible = cache_ready and not team.cache
	if is_open:
		var structures := []
		for tower: DefenceTower in game.defences.towers.values(): structures.append([tower.tower_id, tower.level, ceili(tower.hp)])
		for barrier: Barricade in game.barricades: structures.append([barrier.level, barrier.hp > 0])
		var reserves := {}
		for wid in game.weapons.state: reserves[wid] = [game.weapons.state[wid].ammo, game.weapons.state[wid].reserve]
		var signature := str([game.player.score, ceili(game.player.hp), game.weapons.grenades, reserves, mushroom_stock(game.player), game.hunting.stock(game.player.peer_id), game.weapons.unlocked, people, team, game.waves.completed, game.waves.wave, game.skills.levels, game.weapons.current, structures, game.weapons.mod_owned, game.weapons.mod_loadout, rare_market.stock, rare_market.people, game.fireworks.stock(game.player.peer_id)])
		if signature != _last_signature:
			_last_signature = signature
			_render()
	var d := local_data()
	var tracked: Array[String] = []
	for id in ordered_quests():
		if d.accepted.get(id, false) and not d.claimed.get(id, false):
			tracked.append(id)
	if tracked.is_empty():
		tracker.text = "ALL QUESTS DONE\nHold the hut and survive the next wave." if d.claimed.size() == QUESTS.size() else "QUESTS · Q on/off\nTalk to Vendor at the campfire and Mechanic north of it."
		for chain in QUEST_CHAINS:
			if chain_complete(game.player.peer_id, chain): continue
			for id in QUEST_CHAINS[chain].quests:
				if not has_claim(game.player.peer_id, id):
					# Upper case needs the final wording; the tracker is rebuilt four times a second.
					tracker.text = Lang.t("%s · NEXT QUEST\n%s", [Lang.raw(Lang.text(QUEST_CHAINS[chain].name).to_upper()), next_quest_step(game.player.peer_id, id)])
					break
			break
	else:
		var ready := PackedStringArray()
		var ongoing := PackedStringArray()
		for id in tracked:
			if complete(id):
				ready.append("[color=#ffd479][b]%s[/b]\n[b]%s[/b]\n%s[/color]" % [Lang.t("READY TO TURN IN"), Lang.t(QUESTS[id].name), Lang.t("Turn in to %s · %d R reward", [NPCS[QUESTS[id].npc].name, QUESTS[id].reward])])
			else:
				ongoing.append(Lang.t(QUESTS[id].name) + "\n" + quest_progress(id, -1, true))
		var entries := PackedStringArray([Lang.t("QUESTS (%d) · Q on/off", [tracked.size()])])
		if not ready.is_empty():
			entries.append("[color=#ffd479][b]%s[/b][/color]" % Lang.t("%d ready to turn in", [ready.size()]))
		entries.append_array(ready)
		entries.append_array(ongoing)
		tracker.text = "\n\n".join(entries)
	tracker.size.y = 0
	if not d.claimed.get("arrival", false):
		tutorial.text = "WEAPONS & QUESTS\n[E] Talk to Vendor at the campfire."
	elif _arrival_guide_read and not _arrival_inventory_seen:
		tutorial.text = "YOUR GEAR · [I] INVENTORY\nOpen your inventory and look at your weapons and items."
	elif _arrival_guide_read and not _arrival_build_menu_seen:
		tutorial.text = "YOUR DEFENSE · [T] TOWER BUILD MENU\nTake a look at the towers. Only E in the preview confirms a purchase."
	elif team.built == 0:
		tutorial.text = "DEFENSE · [T] TOWER BUILD MENU\n5 types from 120 R · E builds / climbs up · Mechanic upgrades." if _tower_tutorial_remaining > 0.0 else ""
	elif team.turned == 0:
		tutorial.text = "AIM YOUR SENTINEL\nPress R at the tower, rotate with R/mouse wheel and confirm with E."
	else: tutorial.text = ""

func snapshot() -> Dictionary:
	return {"people": people.duplicate(true), "team": team.duplicate(true), "cache_position": cache_node.global_position if cache_node else Vector3.ZERO, "cache_ready": cache_ready, "rare_market": rare_market.snapshot() if rare_market else {}}

func refresh_notifications() -> void:
	var peer: int = NetSession.local_id() if NetSession.enabled else game.player.peer_id
	notifications.observe(self, peer, _notification_baseline_pending)
	_notification_baseline_pending = false

func apply_snapshot(s: Dictionary, initial := false) -> void:
	# Wave state is applied later in the same network snapshot. Observe it on the
	# next UI refresh, after the whole snapshot is in place, and suppress history.
	if initial: _notification_baseline_pending = true
	if rare_market: rare_market.apply_snapshot(s.get("rare_market", {}))
	people = s.get("people", {}).duplicate(true)
	team = s.get("team", team).duplicate(true)
	cache_ready = bool(s.get("cache_ready", false))
	if cache_node:
		if cache_ready: cache_node.global_position = s["cache_position"]
		cache_node.visible = cache_ready and not team.cache

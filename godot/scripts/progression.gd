class_name Progression
extends CanvasLayer

const QUEST_MARKER_COLOR := Color(1.0, 0.78, 0.2)
const VendorGuide = preload("res://scripts/vendor_tutorial.gd")

# One authoritative catalogue is shared by the UI, solo game and host validation.
const NPCS := {
	"wanderer": {"name": "Nebelkrämer", "role": "Wanderhändler · Legendäre Raritäten", "model": "npc_secret_trader", "height": 1.9, "pos": Vector2(-35, -55), "line": "Heute hier, morgen zwischen anderen Bäumen. Was ich mitbringe, kommt selten zweimal."},
	"ranger": {"name": "Mara", "role": "Försterin · Waldaufträge", "model": "npc_mechanic", "height": 1.7, "pos": Vector2(-58.8, 63.0), "quests_only": true, "line": "Setz dich kurz ans Feuer. Der Wald gibt uns Schutz, aber wir müssen auf ihn aufpassen."},
	"camp": {"name": "Vendor", "role": "Waffen & Vorräte", "model": "npc_quartermaster", "height": 1.82, "pos": Vector2(4.0, -16.0), "line": "Bleib am Leben. Ich handle mit Leuten, die ihren Teil beitragen."},
	"mechanic": {"name": "Mechanic", "role": "Verteidigung & Training", "model": "npc_mechanic", "height": 1.7, "pos": Vector2(-5, -24), "line": "Eine Sperre hält sie auf. Ein richtig ausgerichteter Wächter erledigt den Rest."},
	"secret": {"name": "Secret Vendor", "role": "Seltene Ausrüstung", "model": "npc_secret_trader", "height": 1.9, "pos": Vector2(-100, -140), "line": "Du hast mich gefunden. Jetzt zeig mir, dass du diese Waffen führen kannst."},
}
const GOODS := {
	"hatchet": {"npc": "camp", "price": 180, "wave": 1, "quest": "arrival", "ammo": 0, "desc": "Kräftige Waldaxt. Langsamer Schlag, hohe Wucht, keine Munition."},
	"revolver": {"npc": "camp", "price": 220, "wave": 1, "quest": "arrival", "ammo": 24, "desc": "Präzise und sparsam. Sechs schwere Schüsse."},
	"smg": {"npc": "camp", "price": 400, "wave": 2, "quest": "watch", "ammo": 30, "desc": "Schnelle Läufer abfangen. Hoher Munitionsverbrauch."},
	"shotgun": {"npc": "camp", "price": 340, "wave": 2, "quest": "arrival", "ammo": 28, "desc": "Starke Nahverteidigung. Auf Distanz wenig wirksam."},
	"ak47": {"npc": "camp", "price": 780, "wave": 4, "quest": "line", "chain": "assault", "ammo": 44, "desc": "Vielseitiges Sturmgewehr mit kräftigem Rückstoss."},
	"marksman": {"npc": "camp", "price": 680, "wave": 3, "quest": "silent_deal", "chain": "marksman", "ammo": 40, "desc": "Repetiergewehr. Langsam, präzise und durchschlagsstark."},
	"lmg": {"npc": "secret", "price": 1350, "wave": 5, "quest": "supplies", "chain": "engineer", "ammo": 90, "desc": "60 Schuss gegen die Horde. Lange Nachladepause."},
	"breacher": {"npc": "secret", "price": 1650, "wave": 6, "quest": "titan", "ammo": 70, "desc": "Halbautomatische Sturmschrotflinte. Nur für kurze Distanzen."},
	"titanbreaker": {"npc": "secret", "price": 2400, "wave": 9, "quest": "titan", "chain": "marksman", "ammo": 110, "desc": "Titanenbrecher .50. 75 % Zusatzschaden gegen Titanen, teure Munition."},
	# Erweiterung September 2026. "ammo" ist der Preis fuer zwei Magazine; die Munitionskosten pro
	# 1000 Schaden bleiben im Korridor der bestehenden Waffen (13-33 R), die Leuchtpistole und die
	# Graviton-Kanone bewusst darueber - sie zahlen fuer Licht und Flaeche, nicht fuer Schaden.
	"flare_pistol": {"npc": "camp", "price": 220, "wave": 2, "quest": "arrival", "ammo": 10, "desc": "Setzt Getroffene in Brand und beleuchtet acht Sekunden lang das Gelaende. Ein Schuss pro Ladung."},
	"deagle": {"npc": "camp", "price": 560, "wave": 4, "quest": "steady_aim", "ammo": 40, "desc": "Schwere .50-Pistole. Toetet Laeufer mit einem Treffer, dafuer brutaler Rueckstoss."},
	"lever_rifle": {"npc": "camp", "price": 640, "wave": 5, "quest": "steady_aim", "ammo": 30, "desc": "Unterhebelrepetierer mit 3x-Zielfernrohr. Schneller als das Repetiergewehr, langes Nachladen."},
	"mac10": {"npc": "camp", "price": 600, "wave": 5, "quest": "night_shift", "ammo": 34, "desc": "40 Schuss, kaum Rueckstoss, gedaempfter Knall. Nur auf kurze Distanz, weite Streuung."},
	"cryo_smg": {"npc": "secret", "price": 1000, "wave": 8, "quest": "titan", "ammo": 32, "desc": "Kuehlt Getroffene herunter, friert sie ein und richtet an Gefrorenen 40 % mehr Schaden an."},
	"plasma_sniper": {"npc": "secret", "price": 1750, "wave": 10, "quest": "silent_deal", "chain": "marksman", "ammo": 60, "desc": "Energiegewehr mit 5x-Optik. Ueberhitzt statt nachzuladen und kuehlt sich selbst."},
	"minigun": {"npc": "secret", "price": 2100, "wave": 11, "quest": "clockwork", "ammo": 190, "desc": "150 Schuss Gurt, hoechste Feuerrate im Lager. Sehr schwer, laeuft erst an, kein Zielfernrohr."},
	"graviton_cannon": {"npc": "secret", "price": 3000, "wave": 13, "quest": "giant_debt", "ammo": 120, "desc": "Sechs Meter Flaechenschaden und 140 % Zusatzschaden gegen Titanen. Nur zwoelf Energiezellen."},
}
const QUESTS := {
	"forest_basket": {"min_level": 2, "waves_after_accept": 1,"npc": "ranger", "name": "Was der Wald uns gibt", "requires": "arrival", "reward": 90, "desc": "Sammelt als Team fünf Steinpilze. Mara zeigt euch, worauf man im Wald achten muss. Bereits gesammelte Pilze zählen; ihr dürft sie behalten.", "goals": {"edible_mushrooms": 5}},
	"restless_paths": {"min_level": 5, "waves_after_accept": 1,"npc": "ranger", "name": "Unruhe auf den Wegen", "requires": "forest_basket", "reward": 140, "desc": "Besiegt als Team zwölf Läufer. Ihre schnellen Schritte lassen selbst hier am kleinen Feuer niemanden zur Ruhe kommen.", "goals": {"runner_kills": 12}},
	"forest_watch": {"min_level": 8, "waves_after_accept": 1,"npc": "ranger", "name": "Solange das Feuer brennt", "requires": "restless_paths", "reward": 220, "desc": "Übersteht Welle 6 und besiegt insgesamt 80 Zombies. Kehre danach zu Mara an die kleine Feuerstelle zurück.", "goals": {"waves": 6, "kills": 80}},
	"arrival": {"min_level": 1, "waves_after_accept": 0,"npc": "camp", "name": "Am Feuer", "requires": "", "reward": 20, "desc": "Vendor führt dich in Inventar, Handel, Turmbau und Barrikaden ein. Lerne die Grundlagen und hole danach deine Belohnung ab."},
	"watch": {"min_level": 2, "waves_after_accept": 1,"npc": "mechanic", "name": "Der erste Wächter", "requires": "arrival", "reward": 110, "desc": "Baue eine Barrikade und einen Turm. Richte den Turm anschliessend neu aus. T: Vorschau · R/Mausrad: drehen · E: bestätigen. Am Turm R: ausrichten, E: einsteigen, F: reparieren."},
	"line": {"min_level": 2, "waves_after_accept": 1,"npc": "camp", "name": "Die Linie halten", "requires": "arrival", "reward": 140, "desc": "Übersteht als Team zwei Wellen und besiegt 30 Zombies. Kehre zu Vendor zurück."},
	"supplies": {"min_level": 4, "waves_after_accept": 1,"npc": "mechanic", "name": "Die verlorene Lieferung", "requires": "watch", "reward": 180, "desc": "Die Werkzeugkiste ist irgendwo im Gebiet verloren gegangen. Ihr Fundort wechselt mit jeder Runde und ist nach Annahme auf der Karte markiert. Berge die Lieferung und kehre zu Mechanic zurück."},
	"titan": {"min_level": 7, "waves_after_accept": 1,"npc": "secret", "name": "Was auf dem Feld lauert", "requires": "supplies", "reward": 300, "desc": "Besiegt gemeinsam einen Feldtitanen. Sie erscheinen ab Welle 6. Hole danach deine Belohnung beim Secret Vendor ab."},
	"steady_aim": {"min_level": 2, "waves_after_accept": 1,"npc": "camp", "name": "Eine ruhige Hand", "requires": "arrival", "reward": 90, "desc": "Besiegt als Team 15 Zombies mit Kopfschüssen. Jeder gezielte Treffer spart Vorräte.", "goals": {"headshot_kills": 15}},
	"marksman_training": {"min_level": 5, "waves_after_accept": 1,"npc": "camp", "name": "Präzision unter Druck", "requires": "steady_aim", "reward": 140, "desc": "Erreicht als Team 25 Kopfschuss-Kills und übersteht Welle 3. Pistole und Revolver genügen. Danach schickt dich Vendor zur Abschlussprüfung beim Secret Vendor.", "goals": {"headshot_kills": 25, "waves": 3}},
	"night_shift": {"min_level": 5, "waves_after_accept": 1,"npc": "camp", "name": "Die lange Schicht", "requires": "line", "reward": 160, "desc": "Übersteht als Team Welle 4. Vendor braucht Leute, die auch nach dem ersten Ansturm bleiben.", "goals": {"waves": 4}},
	"last_light": {"min_level": 11, "waves_after_accept": 2,"npc": "camp", "name": "Das letzte Licht", "requires": "night_shift", "reward": 240, "desc": "Übersteht Welle 8 und besiegt insgesamt 150 Zombies. Haltet das Lager am Leben.", "goals": {"waves": 8, "kills": 150}},
	"crossfire": {"min_level": 4, "waves_after_accept": 1,"npc": "mechanic", "name": "Kreuzfeuer", "requires": "watch", "reward": 100, "desc": "Stellt zwei aktive Geschütztürme gleichzeitig auf. Beide müssen bei der Abgabe noch stehen.", "goals": {"active_towers": 2}},
	"reinforced": {"min_level": 7, "waves_after_accept": 1,"npc": "mechanic", "name": "Doppelt hält besser", "requires": "crossfire", "reward": 140, "desc": "Verstärkt zwei Barrikaden auf mindestens Stufe 2. Erhaltet beide bis zur Abgabe.", "goals": {"reinforced_barricades": 2}},
	"clockwork": {"min_level": 10, "waves_after_accept": 2,"npc": "mechanic", "name": "Wie ein Uhrwerk", "requires": "reinforced", "reward": 220, "desc": "Baut einen Geschützturm auf Stufe 3 aus und lasst eure Türme insgesamt 40 Zombies besiegen. Der ausgebaute Turm muss noch stehen.", "goals": {"elite_towers": 1, "tower_kills": 40}},
	"silent_deal": {"min_level": 8, "waves_after_accept": 1,"npc": "secret", "name": "Ein diskreter Auftrag", "requires": "marksman_training", "reward": 180, "desc": "Erreicht als Team 40 Kopfschuss-Kills. Hole deine Marksman-Berechtigung beim Secret Vendor ab. Sie erlaubt den Kauf von Präzisionsgewehren; Wellen, Zusatzaufträge und Kaufpreis gelten weiterhin.", "goals": {"headshot_kills": 40}},
	"giant_debt": {"min_level": 11, "waves_after_accept": 1,"npc": "secret", "name": "Die Schuld der Riesen", "requires": "titan", "reward": 260, "desc": "Besiegt insgesamt drei Feldtitanen. Manche Schulden lassen sich nur mit Mut begleichen.", "goals": {"titans": 3}},
	"nameless": {"min_level": 16, "waves_after_accept": 2,"npc": "secret", "name": "Ein Name, den keiner kennt", "requires": "giant_debt", "reward": 380, "desc": "Übersteht Welle 12 und besiegt insgesamt fünf Feldtitanen. Danach sprechen wir als Gleichgestellte.", "goals": {"waves": 12, "titans": 5}},
}
const QUEST_CHAINS := {
	"arrival": {"name": "Ankunft", "quests": ["arrival"]},
	"assault": {"name": "Sturm", "quests": ["line", "night_shift"]},
	"marksman": {"name": "Marksman", "quests": ["steady_aim", "marksman_training", "silent_deal"]},
	"engineer": {"name": "Verteidigungstechnik", "quests": ["watch", "crossfire", "reinforced", "clockwork"]},
	"forest": {"name": "Waldwache", "quests": ["forest_basket", "restless_paths", "forest_watch"]},
	"supplies": {"name": "Versorgung", "quests": ["supplies"]},
	"titans": {"name": "Titanenjagd", "quests": ["titan", "giant_debt", "nameless"]},
	"survival": {"name": "Das Lager bewahren", "quests": ["last_light"]},
}
const GOAL_LABELS := {"edible_mushrooms": "Steinpilze", "runner_kills": "Läufer", "headshot_kills": "Kopfschuss-Kills", "waves": "Wellen", "kills": "Zombies", "active_towers": "Aktive Türme", "reinforced_barricades": "Barrikaden Stufe 2+", "elite_towers": "Türme Stufe 3", "tower_kills": "Turm-Kills", "titans": "Titanen"}
const SKINS := {
	"forest": {"name": "Waldtarn", "price": 160, "npc": "camp", "quest": "line", "desc": "Moos, Oliv und dunkle Erde. Rein optisch."},
	"bronze": {"name": "Rußbronze", "price": 300, "npc": "secret", "quest": "supplies", "desc": "Geschwärztes Metall mit bronzenen Flächen. Rein optisch."},
	"bone": {"name": "Titanenknochen", "price": 480, "npc": "secret", "quest": "titan", "desc": "Helle Knochenstreifen auf dunklem Stahl. Rein optisch."},
}
var game: Node
var npcs: Dictionary = {}
var people: Dictionary = {}
var team := {"kills": 0, "titans": 0, "built": 0, "turned": 0, "cache": false}
var cache_node: Node3D
var cache_ready := false
var is_open := false
var shop := ""
var page := "Handel"
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
const LEGACY_GOAL_LABELS := {"arrival": "Vendor kennenlernen", "built": "Turm bauen",
	"turned": "Turm ausrichten", "built_barricades": "Barrikade bauen", "cache": "Lieferung bergen"}

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
	marker.text = "LIEFERUNG · MECHANIC"
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
		if GOODS[id].get("chain", "") == chain: names.append(Weapons.DEFS[id].name)
	return ", ".join(names)

static func quest_reference(id: String) -> String:
	return "„%s“ bei %s" % [QUESTS[id].name, NPCS[QUESTS[id].npc].name]

func next_quest_step(peer: int, id: String) -> String:
	var next := id
	while not QUESTS[next].requires.is_empty() and not has_claim(peer, QUESTS[next].requires):
		next = QUESTS[next].requires
	var action := "annehmen"
	if mission_level() < int(QUESTS[next].min_level): action = "ab Einsatzlevel %d (aktuell %d)" % [QUESTS[next].min_level, mission_level()]
	if data(peer).accepted.get(next, false):
		action = "Belohnung abholen" if complete(next, peer) else "abschliessen: " + quest_progress(next, peer)
	return "%s – %s" % [quest_reference(next), action]

func prerequisite_reason(peer: int, required: String) -> String:
	if has_claim(peer, required): return ""
	if has_claim(peer, QUESTS[required].requires):
		return "Fehlender Auftrag: %s." % next_quest_step(peer, required)
	return "Fehlender Auftrag: %s. Nächster Schritt: %s." % [quest_reference(required), next_quest_step(peer, required)]

func chain_description(peer: int, chain: String, show_steps := true) -> String:
	var spec: Dictionary = QUEST_CHAINS[chain]
	var count := 0
	var steps := PackedStringArray()
	for id in spec.quests:
		var claimed := has_claim(peer, id)
		if claimed: count += 1
		steps.append(("✓ " if claimed else "") + quest_reference(id))
	var text := "Questreihe %s · %d/%d abgegeben" % [spec.name, count, spec.quests.size()]
	if show_steps: text += "\n" + " → ".join(steps)
	var unlocks := chain_unlocks(chain)
	if not unlocks.is_empty():
		text += "\n%s: Kaufberechtigung für %s. Kaufpreis und Zusatzbedingungen bleiben." % ["Freigeschaltet" if count == spec.quests.size() else "Reihenabschluss", unlocks]
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
	return "[E] Lieferung von Mechanic bergen" if id == "cache" else "[E] %s · %s" % [NPCS[id].name, NPCS[id].role]

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

func quest_lock_reason(peer: int, id: String) -> String:
	var missing := prerequisite_reason(peer, QUESTS[id].requires)
	if not missing.is_empty(): return missing
	var level := int(QUESTS[id].min_level)
	return "Einsatzlevel %d erforderlich (aktuell %d). Überstehe Welle %d." % [level, mission_level(), level - 1] if mission_level() < level else ""

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
			achieved[kind] = "%s %d/%d" % [label, target, target]
	var waves := int(QUESTS[id].waves_after_accept)
	if waves > 0 and game.waves.completed >= required_completion_wave(peer, id):
		achieved["accepted_waves"] = "%d %s nach Annahme überstanden" % [waves, "Welle" if waves == 1 else "Wellen"]
	return achieved

static func _goal_text(text: String, done: bool, rich: bool) -> String:
	return "[color=#79df96]" + text + "[/color]" if rich and done else text

func quest_progress(id: String, peer := -1, rich := false) -> String:
	if peer < 0: peer = game.player.peer_id
	var claimed := has_claim(peer, id)
	var text := _objective_progress(id, rich, claimed)
	if data(peer).accepted.get(id, false) and not claimed and int(QUESTS[id].waves_after_accept) > 0:
		var remaining := maxi(0, required_completion_wave(peer, id) - game.waves.completed)
		text += ("\n" if rich else " · ") + _goal_text("Nach Annahme: noch %d Welle(n) überstehen" % remaining, remaining == 0, rich)
	return text

func _objective_progress(id: String, rich := false, claimed := false) -> String:
	var parts := PackedStringArray()
	if QUESTS.has(id) and QUESTS[id].has("goals"):
		for kind in QUESTS[id].goals:
			var target := int(QUESTS[id].goals[kind])
			parts.append(_goal_text("%s %d/%d" % [GOAL_LABELS[kind], target if claimed else mini(goal_value(kind), target), target], claimed or goal_value(kind) >= target, rich))
	else:
		match id:
			"watch":
				var wall := claimed
				for barricade in game.barricades:
					if barricade.level > 0: wall = true
				parts.append(_goal_text("Turm %d/1" % (1 if claimed else mini(team.built, 1)), claimed or team.built > 0, rich))
				parts.append(_goal_text("Ausrichten %d/1" % (1 if claimed else mini(team.turned, 1)), claimed or team.turned > 0, rich))
				parts.append(_goal_text("Barrikade bauen %d/1" % int(wall), wall, rich))
			"line":
				parts.append(_goal_text("Wellen %d/2" % (2 if claimed else mini(game.waves.completed, 2)), claimed or game.waves.completed >= 2, rich))
				parts.append(_goal_text("Zombies %d/30" % (30 if claimed else mini(team.kills, 30)), claimed or team.kills >= 30, rich))
			"supplies": parts.append(_goal_text("Lieferung geborgen" if claimed or team.cache else "Lieferung an der Kartenmarkierung suchen", claimed or team.cache, rich))
			"titan": parts.append(_goal_text("Titanen %d/1" % (1 if claimed else mini(team.titans, 1)), claimed or team.titans > 0, rich))
			_: parts.append(_goal_text("Vendor am Lagerfeuer kennenlernen", true, rich))
	return ("\n" if rich else " · ").join(parts)

func lock_reason(p: Player, id: String) -> String:
	var spec: Dictionary = GOODS[id]
	var chain: String = spec.get("chain", "")
	if not chain.is_empty() and not chain_complete(p.peer_id, chain):
		for quest in QUEST_CHAINS[chain].quests:
			if not has_claim(p.peer_id, quest):
				return "Berechtigung fehlt: Questreihe %s. Nächster Schritt: %s." % [QUEST_CHAINS[chain].name, next_quest_step(p.peer_id, quest)]
	var missing := prerequisite_reason(p.peer_id, spec.quest)
	if not missing.is_empty(): return missing
	if game.waves.completed < int(spec.wave): return "Welle %d überstehen (%d/%d)" % [spec.wave, game.waves.completed, spec.wave]
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
	if npc not in ["camp", "secret"]: return "Verkaufen kannst du bei Vendor und Secret Vendor."
	var w := weapon_for(p)
	var price := 0
	var label := ""
	match action:
		"sell_meat":
			var stock: Dictionary = game.hunting.stock(p.peer_id)
			if not game.hunting.FOOD.has(id) or int(stock.get(id, 0)) <= 0: return "Dieses Fleisch besitzt du nicht."
			price = int(game.hunting.FOOD[id].sell)
			label = game.hunting.FOOD[id].name
			stock[id] -= 1
		"sell_mushroom":
			var stock := mushroom_stock(p)
			if not Inventory.MUSHROOMS.has(id) or int(stock.get(id, 0)) <= 0: return "Diesen Pilz besitzt du nicht."
			price = int(Inventory.MUSHROOMS[id].sell)
			label = Inventory.MUSHROOMS[id].name
			stock[id] -= 1
		"sell_grenade":
			if w.grenades <= 0: return "Keine Granate im Inventar."
			w.grenades -= 1
			price = 15
			label = "Handgranate"
		"sell_ammo":
			if not Weapons.DEFS.has(id) or Weapons.is_melee(id) or not w.unlocked.get(id, false): return "Munition nicht verfügbar."
			var amount := int(Weapons.DEFS[id].mag)
			if int(w.state[id].reserve) < amount: return "Für den Verkauf brauchst du ein volles Reservemagazin."
			w.state[id].reserve -= amount
			price = ammo_sale_price(id)
			label = "%d Schuss %s" % [amount, Weapons.DEFS[id].name]
		"sell_weapon":
			if not GOODS.has(id) or not w.unlocked.get(id, false): return "Diese Waffe kann nicht verkauft werden."
			price = int(int(GOODS[id].price) * 0.35)
			label = Weapons.DEFS[id].name
			if w.current == id: w.set_weapon("pistol")
			if w._last_firearm == id: w._last_firearm = "pistol"
			w.unlocked[id] = false
			w.state[id].ammo = 0
			w.state[id].reserve = 0
			w.state[id].reloading = 0.0
			w.state[id].cooldown = 0.0
		_: return "Unbekannte Verkaufsaktion."
	p.add_score(price)
	w.update_hud()
	Sfx.event(self, p.peer_id, "purchase")
	return "Verkauft: %s · +%d R" % [label, price]

func mod_lock_reason(p: Player, id: String, wid: String) -> String:
	var w := weapon_for(p)
	if not Weapons.DEFS.has(wid) or not w.unlocked.get(wid, false): return "Diese Waffe besitzt du nicht."
	if not Weapons.Mods.compatible(id, wid, Weapons.DEFS[wid]): return "Nicht mit dieser Waffe kompatibel."
	var spec: Dictionary = Weapons.Mods.DEFS[id]
	var reasons := PackedStringArray()
	if mission_level() < int(spec.level): reasons.append("Einsatzlevel %d benötigt (aktuell %d)." % [spec.level, mission_level()])
	var quest := prerequisite_reason(p.peer_id, spec.quest)
	if not quest.is_empty(): reasons.append(quest)
	return "\n".join(reasons)

func trade_mod(p: Player, npc: String, id: String, wid: String, remove := false) -> String:
	if npc not in ["mechanic", "secret"]: return "Waffen-Mods gibt es bei Mechanic und Secret Vendor."
	var w := weapon_for(p)
	if not Weapons.DEFS.has(wid) or not w.unlocked.get(wid, false): return "Diese Waffe besitzt du nicht."
	var slot := id
	var mod_id := ""
	var cost := 0
	if remove:
		if slot not in Weapons.Mods.SLOTS or not w.mod_loadout.get(wid, {}).has(slot): return "In diesem Platz ist kein Mod montiert."
	else:
		if not Weapons.Mods.DEFS.has(id): return "Unbekannter Waffen-Mod."
		var spec: Dictionary = Weapons.Mods.DEFS[id]
		if spec.npc != npc: return "Dieser Mod wird hier nicht angeboten."
		var reason := mod_lock_reason(p, id, wid)
		if not reason.is_empty(): return reason
		slot = spec.slot
		mod_id = id
		if w.mod_loadout.get(wid, {}).get(slot, "") == id: return "Bereits montiert."
		if not w.mod_owned.get(wid + ":" + id, false): cost = int(spec.price)
	if p.score < cost: return "Zu wenig Rem Dollars: %d R benötigt." % cost
	var updated := w.mod_definition(wid, slot, mod_id)
	var overflow := maxi(0, int(w.state[wid].ammo) - int(updated.mag))
	if int(w.state[wid].reserve) + overflow > w.reserve_limit(wid): return "Reserve voll. Erst Munition verbrauchen, bevor das Magazin verkleinert wird."
	p.add_score(-cost)
	if not remove: w.mod_owned[wid + ":" + id] = true
	w.equip_mod(wid, slot, mod_id)
	Sfx.event(self, p.peer_id, "purchase")
	return "Mod entfernt; bleibt im Besitz." if remove else "Montiert: " + str(Weapons.Mods.DEFS[id].name)

func transact(p: Player, npc: String, action: String, id: String, extra := "") -> String:
	if npc == "wanderer" and action not in ["visit", "rare"]: return "Hier gibt es nur Raritaeten."
	if NetSession.is_client(): return "Der Host bestätigt den Handel."
	if not close_enough(p, npc): return "Gehe zum Händler. Handel ist nur vor Ort möglich."
	if NPCS.get(npc, {}).get("quests_only", false) and action not in ["visit", "quest"]:
		return "Mara vergibt Waldaufträge. Vorräte bekommst du bei Vendor."
	var d := data(p.peer_id)
	var w := weapon_for(p)
	if npc == "secret": d.discovered = true
	if action.begins_with("sell_"): return sell(p, npc, action, id)
	match action:
		"firework":
			if npc != "camp": return "Feuerwerk gibt es bei Vendor am Lagerfeuer."
			return game.fireworks.buy(p, id)
		"visit": return ""
		"rare":
			if npc != "wanderer": return "Diese Raritäten führt nur der Nebelkrämer."
			return rare_market.buy(p, id)
		"mod", "remove_mod": return trade_mod(p, npc, id, extra, action == "remove_mod")
		"autorefill":
			if npc not in ["camp", "secret"]: return "Autorefill gibt es bei Vendor und Secret Vendor."
			var refill := refill_quote(p)
			if refill.missing == 0: return "Alle Magazine und Munitionsreserven sind voll."
			if refill.rounds == 0: return "Zu wenig Rem Dollars für Munition."
			p.add_score(-int(refill.cost))
			for wid in refill.items:
				w.state[wid].ammo += int(refill.items[wid][0])
				w.state[wid].reserve += int(refill.items[wid][1])
				w.state[wid].reloading = 0.0
			w.update_hud()
			Sfx.event(self, p.peer_id, "pickup")
			return "Autorefill: +%d Schuss · −%d R · %s" % [refill.rounds, refill.cost, "alles voll" if refill.rounds == refill.missing else "Teilauffüllung nach Guthaben"]
		"cache":
			if npc != "cache" or team.cache: return "Die Lieferung wurde bereits geborgen."
			if not d.accepted.get("supplies", false): return "Mechanic weiss, wem diese Lieferung gehört. Sprich mit ihr."
			team.cache = true
			cache_node.hide()
			Sfx.event(self, p.peer_id, "pickup")
			return "Lieferung geborgen. Kehre zu Mechanic zurück."
		"quest":
			if not QUESTS.has(id) or QUESTS[id].npc != npc: return "Dieser Auftrag gehört zu einem anderen Händler."
			var q: Dictionary = QUESTS[id]
			if d.claimed.get(id, false): return "Auftrag bereits belohnt."
			var missing := quest_lock_reason(p.peer_id, id)
			if not missing.is_empty(): return missing
			if not d.accepted.get(id, false):
				d.accepted[id] = true
				if not d.has("accepted_wave"): d.accepted_wave = {}
				d.accepted_wave[id] = game.waves.completed
				Sfx.event(self, p.peer_id, "quest_accept")
				return "Auftrag angenommen: " + str(q.name)
			if not complete(id, p.peer_id): return "Auftrag noch nicht erfüllt. " + quest_progress(id, p.peer_id)
			d.claimed[id] = true
			p.add_score(int(q.reward))
			if NetSession.enabled:
				NetSession.feedback(p.peer_id, "quest_complete", [id])
			else:
				notifications.rewarded(id)
			var chain := quest_chain(id)
			if not chain.is_empty() and chain_complete(p.peer_id, chain) and not chain_unlocks(chain).is_empty():
				return "Questreihe %s abgeschlossen · +%d R · Kaufberechtigung: %s" % [QUEST_CHAINS[chain].name, q.reward, chain_unlocks(chain)]
			return "Auftrag abgeschlossen · +%d R · %s" % [q.reward, q.name]
		"weapon":
			if not GOODS.has(id) or GOODS[id].npc != npc: return "Diese Waffe wird hier nicht angeboten."
			if w.unlocked.get(id, false): return "Diese Waffe besitzt du bereits."
			var reason := lock_reason(p, id)
			if not reason.is_empty(): return reason
			if p.score < int(GOODS[id].price): return "Zu wenig Rem Dollars."
			p.add_score(-int(GOODS[id].price))
			w.unlock(id)
			w.state[id].ammo = w.state[id].def.mag
			w.state[id].reserve = int(Weapons.DEFS[id].mag) * 2
			game.achievements.event("weapons")
			Sfx.event(self, p.peer_id, "weapon_pickup")
			if Weapons.is_melee(id): return "Gekauft: %s · Auswahl im Inventar oder mit dem Mausrad" % Weapons.DEFS[id].name
			return "Gekauft: %s · Magazin + 2 Reservemagazine" % Weapons.DEFS[id].name
		"ammo":
			if Weapons.is_melee(id): return "Nahkampfwaffen benötigen keine Munition."
			if npc == "mechanic" or not Weapons.DEFS.has(id) or not w.unlocked.get(id, false): return "Waffe nicht verfügbar."
			var cost := int(GOODS[id].ammo) if GOODS.has(id) else 12
			if int(w.state[id].reserve) >= w.reserve_limit(id): return "Munitionsvorrat voll."
			if p.score < cost: return "Zu wenig Rem Dollars."
			p.add_score(-cost)
			w.add_ammo(id, int(Weapons.DEFS[id].mag) * 2)
			Sfx.event(self, p.peer_id, "pickup")
			return "Zwei Reservemagazine gekauft."
		"medicine", "grenade":
			if npc != "camp": return "Vorräte gibt es bei Vendor."
			var cost := 35 if action == "medicine" else 45
			if action == "medicine" and p.hp >= p.max_hp: return "Gesundheit bereits voll."
			if action == "grenade" and w.grenades >= w.grenades_max: return "Granatentasche voll."
			if p.score < cost: return "Zu wenig Rem Dollars."
			p.add_score(-cost)
			if action == "medicine":
				p.hp = minf(p.max_hp, p.hp + 60)
				p.hud.set_health(p.hp)
			else: w.grenades += 1
			w.update_hud()
			Sfx.event(self, p.peer_id, "pickup")
			return "Vorrat gekauft."
		"skin":
			if not SKINS.has(id) or SKINS[id].npc != npc or not w.unlocked.get(extra, false): return "Lackierung nicht verfügbar."
			var s: Dictionary = SKINS[id]
			var missing := prerequisite_reason(p.peer_id, s.quest)
			if not missing.is_empty(): return missing
			var key := extra + ":" + id
			if not d.skins.get(key, false):
				if p.score < int(s.price): return "Zu wenig Rem Dollars."
				p.add_score(-int(s.price))
				d.skins[key] = true
			w.apply_skin(extra, id)
			Sfx.event(self, p.peer_id, "purchase")
			return "Lackierung angelegt: " + str(s.name)
		"stock_skin":
			if not w.unlocked.get(id, false): return "Waffe nicht verfügbar."
			w.apply_skin(id, "")
			Sfx.event(self, p.peer_id, "purchase")
			return "Originalfinish angelegt."
		"training":
			if npc != "mechanic": return "Training gibt es bei Mechanic."
			return game.skills.purchase(p, w, id)
		"tower_upgrade", "tower_sell":
			if npc != "mechanic" or not id.is_valid_int(): return "Ausbauten gibt es bei Mechanic."
			return game.defences.maintain(p, int(id), action.trim_prefix("tower_"), true)
	return "Unbekannte Aktion."

func request(action: String, id := "", extra := "") -> void:
	if action == "quest" and id == "arrival" and shop == "camp" and not _arrival_guide_read and not local_data().claimed.get(id, false):
		_arrival_guide_pending = true
		vendor_guide.open()
		return
	if NetSession.enabled:
		NetSession.command("shop", [shop, action, id, extra])
		status.text = "Anfrage an den Host …"
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
	page = "Aufträge" if not local_data().claimed.get("arrival", false) or id == "mechanic" or NPCS[id].get("quests_only", false) else "Handel"
	if id == "wanderer": page = "Raritäten"
	is_open = true
	game.player.active = false
	game.weapons.viewmodel.hide()
	for part in game.hud.crosshair_parts: part.hide()
	game.hud.set_prompt("")
	get_tree().paused = not NetSession.enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.show()
	request("visit")
	status.text = "Koop läuft weiter. Bleibe in Deckung." if NetSession.enabled else ""
	_render()

# Local dialogue greeting, also audible during the solo pause. Mara follows the HUD's world-time phases.
const VOCALS := {"camp": "vendor_vocal", "secret": "secret_vendor_vocal", "wanderer": "secret_vendor_vocal", "mechanic": "mechanic_vocal"}
const MARA_VOCALS := {"Morgen": "mara_morning", "Tag": "mara_day", "Abend": "mara_evening", "Nacht": "mara_night"}
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
	if balance: balance.text = "%d REM DOLLARS  ·  EINSATZLEVEL %d  ·  %d WELLEN ÜBERSTANDEN" % [game.player.score, mission_level(), game.waves.completed]

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
	for tab in ["Handel", "Feuerwerk", "Verkaufen", "Aufträge", "Training", "Türme", "Mods", "Skins", "Raritäten"]:
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
	done.text = "Zurück in den Wald · Esc"
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
			_tabs[tab].visible = tab == "Raritäten"
			continue
		_tabs[tab].visible = tab in (["Aufträge"] if NPCS[shop].get("quests_only", false) else (["Aufträge", "Training", "Türme", "Mods"] if shop == "mechanic" else (["Handel", "Verkaufen", "Aufträge", "Mods", "Skins"] if shop == "secret" else ["Handel", "Feuerwerk", "Verkaufen", "Aufträge", "Skins"])))
	var owners := []
	for tower: DefenceTower in game.defences.towers.values(): owners.append([tower.tower_id, tower.owner_peer])
	var layout := str([shop, page, game.weapons.current, game.weapons.unlocked, owners, _mod_weapon, rare_market.stock.keys(), local_data().claimed if page == "Aufträge" else {}])
	_building_layout = layout != _layout_key
	_layout_key = layout
	_row_index = 0
	if _building_layout:
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
		_row_nodes.clear()
	title.text = str(NPCS[shop].name).to_upper() + " · " + page
	subtitle.text = NPCS[shop].line
	_update_balance()
	var p: Player = game.player
	var d := local_data()
	match page:
		"Feuerwerk":
			_info("LICHTER ÜBER DEM WALD", 21)
			_info("Im Inventar [I] auswählen, dann mit Linksklick zünden. Rechtsklick: zur Waffe.\nRaketen steigen etwa 34 m hoch. Reines Feuerwerk ohne Kampfschaden. Vorräte gelten für diese Runde.", 14)
			for id in Fireworks.DEFS:
				var spec: Dictionary = Fireworks.DEFS[id]
				var blocked: String = game.fireworks.buy_error(p, id)
				var detail: String = spec.desc + "\n%d / %d im Inventar · Feuerwerktasche %d / %d" % [game.fireworks.stock(p.peer_id)[id], spec.limit, game.fireworks.count(p.peer_id), Fireworks.CAPACITY]
				_row(spec.name, detail, "%s · %d R" % ["1 Batterie" if Fireworks.is_battery(id) else "5er-Pack" if spec.pack == 5 else "1 Rakete", spec.price], request.bind("firework", id), not blocked.is_empty(), blocked)
		"Raritäten":
			_info("Sortiment wechselt mit Welle, Tageszeit und Standort · Bestand mit allen Spielern geteilt.\nGerade: %s · %s. Ein Talisman aktiv. Auswahl und Spezialmunition im Inventar [I]. Käufe gelten für diese Runde." % ["Tag" if rare_market.phase() == "day" else "Nacht", rare_market.region_name()], 14)
			for id in rare_market.stock:
				var spec: Dictionary = rare_market.Items.DEFS[id]
				var owned: bool = rare_market.data(p.peer_id).owned.get(id, false)
				var blocked := ""
				if not owned:
					if mission_level() < int(spec.level): blocked = "Einsatzlevel %d benötigt (aktuell %d)." % [spec.level, mission_level()]
					elif int(rare_market.stock[id]) <= 0: blocked = "Ausverkauft · Neue Ware beim nächsten Halt oder ab nächster Welle."
					elif p.score < int(spec.price): blocked = "Zu wenig Rem Dollars: %d R benötigt." % spec.price
				_row(spec.name, spec.desc + "\nLevel %d · Bestand %d" % [spec.level, rare_market.stock[id]], "Aktivieren" if owned else "Kaufen · %d R" % spec.price, request.bind("rare", id), not blocked.is_empty(), blocked)
		"Mods": _render_mods(p)
		"Verkaufen":
			var w: Weapons = game.weapons
			var stock := mushroom_stock(p)
			for kind in game.hunting.FOOD:
				var spec: Dictionary = game.hunting.FOOD[kind]
				var count := int(game.hunting.stock(p.peer_id).get(kind, 0))
				_row(spec.name + " · %d im Inventar" % count, spec.text, "1 verkaufen · %d R" % spec.sell, request.bind("sell_meat", kind), count <= 0)
			for kind in Inventory.MUSHROOMS:
				var spec: Dictionary = Inventory.MUSHROOMS[kind]
				var count := int(stock.get(kind, 0))
				_row(spec.name + " · %d im Inventar" % count, spec.text, "1 verkaufen · %d R" % spec.sell, request.bind("sell_mushroom", kind), count <= 0)
			_row("Handgranaten · %d im Inventar" % w.grenades, "Verkaufe eine Granate.", "1 verkaufen · 15 R", request.bind("sell_grenade"), w.grenades <= 0)
			for wid in Weapons.ORDER:
				if not w.unlocked.get(wid, false): continue
				if not Weapons.is_melee(wid):
					var amount := int(Weapons.DEFS[wid].mag)
					_row("Munition · " + Weapons.DEFS[wid].name, "%d Schuss verkaufen. Reserve: %d." % [amount, w.state[wid].reserve], "+%d R" % ammo_sale_price(wid), request.bind("sell_ammo", wid), int(w.state[wid].reserve) < amount)
				if GOODS.has(wid):
					_row(Weapons.DEFS[wid].name, "Waffe verkaufen. Restmunition bringt keinen Aufpreis; Reserve vorher separat verkaufen. Kaufberechtigungen bleiben erhalten.", "+%d R" % int(int(GOODS[wid].price) * 0.35), request.bind("sell_weapon", wid))
		"Aufträge":
			if shop == "camp":
				_row("Grundlagen bei Vendor", "Inventar, Rem Dollars, Türme und Barrikaden · kostenlos nachlesen.", "Einführung ansehen", _replay_vendor_guide)
			for completed in [false, true]:
				var quest_ids: Array = []
				for id in ordered_quests():
					if QUESTS[id].npc == shop and bool(d.claimed.get(id, false)) == completed:
						quest_ids.append(id)
				if quest_ids.is_empty(): continue
				_info("Abgeschlossene" if completed else "Offene Aufträge", 22)
				for id in quest_ids:
					var q: Dictionary = QUESTS[id]
					if q.npc != shop: continue
					var claimed: bool = d.claimed.get(id, false)
					var accepted: bool = d.accepted.get(id, false)
					var blocked := quest_lock_reason(p.peer_id, id)
					var locked := not blocked.is_empty()
					var text := "Erledigt" if claimed else ("Gesperrt" if locked else ("Belohnung abholen" if accepted and complete(id) else ("In Arbeit" if accepted else "Auftrag annehmen")))
					if id == "arrival" and not claimed and not locked and not _arrival_guide_read: text = "Tutorial starten"
					var details: String = q.desc
					var chain := quest_chain(id)
					var heading: String = q.name + " · Level %d · %d R" % [q.min_level, q.reward]
					if not chain.is_empty():
						heading = "%s · %d/%d · %s" % [QUEST_CHAINS[chain].name, QUEST_CHAINS[chain].quests.find(id) + 1, QUEST_CHAINS[chain].quests.size(), heading]
						details += "\n" + chain_description(p.peer_id, chain, false)
					if int(q.waves_after_accept) > 0: details += "\nAb Annahme %d weitere Welle(n) überstehen. Teamziele zählen rückwirkend; Belohnung persönlich abholen." % q.waves_after_accept
					_row(heading, details + "\n" + quest_progress(id, -1, true), text, request.bind("quest", id), claimed or locked or (accepted and not complete(id)), blocked if locked and not claimed else "", true)
		"Handel":
			if shop in ["camp", "secret"]:
				var refill := refill_quote(p)
				var details := "Magazine und Reserve aller eigenen Schusswaffen. Zuerst %s, dann die übrigen Waffen. Granaten separat.\nKomplett: %d R · Mit deinem Guthaben: +%d Schuss für %d R." % [Weapons.DEFS[game.weapons.ammo_weapon()].name, refill.full_cost, refill.rounds, refill.cost]
				_row("Autorefill · gesamte Munition", details, "Alles voll" if refill.missing == 0 else ("Zu wenig Rem Dollars" if refill.rounds == 0 else "Auffüllen · %d R" % refill.cost), request.bind("autorefill"), refill.rounds == 0)
			if shop == "mechanic": _info("Mechanic bietet Training, Turmausbauten und Aufträge an. Waffen und Vorräte gibt es bei Vendor am Lagerfeuer.")
			for id in GOODS:
				var spec: Dictionary = GOODS[id]
				if spec.npc != shop: continue
				var owned: bool = game.weapons.unlocked.get(id, false)
				var reason := lock_reason(p, id)
				var gun: Dictionary = Weapons.DEFS[id]
				var details := "%s\n%d Schaden × %d · %d Schuss · %.1f s Nachladen" % [spec.desc, int(gun.damage), gun.pellets, gun.mag, gun.reload]
				if Weapons.is_melee(id):
					details = "%s\n%d Schaden · %.2f s pro Schlag · %.2f m Reichweite" % [spec.desc, int(gun.damage), gun.rate, gun.range]
				if spec.has("chain"): details += "\n" + chain_description(p.peer_id, spec.chain)
				if gun.has("pierce_targets"): details += "\n" + Weapons.piercing_description(id)
				var blocked := ""
				if not owned:
					if not reason.is_empty(): blocked = "GESPERRT · " + reason
					if p.score < int(spec.price):
						blocked += ("\n" if not blocked.is_empty() else "") + "Es fehlen %d Rem Dollars für den Kauf." % (int(spec.price) - p.score)
				var buy_text := "Im Besitz" if owned else ("Gesperrt · %d R" % spec.price if not reason.is_empty() else "Kaufen · %d R" % spec.price)
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
					_row("Munition · " + str(Weapons.DEFS[wid].name), "Zwei Magazine (+%d Schuss, bis zum Vorratslimit). Vorrat: %d / %d." % [amount, reserve, limit], "Vorrat voll" if full else "%d R" % cost, request.bind("ammo", wid), full or p.score < cost)
			if shop == "camp":
				_row("Verband", "+60 Gesundheit, bis zum Maximum", "35 R", request.bind("medicine"), p.score < 35 or p.hp >= p.max_hp)
				_row("Handgranate", "Eine Granate, bis die Tasche voll ist", "45 R", request.bind("grenade"), p.score < 45 or game.weapons.grenades >= game.weapons.grenades_max)
		"Training":
			if shop != "mechanic": _info("Training gibt es bei Mechanic nördlich des Lagerfeuers.")
			else:
				for spec in Skills.UPGRADES:
					var level: int = game.skills.levels.get(spec.id, 0)
					var cost := int(spec.cost) + int(spec.cost) * level / 2
					_row(spec.name + " · %d/%d" % [level, spec.max], spec.desc, "%d R" % cost, request.bind("training", spec.id), level >= int(spec.max) or p.score < cost)
		"Türme":
			if _building_layout: rows.add_child(ItemIcons.view("tower", Vector2(140, 90)))
			_info("T: Turmtyp wählen · R/Mausrad: drehen · E: platzieren\nAm Turm: E aufsteigen, R ausrichten, F reparieren. Oben: Maus zielt, Linksklick feuert, E steigt ab. Ohne Bediener feuert der Turm automatisch. Dauerfeuer erzeugt Hitze.", 16)
			if shop != "mechanic": _info("Turmausbauten gibt es bei Mechanic.")
			else:
				for id in game.defences.towers:
					var tower: DefenceTower = game.defences.towers[id]
					var cost: int = tower.upgrade_cost()
					_row("%s #%d · Stufe %d" % [tower.spec().name,id,tower.level], "%d/%d TP · %d m Reichweite · %d m entfernt" % [ceili(tower.hp), tower.max_hp(), tower.attack_range(), p.global_position.distance_to(tower.global_position)], "Maximum" if tower.level == 3 else "Ausbauen · %d R" % cost, request.bind("tower_upgrade", str(id)), tower.level == 3 or p.score < cost or tower.operator_peer!=0)
		"Skins":
			var wid: String = game.weapons.current
			_info("Lackierungen für: " + str(Weapons.DEFS[wid].name) + "\nWähle deine Waffe vor dem Gespräch. Skins ändern keine Kampfwerte.", 16)
			for id in SKINS:
				var spec: Dictionary = SKINS[id]
				if spec.npc != shop: continue
				var owned: bool = d.skins.get(wid + ":" + id, false)
				var allowed := has_claim(p.peer_id, spec.quest)
				_row(spec.name, spec.desc + ("" if allowed else "\n" + prerequisite_reason(p.peer_id, spec.quest)), "Anlegen" if owned else "Kaufen · %d R" % spec.price, request.bind("skin", id, wid), not allowed or (not owned and p.score < int(spec.price)))
			_row("Originalfinish", "Kostenlos zum ursprünglichen Material wechseln.", "Anlegen", request.bind("stock_skin", wid))

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
	_info("Mods gelten pro Waffe für diese Runde. Ein Mod je Platz; gekaufte Mods kostenlos wechseln. Munition separat.\nEinsatzlevel = überstandene Wellen + 1.", 14)
	var wid := _mod_weapon
	var effective: Dictionary = w.state[wid].def
	_row(Weapons.DEFS[wid].name, "%d Schaden × %d · %d Schuss · %.2f s Nachladen\n%s" % [roundi(effective.damage * w.effective_damage_mul()), effective.pellets, effective.mag, effective.reload * w.effective_reload_mul(), Weapons.Mods.summary(w.mod_loadout.get(wid, {}))], "Aktuelle Werte", func(): pass, true)
	for id in Weapons.Mods.DEFS:
		var spec: Dictionary = Weapons.Mods.DEFS[id]
		if spec.npc != shop: continue
		var owned: bool = w.mod_owned.get(wid + ":" + id, false)
		var equipped: bool = w.mod_loadout.get(wid, {}).get(spec.slot, "") == id
		var reason := mod_lock_reason(p, id, wid)
		if reason.is_empty() and not owned and p.score < int(spec.price): reason = "Zu wenig Rem Dollars: %d R benötigt." % spec.price
		_row(spec.name + " · Level %d" % spec.level, spec.slot + " · " + spec.desc, "Montiert" if equipped else ("Montieren" if owned else "Kaufen · %d R" % spec.price), request.bind("mod", id, wid), equipped or not reason.is_empty(), reason)
	for slot in Weapons.Mods.SLOTS:
		var installed: String = w.mod_loadout.get(wid, {}).get(slot, "")
		_row(slot, Weapons.Mods.DEFS[installed].name if not installed.is_empty() else "Originalausstattung", "Entfernen", request.bind("remove_mod", slot, wid), installed.is_empty())

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
	tutorial.visible = playing and not game.defences.placing and not game.defences.is_open and not game.player.mounted_tower and not guiding
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
		var signature := str([game.player.score, ceili(game.player.hp), game.weapons.grenades, reserves, mushroom_stock(game.player), game.hunting.stock(game.player.peer_id), game.weapons.unlocked, people, team, game.waves.completed, game.skills.levels, game.weapons.current, structures, game.weapons.mod_owned, game.weapons.mod_loadout, rare_market.stock, rare_market.people, game.fireworks.stock(game.player.peer_id)])
		if signature != _last_signature:
			_last_signature = signature
			_render()
	var d := local_data()
	var tracked: Array[String] = []
	for id in ordered_quests():
		if d.accepted.get(id, false) and not d.claimed.get(id, false):
			tracked.append(id)
	if tracked.is_empty():
		tracker.text = "ALLE AUFTRÄGE ERLEDIGT\nHalte die Hütte und überstehe die nächste Welle." if d.claimed.size() == QUESTS.size() else "AUFTRÄGE · Q ein/aus\nSprich mit Vendor am Lagerfeuer und Mechanic nördlich davon."
		for chain in QUEST_CHAINS:
			if chain_complete(game.player.peer_id, chain): continue
			for id in QUEST_CHAINS[chain].quests:
				if not has_claim(game.player.peer_id, id):
					tracker.text = "%s · NÄCHSTER AUFTRAG\n%s" % [QUEST_CHAINS[chain].name.to_upper(), next_quest_step(game.player.peer_id, id)]
					break
			break
	else:
		var ready := PackedStringArray()
		var ongoing := PackedStringArray()
		for id in tracked:
			if complete(id):
				ready.append("[color=#ffd479][b]BEREIT ZUR ABGABE[/b]\n[b]%s[/b]\nBei %s abgeben · %d R Belohnung[/color]" % [QUESTS[id].name, NPCS[QUESTS[id].npc].name, QUESTS[id].reward])
			else:
				ongoing.append("%s\n%s" % [QUESTS[id].name, quest_progress(id, -1, true)])
		var entries := PackedStringArray(["AUFTRÄGE (%d) · Q ein/aus" % tracked.size()])
		if not ready.is_empty():
			entries.append("[color=#ffd479][b]%d zur Abgabe bereit[/b][/color]" % ready.size())
		entries.append_array(ready)
		entries.append_array(ongoing)
		tracker.text = "\n\n".join(entries)
	tracker.size.y = 0
	if not d.claimed.get("arrival", false):
		tutorial.text = "WAFFEN & AUFTRÄGE\n[E] Sprich mit Vendor am Lagerfeuer."
	elif _arrival_guide_read and not _arrival_inventory_seen:
		tutorial.text = "DEINE AUSRÜSTUNG · [I] INVENTAR\nÖffne dein Inventar und sieh dir Waffen und Gegenstände an."
	elif _arrival_guide_read and not _arrival_build_menu_seen:
		tutorial.text = "DEINE VERTEIDIGUNG · [T] TURMBAUMENÜ\nSieh dir die Türme an. Erst E in der Vorschau bestätigt einen Kauf."
	elif team.built == 0:
		tutorial.text = "VERTEIDIGUNG · [T] TURMBAUMENÜ\n5 Typen ab 120 R · E baut / steigt auf · Mechanic baut aus." if _tower_tutorial_remaining > 0.0 else ""
	elif team.turned == 0:
		tutorial.text = "RICHTE DEINEN WÄCHTER AUS\nAm Turm R drücken, mit R/Mausrad drehen und mit E bestätigen."
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

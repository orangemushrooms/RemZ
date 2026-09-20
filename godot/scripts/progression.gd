class_name Progression
extends CanvasLayer

# One authoritative catalogue is shared by the UI, solo game and host validation.
const NPCS := {
	"camp": {"name": "Vendor", "role": "Waffen & Vorräte", "model": "npc_quartermaster", "height": 1.82, "pos": Vector2(4.0, -16.0), "line": "Bleib am Leben. Ich handle mit Leuten, die ihren Teil beitragen."},
	"mechanic": {"name": "Mechanic", "role": "Verteidigung & Training", "model": "npc_mechanic", "height": 1.7, "pos": Vector2(-5, -24), "line": "Eine Sperre hält sie auf. Ein richtig ausgerichteter Wächter erledigt den Rest."},
	"secret": {"name": "Secret Vendor", "role": "Seltene Ausrüstung", "model": "npc_secret_trader", "height": 1.9, "pos": Vector2(-43, -119), "line": "Du hast mich gefunden. Jetzt zeig mir, dass du diese Waffen führen kannst."},
}
const CACHE := Vector2(-64, -147)
const GOODS := {
	"revolver": {"npc": "camp", "price": 220, "wave": 1, "quest": "arrival", "ammo": 24, "desc": "Präzise und sparsam. Sechs schwere Schüsse."},
	"smg": {"npc": "camp", "price": 400, "wave": 2, "quest": "watch", "ammo": 30, "desc": "Schnelle Läufer abfangen. Hoher Munitionsverbrauch."},
	"shotgun": {"npc": "camp", "price": 340, "wave": 2, "quest": "arrival", "ammo": 28, "desc": "Starke Nahverteidigung. Auf Distanz wenig wirksam."},
	"ak47": {"npc": "camp", "price": 780, "wave": 4, "quest": "line", "ammo": 44, "desc": "Vielseitiges Sturmgewehr mit kräftigem Rückstoss."},
	"marksman": {"npc": "camp", "price": 680, "wave": 3, "quest": "supplies", "ammo": 40, "desc": "Repetiergewehr. Langsam, präzise und durchschlagsstark."},
	"lmg": {"npc": "secret", "price": 1350, "wave": 5, "quest": "supplies", "ammo": 90, "desc": "60 Schuss gegen die Horde. Lange Nachladepause."},
	"breacher": {"npc": "secret", "price": 1650, "wave": 6, "quest": "titan", "ammo": 70, "desc": "Halbautomatische Sturmschrotflinte. Nur für kurze Distanzen."},
	"titanbreaker": {"npc": "secret", "price": 2400, "wave": 9, "quest": "titan", "ammo": 110, "desc": "Titanenbrecher .50. 75 % Zusatzschaden gegen Titanen, teure Munition."},
}
const QUESTS := {
	"arrival": {"npc": "camp", "name": "Am Feuer", "requires": "", "reward": 20, "desc": "Sprich mit Vendor am Lagerfeuer. Er erklärt dir Handel und Versorgung."},
	"watch": {"npc": "mechanic", "name": "Der erste Wächter", "requires": "arrival", "reward": 110, "desc": "Baue eine Barrikade und einen Turm. Richte den Turm anschliessend neu aus. T: Vorschau · R/Mausrad: drehen · E: bestätigen. Am Turm E: ausrichten, F: reparieren."},
	"line": {"npc": "camp", "name": "Die Linie halten", "requires": "arrival", "reward": 140, "desc": "Übersteht als Team zwei Wellen und besiegt 30 Zombies. Kehre zu Vendor zurück."},
	"supplies": {"npc": "mechanic", "name": "Die verlorene Lieferung", "requires": "watch", "reward": 180, "desc": "Folge dem nördlichen Waldweg bis kurz vor den Abzweig zum Teich. Rechts des Weges liegt eine markierte Werkzeugkiste. Bringe die Lieferung zu Mechanic. Ein Händler soll weiter südöstlich im Wald lagern."},
	"titan": {"npc": "secret", "name": "Was auf dem Feld lauert", "requires": "supplies", "reward": 300, "desc": "Besiegt gemeinsam einen Feldtitanen. Sie erscheinen ab Welle 6. Hole danach deine Belohnung beim Secret Vendor ab."},
}
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
var is_open := false
var shop := ""
var page := "Handel"
var panel: Control
var rows: VBoxContainer
var title: Label
var subtitle: Label
var balance: Label
var status: Label
var tracker: Label
var tutorial: Label
var _tabs: Dictionary = {}
var _row_nodes: Array = []
var _row_index := 0
var _layout_key := ""
var _building_layout := false
var _refresh_time := 0.0
var _last_signature := ""
var _journal := true

static func clear_space() -> void:
	# Deterministic clearings, before forests and navmesh are constructed on every peer.
	var centers: Array = [CACHE]
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
	cache_node = Node3D.new()
	cache_node.position = Map.ground_pos(CACHE.x, CACHE.y)
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

func data(peer: int) -> Dictionary:
	if not people.has(peer): people[peer] = {"accepted": {}, "claimed": {}, "skins": {}, "discovered": false}
	return people[peer]

func local_data() -> Dictionary:
	return data(NetSession.local_id() if NetSession.enabled else game.player.peer_id)

func has_claim(peer: int, quest: String) -> bool:
	return quest.is_empty() or data(peer).claimed.get(quest, false)

func weapon_for(p: Player) -> Weapons:
	return NetSession.world.weapons[p.peer_id] if NetSession.is_host() else game.weapons

func close_enough(p: Player, id: String) -> bool:
	if not p.alive or not game.started or game.over: return false
	var target: Vector3
	var body: Object = null
	if id == "cache": target = cache_node.global_position + Vector3.UP * 0.6
	elif npcs.has(id):
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
	if kind in ["kills", "titans", "built", "turned"]: team[kind] += 1

func complete(quest: String) -> bool:
	match quest:
		"arrival": return true
		"watch":
			var wall := false
			for b: Barricade in game.barricades:
				if b.level > 0: wall = true
			return team.built > 0 and team.turned > 0 and wall
		"line": return game.waves.completed >= 2 and team.kills >= 30
		"supplies": return team.cache
		"titan": return team.titans > 0
	return false

func quest_progress(id: String) -> String:
	match id:
		"watch": return "Turm %d/1 · Ausrichten %d/1 · Barrikade bauen" % [mini(team.built, 1), mini(team.turned, 1)]
		"line": return "Wellen %d/2 · Zombies %d/30" % [mini(game.waves.completed, 2), mini(team.kills, 30)]
		"supplies": return "Lieferung geborgen" if team.cache else "Lieferung am nördlichen Waldweg suchen"
		"titan": return "Titanen %d/1" % mini(team.titans, 1)
	return "Vendor am Lagerfeuer kennenlernen"

func lock_reason(p: Player, id: String) -> String:
	var spec: Dictionary = GOODS[id]
	if not has_claim(p.peer_id, spec.quest): return "Auftrag abschliessen: " + str(QUESTS[spec.quest].name)
	if game.waves.completed < int(spec.wave): return "Welle %d überstehen (%d/%d)" % [spec.wave, game.waves.completed, spec.wave]
	return ""

func transact(p: Player, npc: String, action: String, id: String, extra := "") -> String:
	if NetSession.is_client(): return "Der Host bestätigt den Handel."
	if not close_enough(p, npc): return "Gehe zum Händler. Handel ist nur vor Ort möglich."
	var d := data(p.peer_id)
	var w := weapon_for(p)
	if npc == "secret": d.discovered = true
	match action:
		"visit": return ""
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
			if not has_claim(p.peer_id, q.requires): return "Schliesse zuerst den vorherigen Auftrag ab."
			if not d.accepted.get(id, false):
				d.accepted[id] = true
				Sfx.event(self, p.peer_id, "quest_accept")
				return "Auftrag angenommen: " + str(q.name)
			if not complete(id): return "Auftrag noch nicht erfüllt. " + quest_progress(id)
			d.claimed[id] = true
			p.add_score(int(q.reward))
			Sfx.event(self, p.peer_id, "quest_complete")
			return "Auftrag abgeschlossen · +%d P · %s" % [q.reward, q.name]
		"weapon":
			if not GOODS.has(id) or GOODS[id].npc != npc: return "Diese Waffe wird hier nicht angeboten."
			if w.unlocked.get(id, false): return "Diese Waffe besitzt du bereits."
			var reason := lock_reason(p, id)
			if not reason.is_empty(): return reason
			if p.score < int(GOODS[id].price): return "Zu wenig Punkte."
			p.add_score(-int(GOODS[id].price))
			w.unlock(id)
			w.state[id].ammo = Weapons.DEFS[id].mag
			w.state[id].reserve = int(Weapons.DEFS[id].mag) * 2
			game.achievements.event("weapons")
			Sfx.event(self, p.peer_id, "weapon_pickup")
			return "Gekauft: %s · Magazin + 2 Reservemagazine" % Weapons.DEFS[id].name
		"ammo":
			if npc == "mechanic" or not Weapons.DEFS.has(id) or not w.unlocked.get(id, false): return "Waffe nicht verfügbar."
			var cost := int(GOODS[id].ammo) if GOODS.has(id) else 12
			if int(w.state[id].reserve) >= w.reserve_limit(id): return "Munitionsvorrat voll."
			if p.score < cost: return "Zu wenig Punkte."
			p.add_score(-cost)
			w.add_ammo(id, int(Weapons.DEFS[id].mag) * 2)
			Sfx.event(self, p.peer_id, "pickup")
			return "Zwei Reservemagazine gekauft."
		"medicine", "grenade":
			if npc != "camp": return "Vorräte gibt es bei Vendor."
			var cost := 35 if action == "medicine" else 45
			if action == "medicine" and p.hp >= p.max_hp: return "Gesundheit bereits voll."
			if action == "grenade" and w.grenades >= w.grenades_max: return "Granatentasche voll."
			if p.score < cost: return "Zu wenig Punkte."
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
			if not has_claim(p.peer_id, s.quest): return "Auftrag abschliessen: " + str(QUESTS[s.quest].name)
			var key := extra + ":" + id
			if not d.skins.get(key, false):
				if p.score < int(s.price): return "Zu wenig Punkte."
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
	if NetSession.enabled:
		NetSession.command("shop", [shop, action, id, extra])
		status.text = "Anfrage an den Host …"
	else:
		status.text = transact(game.player, shop, action, id, extra)
	_last_signature = ""

func interact(id: String) -> void:
	if id == "cache":
		if NetSession.enabled: NetSession.command("shop", [id, "cache", "", ""])
		else: game.hud.message(transact(game.player, id, "cache", ""), 3)
		return
	if not game.player.active or not close_enough(game.player, id): return
	shop = id
	page = "Aufträge" if not local_data().claimed.get("arrival", false) or id == "mechanic" else "Handel"
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

func close() -> void:
	if not is_open: return
	is_open = false
	panel.hide()
	get_tree().paused = false
	game.player.active = game.player.alive and not game.over
	game.weapons.viewmodel.visible = game.player.active
	for part in game.hud.crosshair_parts: part.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if game.player.active else Input.MOUSE_MODE_VISIBLE
	game.defences.input_grace = 0.25

func _label(text: String, size := 18) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _build_ui() -> void:
	tracker = _label("", 16)
	tracker.position = Vector2(26, 154)
	tracker.size = Vector2(355, 150)
	tracker.add_theme_color_override("font_color", Color(0.93, 0.83, 0.61))
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
	column.add_child(balance)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	for tab in ["Handel", "Aufträge", "Training", "Türme", "Skins"]:
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
	status = _label("", 15)
	status.custom_minimum_size.y = 38
	status.add_theme_color_override("font_color", Color(0.94, 0.78, 0.5))
	column.add_child(status)
	var done := Button.new()
	done.text = "Zurück in den Wald · Esc"
	done.custom_minimum_size.y = 40
	done.pressed.connect(close)
	column.add_child(done)
	panel.hide()

func _row(heading: String, details: String, button_text: String, action: Callable, disabled := false) -> void:
	# Updating prices and quest counters must preserve the button receiving a click.
	if not _building_layout:
		var widgets: Array = _row_nodes[_row_index]
		widgets[0].text = heading
		widgets[1].text = details
		widgets[2].text = button_text
		widgets[2].disabled = disabled
		widgets[3].texture = ItemIcons.texture(ItemIcons.action_id(action))
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
	var desc := _label(details, 14)
	desc.modulate = Color(0.72, 0.8, 0.72)
	text.add_child(desc)
	var button := Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(205, 45)
	button.disabled = disabled
	button.pressed.connect(action)
	box.add_child(button)
	rows.add_child(HSeparator.new())
	_row_nodes.append([heading_label, desc, button, icon])
	_row_index += 1

func _info(text: String, size := 18) -> void:
	if _building_layout: rows.add_child(_label(text, size))

func _render() -> void:
	for tab in _tabs:
		_tabs[tab].visible = tab in (["Aufträge", "Training", "Türme"] if shop == "mechanic" else ["Handel", "Aufträge", "Skins"])
	var owners := []
	for tower: DefenceTower in game.defences.towers.values(): owners.append([tower.tower_id, tower.owner_peer])
	var layout := str([shop, page, game.weapons.current, owners])
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
	balance.text = "%d PUNKTE  ·  %d WELLEN ÜBERSTANDEN" % [game.player.score, game.waves.completed]
	var p: Player = game.player
	var d := local_data()
	match page:
		"Aufträge":
			for id in QUESTS:
				var q: Dictionary = QUESTS[id]
				if q.npc != shop: continue
				var claimed: bool = d.claimed.get(id, false)
				var accepted: bool = d.accepted.get(id, false)
				var locked := not has_claim(p.peer_id, q.requires)
				var text := "Erledigt" if claimed else ("Vorheriger Auftrag fehlt" if locked else ("Belohnung abholen" if accepted and complete(id) else ("In Arbeit" if accepted else "Auftrag annehmen")))
				_row(q.name + " · %d P" % q.reward, q.desc + "\n" + quest_progress(id), text, request.bind("quest", id), claimed or locked or (accepted and not complete(id)))
		"Handel":
			if shop == "mechanic": _info("Mechanic bietet Training, Turmausbauten und Aufträge an. Waffen und Vorräte gibt es bei Vendor am Lagerfeuer.")
			for id in GOODS:
				var spec: Dictionary = GOODS[id]
				if spec.npc != shop: continue
				var owned: bool = game.weapons.unlocked.get(id, false)
				var reason := lock_reason(p, id)
				var gun: Dictionary = Weapons.DEFS[id]
				var details := "%s\n%d Schaden × %d · %d Schuss · %.1f s Nachladen\n%s" % [spec.desc, int(gun.damage), gun.pellets, gun.mag, gun.reload, "Im Besitz" if owned else reason]
				_row(gun.name, details, "Im Besitz" if owned else "Kaufen · %d P" % spec.price, request.bind("weapon", id), owned or not reason.is_empty() or p.score < int(spec.price))
			if shop != "mechanic":
				var wid: String = game.weapons.current
				var cost := int(GOODS[wid].ammo) if GOODS.has(wid) else 12
				_row("Munition · " + str(Weapons.DEFS[wid].name), "Zwei Magazine. Vorratslimit: %d Schuss. Waffe im Inventar auswählen." % game.weapons.reserve_limit(wid), "%d P" % cost, request.bind("ammo", wid), p.score < cost)
			if shop == "camp":
				_row("Verband", "+60 Gesundheit, bis zum Maximum", "35 P", request.bind("medicine"), p.score < 35 or p.hp >= p.max_hp)
				_row("Handgranate", "Eine Granate, bis die Tasche voll ist", "45 P", request.bind("grenade"), p.score < 45 or game.weapons.grenades >= game.weapons.grenades_max)
		"Training":
			if shop != "mechanic": _info("Training gibt es bei Mechanic nördlich des Lagerfeuers.")
			else:
				for spec in Skills.UPGRADES:
					var level: int = game.skills.levels.get(spec.id, 0)
					var cost := int(spec.cost) + int(spec.cost) * level / 2
					_row(spec.name + " · %d/%d" % [level, spec.max], spec.desc, "%d P" % cost, request.bind("training", spec.id), level >= int(spec.max) or p.score < cost)
		"Türme":
			if _building_layout: rows.add_child(ItemIcons.view("tower", Vector2(140, 90)))
			_info("T: Bauvorschau · R/Mausrad: drehen · E: platzieren\nAm Turm: E zum Ausrichten, F zum Reparieren. 160° Feuersektor, freie Sicht nötig. Dauerfeuer führt zum Abkühlen.", 16)
			if shop != "mechanic": _info("Ausbauten und Abbau verwaltet Mechanic. Nur eigene Türme können verkauft werden.")
			else:
				for id in game.defences.towers:
					var tower: DefenceTower = game.defences.towers[id]
					var cost: int = DefenceTower.UPGRADES[mini(tower.level - 1, 1)]
					_row("Wächter #%d · Stufe %d" % [id, tower.level], "%d/%d TP · %d m Reichweite · %d m entfernt" % [ceili(tower.hp), tower.max_hp(), DefenceTower.RANGE[tower.level - 1], p.global_position.distance_to(tower.global_position)], "Maximum" if tower.level == 3 else "Ausbauen · %d P" % cost, request.bind("tower_upgrade", str(id)), tower.level == 3 or p.score < cost)
					if tower.owner_peer == p.peer_id: _row("Wächter #%d abbauen" % id, "Der Turm wird entfernt. 40 Punkte zurück.", "Abbauen", request.bind("tower_sell", str(id)))
		"Skins":
			var wid: String = game.weapons.current
			_info("Lackierungen für: " + str(Weapons.DEFS[wid].name) + "\nWähle deine Waffe vor dem Gespräch. Skins ändern keine Kampfwerte.", 16)
			for id in SKINS:
				var spec: Dictionary = SKINS[id]
				if spec.npc != shop: continue
				var owned: bool = d.skins.get(wid + ":" + id, false)
				var allowed := has_claim(p.peer_id, spec.quest)
				_row(spec.name, spec.desc + ("" if allowed else "\nAuftrag: " + str(QUESTS[spec.quest].name)), "Anlegen" if owned else "Kaufen · %d P" % spec.price, request.bind("skin", id, wid), not allowed or (not owned and p.score < int(spec.price)))
			_row("Originalfinish", "Kostenlos zum ursprünglichen Material wechseln.", "Anlegen", request.bind("stock_skin", wid))

func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif game.started and not game.over and game.player.active and event.is_action_pressed("skills"):
		_journal = not _journal
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not game: return
	if is_open and not close_enough(game.player, shop): close()
	var playing: bool = game.started and not game.over and game.player.active and not game.hud.overlay.visible
	var guiding: bool = game.intro != null and game.intro.showing_guidance()
	tracker.visible = playing and _journal and not game.defences.placing and not guiding
	tutorial.visible = playing and not game.defences.placing and not guiding
	_refresh_time -= delta
	if _refresh_time > 0: return
	_refresh_time = 0.25
	cache_node.visible = not team.cache
	if is_open:
		var structures := []
		for tower: DefenceTower in game.defences.towers.values(): structures.append([tower.tower_id, tower.level, ceili(tower.hp)])
		var signature := str([game.player.score, ceili(game.player.hp), game.weapons.grenades, game.weapons.cur().reserve, game.weapons.unlocked, people, team, game.waves.completed, game.skills.levels, game.weapons.current, structures])
		if signature != _last_signature:
			_last_signature = signature
			_render()
	var d := local_data()
	var tracked := ""
	for id in QUESTS:
		if d.accepted.get(id, false) and not d.claimed.get(id, false):
			tracked = id
			break
	if tracked.is_empty():
		tracker.text = "ALLE AUFTRÄGE ERLEDIGT\nHalte die Hütte und überstehe die nächste Welle." if d.claimed.size() == QUESTS.size() else "AUFTRÄGE · TAB ein/aus\nSprich mit Vendor am Lagerfeuer und Mechanic nördlich davon."
	else:
		tracker.text = "AUFTRAG · " + str(QUESTS[tracked].name) + "\n" + ("Erfüllt · Belohnung bei " + str(NPCS[QUESTS[tracked].npc].name) + " abholen" if complete(tracked) else quest_progress(tracked))
	if not d.claimed.get("arrival", false):
		tutorial.text = "WAFFEN & AUFTRÄGE\n[E] Sprich mit Vendor am Lagerfeuer."
	elif team.built == 0:
		tutorial.text = "VERTEIDIGUNG · [T] GESCHÜTZTURM\n120 P · R/Mausrad dreht die Vorschau · E baut · Mechanic erklärt den Ausbau."
	elif team.turned == 0:
		tutorial.text = "RICHTE DEINEN WÄCHTER AUS\nAm Turm E drücken, mit R/Mausrad drehen und mit E bestätigen."
	else: tutorial.text = ""

func snapshot() -> Dictionary:
	return {"people": people.duplicate(true), "team": team.duplicate(true)}

func apply_snapshot(s: Dictionary) -> void:
	people = s.get("people", {}).duplicate(true)
	team = s.get("team", team).duplicate(true)

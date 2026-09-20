class_name Fireworks
extends Node3D

const Effect = preload("res://scripts/firework_effect.gd")
const CAPACITY := 32
const MAX_ACTIVE := 12
const DEFS := {
	"fw_ruby": {"name": "Rubinstern", "price": 45, "pack": 1, "limit": 8, "rocket": true, "color": Color(1, 0.08, 0.16), "desc": "Rote Sternenkugel mit silbernem Kern und funkelnden Schweifen."},
	"fw_aurora": {"name": "Polarlicht", "price": 60, "pack": 1, "limit": 8, "rocket": true, "color": Color(0.18, 1, 0.65), "desc": "Smaragdgrüne Sterne mit violetten Spitzen und einem leuchtenden Ring."},
	"fw_gold": {"name": "Goldweide", "price": 85, "pack": 1, "limit": 8, "rocket": true, "color": Color(1, 0.65, 0.16), "desc": "Eine grosse goldene Krone mit langen, langsam fallenden Glutspuren und Knistern."},
	"fw_cracker": {"name": "Walddonner", "price": 35, "pack": 5, "limit": 20, "rocket": false, "color": Color(1, 0.3, 0.1), "desc": "Fünf einzelne Böller: kurze Wurfbahn, knisternde Lunte, kräftiger Knall mit Funken und Rauch."},
}
var game: Node3D
var stocks: Dictionary = {}
var cooldowns: Dictionary = {}
var active: Dictionary = {}
var next_id := 1
var selected := ""
var armed := false
var input_grace := 0.0
var held: Node3D
var hint: Label
var _clock := 0.0

func setup(scene: Node3D) -> void:
	game = scene
	var ui := CanvasLayer.new()
	ui.layer = 6
	add_child(ui)
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-340, -150)
	hint.size = Vector2(680, 84)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 19)
	hint.add_theme_color_override("font_color", Color(1, 0.83, 0.5))
	hint.add_theme_constant_override("outline_size", 6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hint)
	hint.hide()

func stock(peer: int) -> Dictionary:
	if not stocks.has(peer):
		stocks[peer] = {}
		for id in DEFS: stocks[peer][id] = 0
	return stocks[peer]

func count(peer: int) -> int:
	var total := 0
	for amount in stock(peer).values(): total += int(amount)
	return total

func buy_error(p: Player, id: String) -> String:
	if not DEFS.has(id): return "Unbekanntes Feuerwerk."
	var d: Dictionary = DEFS[id]
	if not p.alive: return "Du bist ausser Gefecht."
	if int(stock(p.peer_id)[id]) + int(d.pack) > int(d.limit) or count(p.peer_id) + int(d.pack) > CAPACITY:
		return "Feuerwerktasche voll für dieses Paket."
	if p.score < int(d.price): return "Zu wenig Punkte: %d P benötigt." % d.price
	return ""

func buy(p: Player, id: String) -> String:
	if NetSession.is_client(): return "Der Host bestätigt den Kauf."
	var error := buy_error(p, id)
	if not error.is_empty(): return error
	var d: Dictionary = DEFS[id]
	p.add_score(-int(d.price))
	stock(p.peer_id)[id] += int(d.pack)
	Sfx.event(self, p.peer_id, "purchase")
	return "%s ×%d gekauft · Im Inventar [I] auswählen." % [d.name, d.pack]

func select(id: String) -> void:
	if not DEFS.has(id) or int(stock(game.player.peer_id)[id]) <= 0: return
	if not game.player.alive or game.over: return
	if game.inventory.is_open: game.inventory.close()
	selected = id
	armed = true
	input_grace = 0.3
	game.weapons._reset_scope()
	game.weapons.viewmodel.hide()
	if is_instance_valid(held): held.queue_free()
	held = Effect.model(bool(DEFS[id].rocket))
	game.player.camera.add_child(held)
	held.position = Vector3(0.27, -0.34, -0.55)
	held.rotation = Vector3(-0.15, 0.3, -0.15)
	if not DEFS[id].rocket: held.scale = Vector3.ONE * 1.4

func cancel() -> void:
	if not armed: return
	armed = false
	if is_instance_valid(held): held.queue_free()
	hint.hide()
	game.weapons.viewmodel.visible = game.player.active and game.player.alive
	input_grace = 0.2

func _unhandled_input(event: InputEvent) -> void:
	if not armed or not game.player.active: return
	if event.is_action_pressed("aim") or event.is_action_pressed("weapon_next") or event.is_action_pressed("weapon_prev"):
		cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode >= KEY_0 and event.keycode <= KEY_9:
		cancel()

func _process(delta: float) -> void:
	_clock += delta
	input_grace = maxf(0, input_grace - delta)
	for peer in cooldowns: cooldowns[peer] = maxf(0, float(cooldowns[peer]) - delta)
	for id in active.keys():
		if not is_instance_valid(active[id]): active.erase(id)
	if not armed: return
	if not game.player.alive or game.over:
		cancel()
		return
	var playing: bool = game.player.active
	game.weapons.viewmodel.hide()
	if is_instance_valid(held):
		held.visible = playing
		held.position.y = -0.34 + sin(_clock * 2.4) * 0.005
	hint.visible = playing
	hint.text = "%s · %d Stück\nLinksklick: %s · Rechtsklick: zurück zur Waffe" % [DEFS[selected].name, stock(game.player.peer_id)[selected], "aufstellen & zünden" if DEFS[selected].rocket else "anzünden & werfen"]
	if playing and input_grace <= 0 and Input.is_action_just_pressed("fire"):
		input_grace = 0.65
		if NetSession.enabled:
			NetSession.command("firework", [selected, game.player.rotation.y, game.player.pitch])
		else:
			var error := ignite(game.player, selected)
			if not error.is_empty(): game.hud.message(error, 2.0)
	if int(stock(game.player.peer_id)[selected]) <= 0: cancel()

# Only the host chooses launch positions and consumes stock. Peers reproduce its timeline.
func ignite(p: Player, id: String) -> String:
	if NetSession.is_client(): return "Der Host bestätigt das Zünden."
	if not DEFS.has(id) or not p.alive or not p.active or game.over: return "Feuerwerk ist gerade nicht möglich."
	if int(stock(p.peer_id)[id]) <= 0: return "Kein Feuerwerk dieser Sorte mehr."
	if float(cooldowns.get(p.peer_id, 0)) > 0: return "Einen Moment bis zum nächsten Feuerwerk."
	var alive_effects := 0
	for effect in active.values():
		if is_instance_valid(effect): alive_effects += 1
	if alive_effects >= MAX_ACTIVE: return "Warte kurz, bis das Feuerwerk abgeklungen ist."
	var forward := -p.global_basis.z
	var eye := p.camera.global_position
	var origin := eye + forward * 0.5
	var landing := origin
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [p.get_rid()]
	if DEFS[id].rocket:
		var target := p.global_position + forward * 1.8
		var sight := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target + Vector3.UP * 0.7, 1 | 8, exclude))
		if not sight.is_empty(): return "Vor dir ist kein Platz zum Aufstellen."
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(target + Vector3.UP * 1.8, target - Vector3.UP * 2.5, 1 | 8, exclude))
		if ground.is_empty() or ground.normal.y < 0.8: return "Stelle die Rakete auf einen ebenen Untergrund."
		origin = ground.position + Vector3.UP * 0.03
		var ceiling := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.8, origin + Vector3.UP * 40, 1 | 8, exclude))
		if not ceiling.is_empty(): return "Die Rakete braucht freien Himmel über sich."
		landing = origin
	else:
		# Trace the complete short arc so a thrown cracker cannot cross a wall.
		origin = eye
		var velocity := -p.head.global_basis.z * 7.0 + Vector3.UP * 2.0
		var previous := origin
		for step in range(1, 41):
			var t := step * 0.05
			var at := origin + velocity * t + Vector3.DOWN * 4.9 * t * t
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(previous, at, 1 | 8, exclude))
			if not hit.is_empty():
				landing = hit.position + hit.normal * 0.07
				break
			landing = at
			previous = at
	stock(p.peer_id)[id] -= 1
	cooldowns[p.peer_id] = 0.9
	var effect = Effect.new()
	effect.configure(id, origin, landing, randi() & 0x7fffffff, 0.0)
	add_child(effect)
	active[next_id] = effect
	next_id += 1
	return ""

func snapshot() -> Dictionary:
	var live := {}
	for id in active:
		if is_instance_valid(active[id]): live[id] = active[id].state()
	return {"stocks": stocks.duplicate(true), "active": live}

func apply_snapshot(data: Dictionary) -> void:
	var previous: Dictionary = stock(game.player.peer_id).duplicate()
	stocks = data.get("stocks", {}).duplicate(true)
	if game.inventory.is_open and previous != stock(game.player.peer_id): game.inventory._refresh()
	var live: Dictionary = data.get("active", {})
	for id in active.keys():
		if not live.has(id):
			if is_instance_valid(active[id]): active[id].queue_free()
			active.erase(id)
	for id in live:
		var s: Array = live[id]
		if not active.has(id) or not is_instance_valid(active[id]):
			var effect = Effect.new()
			effect.configure(s[0], s[1], s[2], s[3], s[4])
			add_child(effect)
			active[id] = effect
		elif absf(active[id].age - float(s[4])) > 0.35:
			active[id].age = maxf(active[id].age, float(s[4]))

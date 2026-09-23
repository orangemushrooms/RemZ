class_name Fireworks
extends Node3D

const Effect = preload("res://scripts/firework_effect.gd")
const Battery = preload("res://scripts/firework_battery.gd")
const CAPACITY := 32
const MAX_ACTIVE := 12
const DEFS := {
	"fw_battery_40": {"name": "Star Festival · Battery", "price": 650, "pack": 1, "limit": 2, "rocket": true, "duration": 40.0, "shots": 36, "model": "firework_battery_40", "width": 0.8, "color": Color(0.7, 0.3, 1), "desc": "Large firework battery: 40 seconds of red, green and golden aerial stars with a faster finale. Set it up on level ground under open sky. No combat damage."},
	"fw_battery_90": {"name": "Sky Festival · XL Battery", "price": 1400, "pack": 1, "limit": 1, "rocket": true, "duration": 90.0, "shots": 84, "model": "firework_battery_90", "width": 1.25, "color": Color(1, 0.65, 0.15), "desc": "Huge compound battery: 90 seconds of colorful fan salvos and golden crowns with a dense grand finale. Needs plenty of free space and open sky. No combat damage."},
	"fw_ruby": {"name": "Ruby Star", "price": 45, "pack": 1, "limit": 8, "rocket": true, "color": Color(1, 0.08, 0.16), "desc": "Red star shell with a silver core and sparkling tails."},
	"fw_aurora": {"name": "Aurora", "price": 60, "pack": 1, "limit": 8, "rocket": true, "color": Color(0.18, 1, 0.65), "desc": "Emerald green stars with violet tips and a glowing ring."},
	"fw_gold": {"name": "Golden Willow", "price": 85, "pack": 1, "limit": 8, "rocket": true, "color": Color(1, 0.65, 0.16), "desc": "A large golden crown with long, slowly falling ember trails and crackling."},
	"fw_cracker": {"name": "Forest Thunder", "price": 35, "pack": 5, "limit": 20, "rocket": false, "color": Color(1, 0.3, 0.1), "desc": "Five single firecrackers: short throw, crackling fuse, a powerful bang with sparks and smoke."},
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
var hands: ViewmodelHands
var hint: Label
var _clock := 0.0

static func is_battery(id: String) -> bool:
	return DEFS.has(id) and DEFS[id].has("duration")

static func icon_id(id: String) -> String:
	return str(DEFS[id].model) if is_battery(id) else ("firework_rocket" if DEFS[id].rocket else "firework_cracker")

static func make_effect(id: String):
	return Battery.new() if is_battery(id) else Effect.new()

func setup(scene: Node3D) -> void:
	Effect.prewarm_audio()
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
	if not DEFS.has(id): return "Unknown firework."
	var d: Dictionary = DEFS[id]
	if not p.alive: return "You are down."
	if int(stock(p.peer_id)[id]) + int(d.pack) > int(d.limit) or count(p.peer_id) + int(d.pack) > CAPACITY:
		return "Firework bag too full for this pack."
	if p.score < int(d.price): return Lang.t("Not enough Rem Dollars: %d R needed.", [d.price])
	return ""

func buy(p: Player, id: String) -> String:
	if NetSession.is_client(): return "The host confirms the purchase."
	var error := buy_error(p, id)
	if not error.is_empty(): return error
	var d: Dictionary = DEFS[id]
	p.add_score(-int(d.price))
	stock(p.peer_id)[id] += int(d.pack)
	Sfx.event(self, p.peer_id, "purchase")
	return Lang.t("%s ×%d bought · select it in the inventory [I].", [d.name, d.pack])

func select(id: String) -> void:
	if not DEFS.has(id) or int(stock(game.player.peer_id)[id]) <= 0: return
	if not game.player.alive or game.over: return
	if game.inventory.is_open: game.inventory.close()
	selected = id
	armed = true
	input_grace = 0.3
	game.weapons._reset_scope()
	game.weapons.cur().node.hide()
	game.weapons.viewmodel.show()
	if is_instance_valid(held): held.queue_free()
	held = Node3D.new()
	game.weapons.viewmodel.camera.add_child(held)
	var prop: Node3D = Battery.model(id, true) if is_battery(id) else Effect.model(bool(DEFS[id].rocket))
	held.add_child(prop)
	prop.position.y = -0.13 if DEFS[id].rocket else -0.07
	hands = ViewmodelHands.build("knife", ViewmodelHands.weapon_bounds(prop))
	held.add_child(hands)
	hands.support.hide()
	for mesh in held.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 2
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	held.position = Vector3(0.27, -0.30, -0.62)
	held.rotation = Vector3(-0.12, 0.3, -0.12)

func cancel() -> void:
	if not armed: return
	armed = false
	if is_instance_valid(held): held.queue_free()
	hint.hide()
	game.weapons.cur().node.show()
	game.weapons.viewmodel.visible = game.player.active and game.player.alive
	game.weapons.update_hud()
	input_grace = 0.2

func _unhandled_input(event: InputEvent) -> void:
	if not armed or not game.player.active: return
	if event.is_action_pressed("aim") or event.is_action_pressed("weapon_next") or event.is_action_pressed("weapon_prev"):
		cancel()
		get_viewport().set_input_as_handled()

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
	for state in game.weapons.state.values(): state.node.hide()
	game.weapons.viewmodel.visible = playing
	if is_instance_valid(held):
		held.visible = playing
		held.position.y = -0.30 + sin(_clock * 2.4) * 0.005 - sin(input_grace * PI / 0.65) * 0.055
		hands.animate_cloth(delta, game.player.velocity.length(), 0.0)
		hands.anchor_melee_elbows(game.weapons.viewmodel.camera)
	hint.visible = playing
	hint.text = Lang.t("Left click: %s\nRight click: back to your weapon", [Lang.t("Set up & light battery · %d s", [DEFS[selected].duration]) if is_battery(selected) else "Set up & light rocket" if DEFS[selected].rocket else "Light & throw firecracker"])
	game.hud.ammo_label.text = Lang.t("%d pcs", [stock(game.player.peer_id)[selected]])
	game.hud.weapon_label.text = Lang.t("%s · Fireworks", [DEFS[selected].name])
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
	if NetSession.is_client(): return "The host confirms the ignition."
	if not DEFS.has(id) or not p.alive or not p.active or game.over: return "Fireworks are not possible right now."
	if int(stock(p.peer_id)[id]) <= 0: return "No fireworks of this kind left."
	if float(cooldowns.get(p.peer_id, 0)) > 0: return "Wait a moment before the next firework."
	var alive_effects := 0
	for effect in active.values():
		if is_instance_valid(effect): alive_effects += 1
	if alive_effects >= MAX_ACTIVE: return "Wait until the fireworks have died down."
	if is_battery(id):
		var batteries := 0
		for effect in active.values():
			if is_instance_valid(effect) and is_battery(effect.kind): batteries += 1
		if batteries >= 2: return "At most two firework batteries can burn at the same time."
	var forward := -p.global_basis.z
	var eye := p.camera.global_position
	var origin := eye + forward * 0.5
	var landing := origin
	var path := PackedVector3Array([origin])
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [p.get_rid()]
	if DEFS[id].rocket:
		var target := p.global_position + forward * 1.8
		var sight := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target + Vector3.UP * 0.7, 1 | 8, exclude))
		if not sight.is_empty(): return "There is no room in front of you to set it up."
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(target + Vector3.UP * 1.8, target - Vector3.UP * 2.5, 1 | 8, exclude))
		if ground.is_empty() or ground.normal.y < 0.8: return "Set the firework up on level ground."
		origin = ground.position + Vector3.UP * 0.03
		var ceiling := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.8, origin + Vector3.UP * 40, 1 | 8, exclude))
		if not ceiling.is_empty(): return "The firework needs open sky above it."
		if is_battery(id):
			var width := float(DEFS[id].width)
			var query := PhysicsShapeQueryParameters3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(width + 0.15, 0.4, width + 0.15)
			query.shape = box
			query.transform.origin = origin + Vector3.UP * 0.45
			query.collision_mask = 1 | 8
			query.exclude = exclude
			if not space.intersect_shape(query, 1).is_empty(): return "There is not enough room here for the battery."
			for offset in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
				var edge: Vector3 = origin + offset * width * 0.5
				var support := space.intersect_ray(PhysicsRayQueryParameters3D.create(edge + Vector3.UP, edge - Vector3.UP, 1 | 8, exclude))
				if support.is_empty() or absf(support.position.y - origin.y) > 0.18: return "The whole battery must stand on level ground."
				var sky := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.8, origin + Vector3.UP * 45 + offset * 9, 1 | 8, exclude))
				if not sky.is_empty(): return "The fan salvos need open sky."
			for effect in active.values():
				if is_instance_valid(effect) and effect.origin.distance_to(origin) < width + 0.8: return "Keep more distance from fireworks already lit."
		landing = origin
	else:
		# Trace the complete short arc so a thrown cracker cannot cross a wall.
		origin = eye
		path = PackedVector3Array([origin])
		var velocity := -p.head.global_basis.z * 7.0 + Vector3.UP * 2.0
		var previous := origin
		for step in range(1, 41):
			var t := step * 0.05
			var at := origin + velocity * t + Vector3.DOWN * 4.9 * t * t
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(previous, at, 1 | 8, exclude))
			if not hit.is_empty():
				landing = hit.position + hit.normal * 0.025
				path.append(landing)
				break
			landing = at
			path.append(at)
			previous = at
	stock(p.peer_id)[id] -= 1
	cooldowns[p.peer_id] = 0.9
	var effect = make_effect(id)
	effect.configure(id, origin, landing, randi() & 0x7fffffff, 0.0, path)
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
			var effect = make_effect(str(s[0]))
			effect.configure(s[0], s[1], s[2], s[3], s[4], s[5])
			add_child(effect)
			active[id] = effect
		elif absf(active[id].age - float(s[4])) > 0.35:
			active[id].age = maxf(active[id].age, float(s[4]))

# Callouts (26 Sep 2026): the radio the team shares. X (or the middle mouse button) pings whatever the
# crosshair rests on - a gate ("Hold the Meadow Gate!", "... is breaking!"), the hut, an enemy, a spot on
# the ground ("Move here!") or nothing ("Regroup on me!") - and the game itself calls out what matters:
# a gate under heavy attack, a breach, a teammate down, a screamer's mark, a titan. Every callout is a
# line in the radio log (top left), a marker in the world and on the minimap for LIFETIME seconds and a
# radio click. In co-op a client's ping travels as a command to the host, which validates it and hands
# it to everyone as feedback "ping" (author, kind, position, subject); the text is built on each machine
# in its own language.
class_name Pings
extends Node

const LIFETIME := 9.0
const RANGE := 90.0
const CALLOUT_COOLDOWN := 12.0
const TEXTS := {
	"gate_attack": "%s is under attack!",
	"gate_breaking": "%s is breaking!",
	"gate_breached": "%s breached! Fall back to the sandbags!",
	"gate_hold": "Hold %s!",
	"sandbags": "Hold the sandbag line behind %s!",
	"hut": "Defend the forest hut!",
	"enemy": "Enemy spotted here!",
	"move": "Move here!",
	"regroup": "Regroup on me!",
	"down": "%s is down!",
	"spotted": "%s was spotted by a screamer!",
	"titan": "Titan incoming!",
	"blood_moon": "Blood moon! They are faster - kills count double.",
}
const COLOURS := {
	"gate_attack": Color(1.0, 0.35, 0.25), "gate_breaking": Color(1.0, 0.2, 0.15), "gate_breached": Color(1.0, 0.1, 0.1),
	"gate_hold": Color(1.0, 0.75, 0.3), "sandbags": Color(0.9, 0.78, 0.45), "hut": Color(1.0, 0.45, 0.2), "enemy": Color(1.0, 0.3, 0.3),
	"move": Color(0.4, 0.9, 1.0), "regroup": Color(0.4, 0.9, 1.0), "down": Color(1.0, 0.5, 0.2), "spotted": Color(1.0, 0.3, 0.6),
	"titan": Color(1.0, 0.55, 0.15), "blood_moon": Color(1.0, 0.2, 0.2),
}

var main: Node
var active: Array = []         # [{kind, position, text, author, time, colour}]
var log: Array = []            # the last lines shown top left [text, time]
var count := 0
var _cooldowns: Dictionary = {}
var _tap_t := 0.0

func setup(game: Node) -> void:
	main = game
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _unhandled_input(event: InputEvent) -> void:
	if not main or not main.started or main.over or not main.player or not main.player.active: return
	if event.is_action_pressed("ping") and not event.is_echo():
		if _tap_t > 0.0: return
		_tap_t = 0.6
		contextual()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _tap_t > 0.0: _tap_t -= delta
	for key in _cooldowns.keys():
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0: _cooldowns.erase(key)
	var keep: Array = []
	for entry in active:
		entry.time -= delta
		if entry.time > 0.0: keep.append(entry)
	active = keep
	var lines: Array = []
	for line in log:
		line[1] -= delta
		if line[1] > 0.0: lines.append(line)
	log = lines

# ---------------------------------------------------------------- the player's own ping
# What the crosshair rests on decides the callout.
func contextual() -> void:
	var player: Player = main.player
	var camera: Camera3D = player.camera
	var from := camera.global_position
	var to := from - camera.global_basis.z * RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 8 | Zombie.HITBOX_LAYER, [player.get_rid()])
	query.collide_with_areas = true
	var hit := Zombie.cast_ray(main, query)
	var kind := "regroup"
	var subject := ""
	var position := player.global_position
	if not hit.is_empty():
		var collider: Object = hit.collider
		var zombie := Zombie.from_hit(hit)
		var line: Barricade = _line_of(collider)
		if zombie and zombie.alive:
			kind = "enemy"
			position = zombie.global_position
		elif line:
			subject = str(line.slot["name"])
			position = line.center
			if not line.is_gate(): kind = "sandbags"
			elif line.level > 0 and line.under_attack() and line.hp < line.max_hp() * 0.5: kind = "gate_breaking"
			elif line.level > 0 and line.under_attack(): kind = "gate_attack"
			else: kind = "gate_hold"
		elif collider is Node and (collider as Node).is_in_group("hut_body"):
			kind = "hut"
			position = main.hut.center if main.hut else hit.position
		elif from.distance_to(hit.position) < RANGE:
			kind = "move"
			position = hit.position
	if kind in ["move", "regroup"]:
		# an open site has no collision: a gate or sandbag site close to the line of sight still counts
		var site: Barricade = _site_along(from, to if hit.is_empty() else hit.position)
		if site:
			subject = str(site.slot["name"])
			position = site.center
			kind = "gate_hold" if site.is_gate() else "sandbags"
	send(kind, position, subject)

func _site_along(from: Vector3, to: Vector3) -> Barricade:
	var lines: Array = main.defence_lines() if main.has_method("defence_lines") else main.barricades
	var best: Barricade = null
	var best_distance := 3.0
	for line in lines:
		if line.level > 0: continue
		var centre: Vector3 = line.center + Vector3.UP * 0.8
		var closest := Geometry3D.get_closest_point_to_segment(centre, from, to)
		var d := closest.distance_to(centre)
		if d < best_distance and closest.distance_to(from) < RANGE:
			best_distance = d
			best = line
	return best

func _line_of(collider: Object) -> Barricade:
	if not collider is Node: return null
	var node := collider as Node
	while node:
		if node is Barricade: return node
		node = node.get_parent()
	return null

# a ping from this machine's player: straight to everyone (solo / host) or as a command to the host
func send(kind: String, position: Vector3, subject := "") -> void:
	if not TEXTS.has(kind): return
	if NetSession.is_client():
		NetSession.command("ping", [kind, position, subject])
		return
	broadcast(NetSession.local_id(), kind, position, subject)

# host / solo: hand a validated ping to every peer (and to this machine)
func broadcast(author_id: int, kind: String, position: Vector3, subject := "") -> void:
	if not TEXTS.has(kind) or not position.is_finite(): return
	var author: String = NetSession.roster.get(author_id, NetSession.player_name) if NetSession.enabled else NetSession.player_name
	if NetSession.is_host():
		for peer in NetSession.ready_peers:
			if peer != 1 and NetSession.ready_peers[peer]: NetSession.feedback(peer, "ping", [author, kind, position, subject])
	receive(author, kind, position, subject)

# the automatic callouts of the game itself (host / solo), throttled per key
func callout(key: String, kind: String, position: Vector3, subject := "") -> void:
	if NetSession.is_client(): return
	if _cooldowns.has(key): return
	_cooldowns[key] = CALLOUT_COOLDOWN
	broadcast(0, kind, position, subject)

# every machine: text in its own language, marker, log line, radio click
func receive(author: String, kind: String, position: Vector3, subject := "") -> void:
	if not TEXTS.has(kind): return
	# a player's name stays as it is, a gate's name is a msgid and gets translated on this machine
	var argument: Variant = Lang.raw(subject) if kind in ["down", "spotted"] else subject
	var body: String = Lang.t(TEXTS[kind], [argument]) if TEXTS[kind].contains("%s") else Lang.t(TEXTS[kind])
	var text: String = Lang.t("%s: %s", [Lang.raw(author), body]) if not author.is_empty() else body
	count += 1
	active.append({"kind": kind, "position": position, "text": body, "author": author, "time": LIFETIME, "colour": COLOURS.get(kind, Color.WHITE)})
	if active.size() > 6: active.pop_front()
	log.append([text, LIFETIME + 3.0])
	if log.size() > 4: log.pop_front()
	Sfx.play(self, "radio", -14.0, randf_range(0.95, 1.05))
	if main and main.hud and main.hud.has_method("radio_line"): main.hud.radio_line(text, COLOURS.get(kind, Color.WHITE))

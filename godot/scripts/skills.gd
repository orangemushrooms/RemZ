class_name Skills
extends CanvasLayer

var player: Player
var weapons: Weapons
var hud: Hud
var main: Node
var levels := {}
var is_open := false

const UPGRADES := [
	{ "id": "hp", "name": "Zähigkeit", "desc": "+25 maximale Lebenspunkte", "cost": 100, "max": 4 },
	{ "id": "speed", "name": "Beine", "desc": "+8 % Laufgeschwindigkeit", "cost": 80, "max": 4 },
	{ "id": "regen", "name": "Erholung", "desc": "Schnellere Regeneration", "cost": 80, "max": 3 },
	{ "id": "damage", "name": "Schusskraft", "desc": "+12 % Schaden", "cost": 120, "max": 5 },
	{ "id": "reload", "name": "Schnelle Hände", "desc": "-15 % Nachladezeit", "cost": 80, "max": 3 },
	{ "id": "steady", "name": "Ruhige Hand", "desc": "-15 % Streuung und ruhigere Feuerstöße", "cost": 180, "max": 3 },
	{ "id": "grenades", "name": "Granatentasche", "desc": "+1 Platz in der Granatentasche", "cost": 70, "max": 4 },
]

func setup(p: Player, w: Weapons, h: Hud, m: Node) -> void:
	player = p
	weapons = w
	hud = h
	main = m
	for spec in UPGRADES: levels[spec.id] = 0

func purchase(p: Player, w: Weapons, id: String) -> String:
	if NetSession.is_client() or not main.progression.close_enough(p, "mechanic"): return "Training nur bei Mechanic."
	var progress: Dictionary = NetSession.world.levels[p.peer_id] if NetSession.is_host() else levels
	var spec: Dictionary = {}
	for entry in UPGRADES:
		if entry.id == id: spec = entry
	if spec.is_empty(): return "Dieses Training gibt es nicht."
	var level: int = progress.get(id, 0)
	var cost := int(spec.cost) + int(spec.cost) * level / 2
	if level >= int(spec.max): return "Training bereits vollständig."
	if p.score < cost: return "Zu wenig Punkte."
	p.add_score(-cost)
	progress[id] = level + 1
	match id:
		"hp":
			p.max_hp += 25.0
			p.hp = minf(p.max_hp, p.hp + 25.0)
			if p == player: hud.hp_bar.max_value = p.max_hp
			p.hud.set_health(p.hp)
		"speed": p.speed_mul += 0.08
		"regen": p.regen_mul += 0.6
		"damage": w.damage_mul += 0.12
		"reload": w.reload_mul *= 0.85
		"steady": w.spread_mul *= 0.85
		"grenades":
			w.grenades_max += 1
			w.grenades += 1
	w.update_hud()
	Sfx.event(self, p.peer_id, "purchase")
	return "Training gekauft: " + str(spec.name)

func _buy(id: String) -> void:
	if NetSession.enabled: NetSession.command("shop", ["mechanic", "training", id, ""])
	else: hud.message(purchase(player, weapons, id), 2)

func open() -> void:
	if main.progression.close_enough(player, "mechanic"): main.progression.interact("mechanic")
	else: hud.message("Training gibt es bei Mechanic nördlich des Lagerfeuers.", 3)

func close() -> void:
	if main.progression: main.progression.close()

func _refresh() -> void:
	pass

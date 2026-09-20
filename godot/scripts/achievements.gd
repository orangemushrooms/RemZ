# Achievements: tiered goals with rewards, blinking gold toasts, persistent across runs (user://achievements.json).
# Other systems report events via Achievements.event(name, amount).
class_name Achievements
extends CanvasLayer

const SAVE := "user://achievements.json"
# id: title, text, counter, target, reward {score, grenades, ammo, hp}
const DEFS := [
	{ "id": "pumpkin", "title": "Kürbisknacker", "text": "Einen Kürbis zerschossen", "counter": "pumpkins", "target": 1, "reward": { "score": 25 } },
	{ "id": "first_blood", "title": "Erstes Blut", "text": "Ersten Zombie erledigt", "counter": "kills", "target": 1, "reward": { "score": 10 } },
	{ "id": "kills_5", "title": "Warmgeschossen", "text": "5 Zombies erledigt", "counter": "kills", "target": 5, "reward": { "score": 20 } },
	{ "id": "kills_25", "title": "Waldpolizei", "text": "25 Zombies erledigt", "counter": "kills", "target": 25, "reward": { "score": 40, "grenades": 1 } },
	{ "id": "kills_100", "title": "Heitersberg-Schlächter", "text": "100 Zombies erledigt", "counter": "kills", "target": 100, "reward": { "score": 100, "hp": 2 } },
	{ "id": "kills_250", "title": "Legende von Remetschwil", "text": "250 Zombies erledigt", "counter": "kills", "target": 250, "reward": { "score": 250, "hp": 4, "grenades": 3 } },
	{ "id": "head_1", "title": "Volltreffer", "text": "Erster Kopfschuss", "counter": "headshots", "target": 1, "reward": { "score": 10 } },
	{ "id": "head_10", "title": "Scharfschütze", "text": "10 Kopfschüsse", "counter": "headshots", "target": 10, "reward": { "score": 40, "grenades": 1 } },
	{ "id": "head_50", "title": "Kopfjäger", "text": "50 Kopfschüsse", "counter": "headshots", "target": 50, "reward": { "score": 120, "ammo": true } },
	{ "id": "wave_1", "title": "Erste Nacht", "text": "Welle 1 überstanden", "counter": "waves", "target": 1, "reward": { "score": 25, "hp": 2 } },
	{ "id": "wave_3", "title": "Durchhalten", "text": "Welle 3 überstanden", "counter": "waves", "target": 3, "reward": { "score": 50, "hp": 2 } },
	{ "id": "wave_5", "title": "Hüttenwart", "text": "Welle 5 überstanden", "counter": "waves", "target": 5, "reward": { "score": 100, "hp": 3, "grenades": 2 } },
	{ "id": "wave_10", "title": "Unsterblich", "text": "Welle 10 überstanden", "counter": "waves", "target": 10, "reward": { "score": 200, "hp": 5, "ammo": true } },
	{ "id": "flawless", "title": "Kein Kratzer", "text": "Eine Welle ohne Schaden überstanden", "counter": "flawless", "target": 1, "reward": { "score": 30, "grenades": 1 } },
	{ "id": "bar_1", "title": "Zimmermann", "text": "Erste Barrikade gebaut", "counter": "barricades", "target": 1, "reward": { "score": 15 } },
	{ "id": "bar_6", "title": "Festung Waldhütte", "text": "6 Barrikadenstufen gebaut", "counter": "barricades", "target": 6, "reward": { "score": 50, "hp": 2 } },
	{ "id": "loot_1", "title": "Fundstück", "text": "Erste Waffe gekauft", "counter": "weapons", "target": 1, "reward": {} },
	{ "id": "loot_4", "title": "Arsenal", "text": "Vier Waffen gekauft", "counter": "weapons", "target": 4, "reward": {} },
	{ "id": "door", "title": "Aufgemacht", "text": "Garagentor der Waldhütte geöffnet", "counter": "door", "target": 1, "reward": { "score": 10 } },
	{ "id": "window", "title": "Einbrecher", "text": "Hinterfenster des Holzlagers zerschossen", "counter": "window", "target": 1, "reward": { "score": 15 } },
	{ "id": "shroom_1", "title": "Pilzsammler", "text": "Ersten Pilz gesammelt", "counter": "mushrooms", "target": 1, "reward": { "score": 5 } },
	{ "id": "shroom_10", "title": "Pilzkenner", "text": "10 Pilze gesammelt", "counter": "mushrooms", "target": 10, "reward": { "score": 25, "hp": 2 } },
	{ "id": "rausch", "title": "Rausch", "text": "Fliegenpilz gegessen", "counter": "rausch", "target": 1, "reward": { "score": 10 } },
	{ "id": "oak", "title": "Die Eiche", "text": "Die grosse Eiche am Weg zur Hütte besucht", "counter": "oak", "target": 1, "reward": { "score": 10 } },
	{ "id": "road", "title": "Bis zur Sennhofstrasse", "text": "Die Sennhofstrasse erreicht", "counter": "road", "target": 1, "reward": { "score": 10, "grenades": 1 } },
	{ "id": "north", "title": "Oberer Sorchen", "text": "Den Waldweg nach Norden bis zum Ende gegangen", "counter": "north", "target": 1, "reward": { "score": 20 } },
	{ "id": "grenade_3", "title": "Sprengmeister", "text": "3 Zombies mit einer Granate", "counter": "grenade_multi", "target": 1, "reward": { "score": 40, "grenades": 2 } },
	{ "id": "streak_10", "title": "Im Rausch", "text": "10 Abschüsse in Serie", "counter": "streak_10", "target": 1, "reward": { "score": 40, "grenades": 1 } },
	{ "id": "drops_10", "title": "Aufgelesen", "text": "10 Vorräte von Zombies aufgesammelt", "counter": "drops", "target": 10, "reward": { "score": 30, "ammo": true } },
]

var player: Player
var weapons: Weapons
var hud: Hud
var main: Node
var counters := {}
var unlocked := {}          # id -> true (persisted)
var session_unlocked := {}  # id -> true (this run, rewards given)
var _queue: Array = []
var _toast: PanelContainer
var _title: Label
var _text: Label
var _reward: Label
var _badge: Label
var _showing := false
var _wave_damage := false
var persist := true

func setup(p: Player, w: Weapons, h: Hud, m: Node) -> void:
	player = p
	weapons = w
	hud = h
	main = m
	persist = not ("--smoke-test" in OS.get_cmdline_user_args() or "--autotest" in OS.get_cmdline_user_args())
	_load()

func _ready() -> void:
	layer = 9   # below the HUD menu overlay so the pause / game-over screen covers the toast
	_toast = PanelContainer.new()
	_toast.visible = false
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.custom_minimum_size = Vector2(460, 96)
	_toast.position = Vector2(-230, 110)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.05, 0.03, 0.92)
	st.border_color = Color(1.0, 0.8, 0.3)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(12)
	st.shadow_color = Color(1.0, 0.75, 0.2, 0.35)
	st.shadow_size = 14
	_toast.add_theme_stylebox_override("panel", st)
	add_child(_toast)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	_toast.add_child(h)
	_badge = Label.new()
	_badge.text = "★"
	_badge.add_theme_font_size_override("font_size", 44)
	_badge.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	h.add_child(_badge)
	var v := VBoxContainer.new()
	h.add_child(v)
	var head := Label.new()
	head.text = "ERFOLG FREIGESCHALTET"
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	v.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(1, 1, 1))
	v.add_child(_title)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 13)
	_text.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75))
	v.add_child(_text)
	_reward = Label.new()
	_reward.add_theme_font_size_override("font_size", 13)
	_reward.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	v.add_child(_reward)

func _load() -> void:
	if FileAccess.file_exists(SAVE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if d is Dictionary:
			for k in d.get("unlocked", []):
				unlocked[k] = true

func _save() -> void:
	if not persist: return
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({ "unlocked": unlocked.keys() }))

# report progress: event("kills"), event("waves", 3), ...
func event(name: String, amount: int = 1, absolute: bool = false) -> void:
	if NetSession.is_client(): return
	counters[name] = amount if absolute else counters.get(name, 0) + amount
	for d in DEFS:
		if d["counter"] == name and counters[name] >= d["target"] and not session_unlocked.has(d["id"]):
			_unlock(d)

func progress_text() -> String:
	return "%d / %d Erfolge" % [unlocked.size(), DEFS.size()]

func _unlock(d: Dictionary) -> void:
	session_unlocked[d["id"]] = true
	var fresh: bool = not unlocked.has(d["id"])
	unlocked[d["id"]] = true
	_save()
	var r: Dictionary = d["reward"]
	var parts: Array = []
	if r.has("score"):
		player.add_score(int(r["score"]))
		parts.append("+%d Punkte" % int(r["score"]))
	if r.has("grenades"):
		weapons.grenades = mini(weapons.grenades_max, weapons.grenades + int(r["grenades"]))
		parts.append("+%d Granaten" % int(r["grenades"]))
	if r.has("hp"):
		player.max_hp += float(r["hp"])
		player.hp = minf(player.hp + float(r["hp"]), player.max_hp)
		parts.append("+%d max. Leben" % int(r["hp"]))
	if r.has("ammo"):
		weapons.refill_all()
		parts.append("Pistolenreserve gesichert")
	weapons.update_hud()
	if NetSession.is_host():
		for id in NetSession.world.actors:
			if id == 1: continue
			var p: Player = NetSession.world.actor(id)
			var w: Weapons = NetSession.world.weapons[id]
			p.add_score(int(r.get("score", 0)))
			w.grenades = mini(w.grenades_max, w.grenades + int(r.get("grenades", 0)))
			p.max_hp += float(r.get("hp", 0))
			p.hp = minf(p.hp + float(r.get("hp", 0)), p.max_hp)
			if r.has("ammo"): w.refill_all()
			NetSession.feedback(id, "message", ["Teamerfolg: " + str(d.title), 3.5])
	_queue.append([d, ", ".join(parts), fresh])
	if not _showing:
		_next()

func _next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var item: Array = _queue.pop_front()
	var d: Dictionary = item[0]
	_title.text = d["title"]
	_text.text = d["text"]
	_reward.text = item[1] + ("" if item[2] else "  (schon einmal erreicht)")
	_toast.visible = true
	_toast.modulate = Color(1, 1, 1, 0)
	_toast.position.y = 80
	Sfx.play(self, "confirm", 0.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_toast, "modulate:a", 1.0, 0.25)
	tw.tween_property(_toast, "position:y", 110.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# blinking star and border glow
	var blink := create_tween()
	blink.set_loops(6)
	blink.tween_property(_badge, "modulate", Color(2.0, 1.8, 1.0), 0.18)
	blink.tween_property(_badge, "modulate", Color(1, 1, 1), 0.18)
	var hold := create_tween()
	hold.tween_interval(3.4)
	hold.tween_property(_toast, "modulate:a", 0.0, 0.4)
	hold.tween_callback(func(): _toast.visible = false; _next())

func _process(_delta: float) -> void:
	if NetSession.is_host() and NetSession.world:
		for teammate: Player in NetSession.world.actors.values():
			if teammate.alive: _explore(teammate.global_position)
		return
	if not player or not player.active or NetSession.is_client():
		return
	_explore(player.global_position)

func _explore(p: Vector3) -> void:
	if not counters.has("oak") and Vector2(p.x, p.z).distance_to(Map.LANDMARK_OAK) < 9.0:
		event("oak")
	if not counters.has("road") and p.x > 100.0:
		event("road")
	if not counters.has("north") and p.z < -110.0:
		event("north")

# wave bookkeeping (called by waves.gd)
func wave_started() -> void:
	_wave_damage = false

func player_hurt() -> void:
	_wave_damage = true

func wave_cleared(n: int) -> void:
	event("waves", n, true)
	if not _wave_damage:
		event("flawless")

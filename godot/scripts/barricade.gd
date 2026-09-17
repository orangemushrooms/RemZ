# A barricade slot at one approach to the bay: build up to level 3, repair, gets attacked by zombies.
class_name Barricade
extends Node3D

const COST_BUILD := 50
const COST_REPAIR := 25
const MAX_LEVEL := 3

var slot: Dictionary
var level := 0
var hp := 0.0
var center: Vector3
var half_len: float
var dir2: Vector2
var normal2: Vector2
var body: StaticBody3D
var visual: Node3D
var hud: Hud

func setup(s: Dictionary, h: Hud) -> void:
	slot = s
	hud = h
	var p: Vector2 = s["pos"]
	center = Map.ground_pos(p.x, p.y)
	half_len = s["segments"] * 1.6
	var yaw: float = s["yaw"]
	dir2 = Vector2(cos(yaw), -sin(yaw))
	normal2 = Vector2(sin(yaw), cos(yaw))
	position = center
	rotation.y = yaw

func _ready() -> void:
	body = StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(half_len * 2.0, 1.6, 0.9)
	shape.shape = box
	shape.position.y = 0.8
	body.add_child(shape)
	body.add_to_group("barricade")
	add_child(body)
	visual = Node3D.new()
	add_child(visual)
	rebuild()

func max_hp() -> float:
	return level * 150.0

func rebuild() -> void:
	for c in visual.get_children():
		c.queue_free()
	body.process_mode = Node.PROCESS_MODE_INHERIT if level > 0 else Node.PROCESS_MODE_DISABLED
	body.get_child(0).disabled = level == 0
	var scene = load("res://assets/models/barricade.glb")
	for i in int(slot["segments"]):
		for l in level:
			var m: Node3D = scene.instantiate() if scene else null
			if not m:
				continue
			var holder := Node3D.new()
			holder.position = Vector3((i - (slot["segments"] - 1) / 2.0) * 3.2, 0.0, l * 0.35 - 0.35)
			holder.rotation.y = 0.06 if l % 2 == 1 else -0.06
			holder.add_child(m)
			Weapons._fit_height(m, 1.4 * (0.85 + l * 0.15))
			m.position.y += 0.7 * (0.85 + l * 0.15)
			visual.add_child(holder)
	var f := hp / max_hp() if max_hp() > 0.0 else 0.0
	visual.rotation.z = (1.0 - f) * 0.12

func build() -> bool:
	if level >= MAX_LEVEL:
		return false
	level += 1
	hp = max_hp()
	rebuild()
	return true

func repair() -> bool:
	if level == 0 or hp >= max_hp():
		return false
	hp = max_hp()
	rebuild()
	return true

func damage(n: float) -> void:
	if hp <= 0.0:
		return
	hp -= n
	Sfx.play_at(get_parent(), "wood", center, -4.0)
	if hp <= 0.0:
		hp = 0.0
		level = 0
		hud.message("Barrikade %s durchbrochen!" % slot["name"], 2.0)
	rebuild()

func _local(p: Vector3) -> Vector2:
	var dx := p.x - center.x
	var dz := p.z - center.z
	return Vector2(dx * dir2.x + dz * dir2.y, dx * normal2.x + dz * normal2.y)

func crosses(a: Vector3, b: Vector3) -> bool:
	var la := _local(a)
	var lb := _local(b)
	if signf(la.y) == signf(lb.y):
		return false
	var t := la.y / (la.y - lb.y)
	var u := la.x + (lb.x - la.x) * t
	return absf(u) < half_len + 0.6

func prompt_text() -> String:
	if level == 0:
		return "[E] Barrikade bauen (%d Punkte)" % COST_BUILD
	if hp < max_hp():
		return "[E] Reparieren (%d) · %d/%d" % [COST_REPAIR, roundi(hp), int(max_hp())]
	if level < MAX_LEVEL:
		return "[E] Verstärken auf Stufe %d (%d)" % [level + 1, COST_BUILD]
	return "Barrikade Stufe %d · %d/%d" % [level, roundi(hp), int(max_hp())]

func interact(player: Player) -> void:
	if level == 0 or (level < MAX_LEVEL and hp >= max_hp()):
		if player.score < COST_BUILD:
			hud.message("Zu wenig Punkte (%d)" % COST_BUILD, 1.2)
			return
		if build():
			player.add_score(-COST_BUILD)
			Sfx.play(self, "build", -6.0)
	elif hp < max_hp():
		if player.score < COST_REPAIR:
			hud.message("Zu wenig Punkte (%d)" % COST_REPAIR, 1.2)
			return
		if repair():
			player.add_score(-COST_REPAIR)
			Sfx.play(self, "build", -6.0)

# Structural health of the Waldhütte. Zombies that get inside the ring (or close to the walls) hit the hut,
# the HUD warns, the player repairs it with E at a wall. At zero health the round is lost, no matter who is alive.
class_name HutHealth
extends Node3D

const MAX_HP := 5000.0
const REPAIR_STEP := 500.0          # health per repair action
const REPAIR_COST := 30             # points per repair action
const REPAIR_REACH := 5.0           # metres from the walls
const ATTACK_ALERT_SECONDS := 5.0
const RAID_RANGE := 9.0             # zombies closer than this to a wall turn on the hut
const WARNING := "ACHTUNG: DIE WALDHÜTTE WIRD ANGEGRIFFEN!\nVerteidigen!"

var game: Node
var hp := MAX_HP:
	set(value):
		hp = clampf(value, 0.0, MAX_HP)
		if health_display: _update_health_display()
var health_display: Node3D
var health_fill: Sprite3D
var health_label: Label3D
var attack_alert_remaining := 0.0
var _attack_sound: AudioStreamPlayer
var destroyed := false
var body: StaticBody3D              # one wall body; Zombie._can_hit accepts every body in the "hut_body" group
var center := Vector3.ZERO
var half := Vector2.ZERO
var _dir := Vector2.RIGHT           # local +x of the hut in the world xz plane
var _nrm := Vector2.DOWN            # local +z of the hut in the world xz plane

func setup(main: Node, root: Node3D, size: Vector2) -> void:
	game = main
	center = root.global_position
	half = size / 2.0
	var yaw: float = root.rotation.y
	_dir = Vector2(cos(yaw), -sin(yaw))
	_nrm = Vector2(sin(yaw), cos(yaw))
	for b in root.find_children("*", "StaticBody3D", true, false):
		b.add_to_group("hut_body")
		if body == null: body = b
	add_to_group("hut_health")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_create_health_display(root)
	_update_health_display()

func _create_health_display(root: Node3D) -> void:
	health_display = Node3D.new()
	health_display.name = "HealthDisplay"
	add_child(health_display)
	# Measure before map batching removes the individual building meshes.
	var bounds := Barricade._bounds(root, root.transform.affine_inverse())
	health_display.global_position = root.to_global(Vector3(0, bounds.end.y + 0.8, 0))
	var image := Image.create(256, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for background in [true, false]:
		var sprite := Sprite3D.new()
		sprite.texture = texture
		sprite.pixel_size = 0.016
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.no_depth_test = true
		sprite.render_priority = 10 if background else 11
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		health_display.add_child(sprite)
		if background:
			sprite.modulate = Color(0.025, 0.035, 0.04, 0.9)
			sprite.scale = Vector3(1.04, 1.6, 1)
		else:
			health_fill = sprite
			health_fill.region_enabled = true
	health_label = Label3D.new()
	health_label.position.y = 0.55
	health_label.font_size = 32
	health_label.outline_size = 8
	health_label.pixel_size = 0.012
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_label.no_depth_test = true
	health_label.render_priority = 12
	health_display.add_child(health_label)

func _update_health_display() -> void:
	var ratio := hp / MAX_HP
	var width := 256.0 * ratio
	health_fill.visible = hp > 0.0
	health_fill.region_rect = Rect2(0, 0, width, 18)
	health_fill.offset.x = (width - 256.0) * 0.5
	health_fill.modulate = Color(0.3, 0.9, 0.5) if ratio > 0.5 else (Color(1.0, 0.72, 0.2) if ratio > 0.25 else Color(1.0, 0.25, 0.2))
	health_label.text = "WALDHÜTTE  %d / %d" % [ceili(hp), int(MAX_HP)]

func max_hp() -> float:
	return MAX_HP

# the HUD is created after the buildings, so resolve it late
func _hud() -> Hud:
	return game.hud if game and "hud" in game else null

func _local(p: Vector3) -> Vector2:
	var d := Vector2(p.x - center.x, p.z - center.z)
	return Vector2(d.dot(_dir), d.dot(_nrm))

func _world(l: Vector2) -> Vector3:
	var w := Vector2(center.x, center.z) + _dir * l.x + _nrm * l.y
	return Map.ground_pos(w.x, w.y)

# nearest point just outside the footprint, on the ground: where a zombie stands to hit the wall
func attack_point(from: Vector3) -> Vector3:
	var l := _local(from)
	var c := Vector2(clampf(l.x, -half.x, half.x), clampf(l.y, -half.y, half.y))
	var outward: Vector2
	if c.is_equal_approx(l):
		# inside the footprint: push to the nearest wall
		var gaps := [half.x - l.x, half.x + l.x, half.y - l.y, half.y + l.y]
		var k := 0
		for i in 4:
			if gaps[i] < gaps[k]: k = i
		match k:
			0: c.x = half.x; outward = Vector2.RIGHT
			1: c.x = -half.x; outward = Vector2.LEFT
			2: c.y = half.y; outward = Vector2.DOWN
			_: c.y = -half.y; outward = Vector2.UP
	else:
		outward = (l - c).normalized()
	return _world(c + outward * 0.8)

func distance(from: Vector3) -> float:
	var a := attack_point(from)
	return Vector2(from.x - a.x, from.z - a.z).length()

func under_attack() -> bool:
	return hp > 0.0 and attack_alert_remaining > 0.0

func update_attack_alert(seconds: float, notify := true) -> void:
	var was := under_attack()
	attack_alert_remaining = maxf(0.0, seconds) if hp > 0.0 else 0.0
	var hud := _hud()
	if hud: hud.set_hut(hp, MAX_HP, under_attack())
	if not under_attack() and is_instance_valid(_attack_sound): _attack_sound.stop()
	if notify and under_attack() and not was and hud:
		hud.message(WARNING, 3.5)
		if not is_instance_valid(_attack_sound):
			_attack_sound = AudioStreamPlayer.new()
			_attack_sound.name = "HutAttackWarning"
			_attack_sound.stream = Sfx.get_stream("hut_under_attack")
			_attack_sound.volume_db = -6.0
			add_child(_attack_sound)
		# One local warning per attack phase, paired with the visible alarm on host and clients.
		if not _attack_sound.playing: _attack_sound.play()

func damage(n: float) -> void:
	if destroyed or n <= 0.0 or NetSession.is_client(): return
	hp = maxf(0.0, hp - n)
	update_attack_alert(ATTACK_ALERT_SECONDS)
	Sfx.play_at(get_parent(), "wood_hit", center, -3.0)
	if hp <= 0.0:
		destroyed = true
		attack_alert_remaining = 0.0
		Sfx.play_at(get_parent(), "hut_collapse", center, 3.0)
		if game.has_method("_hut_lost"): game._hut_lost()

func can_repair(player: Player) -> bool:
	return not destroyed and hp < MAX_HP and player.alive and distance(player.global_position) <= REPAIR_REACH

# returns an error text, empty on success (same contract as DefenceSystem.maintain)
func repair(player: Player) -> String:
	if destroyed: return "Die Waldhütte ist zerstört."
	if hp >= MAX_HP: return "Keine Reparatur nötig."
	if not player.alive: return "Reparieren ist momentan nicht möglich."
	if distance(player.global_position) > REPAIR_REACH: return "Zu weit von der Hütte entfernt."
	if player.score < REPAIR_COST: return "Es fehlen %d Punkte." % (REPAIR_COST - player.score)
	player.add_score(-REPAIR_COST)
	hp = minf(MAX_HP, hp + REPAIR_STEP)
	Sfx.event(self, player.peer_id, "purchase")
	Sfx.play_at(get_parent(), "build", center, -6.0)
	return ""

func prompt_text() -> String:
	return "[E] Waldhütte reparieren · +%d · %d P\nHütte %d / %d" % [int(REPAIR_STEP), REPAIR_COST, ceili(hp), int(MAX_HP)]

func _process(delta: float) -> void:
	attack_alert_remaining = maxf(0.0, attack_alert_remaining - delta)
	if is_instance_valid(_attack_sound) and (not under_attack() or game.over): _attack_sound.stop()
	var hud := _hud()
	if hud: hud.set_hut(hp, MAX_HP, under_attack())

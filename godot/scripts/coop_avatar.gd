extends Node3D

const COLORS := [Color("66864b"), Color("497e9c"), Color("a9783f"), Color("865c94")]
const SurvivorRig = preload("res://scripts/survivor_rig.gd")
const SurvivorHands = preload("res://scripts/survivor_hands.gd")
var actor: Player
var body: Node3D
var visual: SurvivorRig
var aim: Node3D
var label: Label3D
var gun: Node3D
var hands: Node3D
var flash: OmniLight3D
var weapon := ""
var flash_t := 0.0
var recoil := 0.0
var knife_stab := false
var axe_heavy := false
var tint := Color.WHITE
var step_distance := 0.0
var crouch_blend := 0.0
var right_grip := Vector3.ZERO
var left_grip := Vector3.ZERO
var mods: WeaponAttachments
var _skin := "__unset"
var _loadout := {}

func setup(p: Player, display_name: String, index: int) -> void:
	actor = p
	tint = COLORS[posmod(index, COLORS.size())]
	body = Node3D.new()
	add_child(body)
	visual = SurvivorRig.new()
	body.add_child(visual)
	visual.setup()
	aim = Node3D.new()
	aim.position = Vector3(0.0, 1.40, -0.04)
	body.add_child(aim)
	label = Label3D.new()
	label.text = Lang.t("%s", [Lang.raw(display_name)])
	label.font_size = 32
	label.pixel_size = 0.004
	label.position.y = 2.12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = tint.lightened(0.4)
	label.visibility_range_end = 45.0
	add_child(label)
	flash = OmniLight3D.new()
	flash.light_color = Color(1, 0.65, 0.25)
	flash.omni_range = 3.0
	flash.shadow_enabled = false
	flash.visible = false
	aim.add_child(flash)
	set_weapon("pistol")
	add_to_group("render_dynamic")

func set_weapon(id: String) -> void:
	if id == weapon or not Weapons.DEFS.has(id): return
	Sfx.stop_fire_loop(self)
	weapon = id
	_skin = "__unset"
	if gun:
		gun.get_parent().remove_child(gun)
		gun.queue_free()
	gun = Node3D.new()
	aim.add_child(gun)
	var model: Node3D
	if Weapons.is_melee(id):
		model = Weapons.MeleeModels.build(id)
	else:
		# A missing GLB must not take the teammate's avatar down with it: the view model falls back
		# to a grey box (weapons.gd), so the world avatar does the same instead of crashing.
		var path := "res://assets/models/%s.glb" % Weapons.DEFS[id].model
		if ResourceLoader.exists(path):
			model = (load(path) as PackedScene).instantiate()
		else:
			push_warning("coop avatar: missing weapon model " + path)
			model = Node3D.new()
			var placeholder := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.3, 0.06, 0.04)
			placeholder.mesh = box
			model.add_child(placeholder)
	gun.add_child(model)
	if not Weapons.is_melee(id):
		model.rotation.y = -PI / 2.0
		Weapons._fit_height(model, float(Weapons.DEFS[id].height) * 1.35)
		model.position -= ViewmodelHands.weapon_bounds(gun).get_center()
	var bounds := ViewmodelHands.weapon_bounds(gun)
	var landmarks: Vector4 = ViewmodelHands.GRIPS.get(id, Vector4(0.32, 0.72, 0.48, 0.3))
	right_grip = Vector3(bounds.end.x + 0.024, bounds.position.y + bounds.size.y * landmarks.x - 0.008, bounds.position.z + bounds.size.z * landmarks.y + 0.059)
	left_grip = Vector3(bounds.position.x + 0.001, bounds.position.y + bounds.size.y * landmarks.z - 0.03, bounds.position.z + bounds.size.z * landmarks.w + 0.060)
	if Weapons.is_melee(id):
		right_grip = Vector3(0.02, -0.03, 0.074)
		left_grip = Vector3(-0.22, -0.12, 0.15)
	if id in ViewmodelHands.HANDGUNS:
		left_grip = right_grip + Vector3(-0.065, -0.025, -0.015)
	else:
		# Support near the rear of the fore-end, within a human arm's reach.
		left_grip.z = maxf(left_grip.z, right_grip.z - 0.15)
	# Anchor the trigger wrist; long barrels extend forward, not into the chest.
	gun.position = Vector3(0.12, -0.08, -0.18) - right_grip
	if hands:
		hands.get_parent().remove_child(hands)
		hands.queue_free()
	hands = Node3D.new()
	aim.add_child(hands)
	var right_hand := SurvivorHands.glove(true, false)
	var left_hand := SurvivorHands.glove(false, id not in ViewmodelHands.HANDGUNS)
	hands.add_child(right_hand)
	hands.add_child(left_hand)
	right_hand.position = gun.position + right_grip
	left_hand.position = gun.position + left_grip
	right_hand.rotation.y = PI
	left_hand.rotation = Vector3(0, PI, -0.25 if id in ViewmodelHands.HANDGUNS else PI * 0.5)
	flash.position = gun.position + Vector3(bounds.get_center().x, bounds.end.y - 0.025, bounds.position.z - 0.025)
	# Same rule as the view model: mods go on only once the grips and the flash are anchored to the
	# bare weapon, so a teammate's suppressor cannot shift where their hands sit.
	mods = null
	if not Weapons.is_melee(id) and WeaponAttachments.supported(Weapons.DEFS[id].model):
		mods = WeaponAttachments.new()
		mods.layer = 1
		mods.shadows = true
		mods.setup(Weapons.DEFS[id].model, model, gun)
		gun.add_child(mods)
		mods.refresh(_loadout)

# The host's snapshot already carries every player's loadout, so a teammate's gun shows the same
# mods in the world that its owner sees in their own hands.
func set_mods(loadout: Dictionary) -> void:
	if _loadout == loadout: return
	_loadout = loadout.duplicate(true)
	if mods: mods.refresh(_loadout)

func shot(id: String, mod_effects: Array = []) -> void:
	var field = get_tree().current_scene.get("cornfield")
	if field: field.scare(global_position)
	set_weapon(id)
	if Weapons.is_melee(id):
		axe_heavy = id == "hatchet" and mod_effects.size() == 1 and mod_effects[0] == true
		knife_stab = id == "knife" and mod_effects.size() == 1 and mod_effects[0] == true
		recoil = 0.75
		Sfx.play_at(self, "melee", global_position + Vector3.UP * 1.3, -8.0)
		return
	var mode: String = str(mod_effects[3]) if mod_effects.size() > 3 else ""
	# Same colours a player sees in their own hands (WeaponEffects.MODES).
	match mode:
		"frost": flash.light_color = Color(0.3, 0.8, 1)
		"plasma": flash.light_color = Color(0.4, 0.9, 1)
		"graviton": flash.light_color = Color(0.7, 0.35, 1)
		"fire": flash.light_color = Color(1, 0.3, 0.1)
		_: flash.light_color = Color(1, 0.65, 0.1)
	flash_t = 0.11 if mode == "fire" else 0.065
	recoil = minf(recoil + deg_to_rad(float(mod_effects[2] if mod_effects.size() >= 3 else Weapons.DEFS[id].kick_pitch)) * 0.5, 0.14)
	flash.visible = true
	flash.light_energy = 2.5 * (float(mod_effects[1]) if mod_effects.size() >= 3 else 1.0)
	Sfx.play_at(self, Weapons.DEFS[id].sfx, global_position + Vector3.UP * 1.3, float(mod_effects[0] if mod_effects.size() >= 3 else Weapons.DEFS[id].get("sfx_db", -8.0)), float(Weapons.DEFS[id].get("sfx_pitch", 1.0)))

func _process(delta: float) -> void:
	if not is_instance_valid(actor):
		Sfx.stop_fire_loop(self)
		return
	if not actor.alive: Sfx.stop_fire_loop(self)
	crouch_blend = move_toward(crouch_blend, 1.0 if actor.crouching and actor.alive else 0.0, delta * 6.0)
	label.position.y = 2.12 - crouch_blend * 0.6
	var speed := Vector2(actor.velocity.x, actor.velocity.z).length()
	if actor.alive and speed > 0.5:
		step_distance += speed * delta
		if step_distance > 2.1:
			step_distance = 0.0
			Sfx.play_at(self, "step_leaves", actor.global_position + Vector3.UP * 0.1, -17.0)
	body.rotation.z = lerp_angle(body.rotation.z, 0.0 if actor.alive else PI * 0.5, minf(1.0, delta * 8))
	body.position.y = lerpf(body.position.y, 0.0 if actor.alive else 0.24, minf(1.0, delta * 8))
	flash_t = maxf(0.0, flash_t - delta)
	flash.visible = flash_t > 0.0 and actor.alive
	recoil = move_toward(recoil, 0.0, delta * 0.8)
	var pitch := clampf(actor.pitch, -0.85, 0.85) if actor.alive else 0.0
	var sprinting := actor.alive and speed > 5.0
	aim.position.y = lerpf(aim.position.y, 0.85 if actor.crouching else 1.23 if sprinting else 1.40, minf(1.0, delta * 10.0))
	var swing := sin(clampf(recoil/0.75,0,1)*PI) if Weapons.is_melee(weapon) else 0.0
	aim.position.z = -0.04 - swing*(0.3 if knife_stab else 0.08)
	aim.rotation.z = swing*0.65 if not knife_stab else 0.0
	aim.rotation.x = pitch + recoil - (0.12 if sprinting else 0.0)
	if axe_heavy: aim.rotation.x = pitch - swing*1.1
	if knife_stab: aim.rotation.x = pitch - swing*1.45
	visual.pose(delta, speed, pitch, gun.to_global(right_grip), gun.to_global(left_grip), actor.alive, crouch_blend)
	var tag := Lang.raw(NetSession.roster.get(actor.peer_id, "Player"))
	label.text = Lang.t("%s\n%d / %d", [tag, maxi(0, ceili(actor.hp)), int(actor.max_hp)]) if actor.alive else Lang.t("%s\nRevive [E]", [tag])

func set_skin(finish: String) -> void:
	if not gun or _skin == finish: return
	_skin = finish
	WeaponSkins.apply(gun, finish)

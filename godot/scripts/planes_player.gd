extends Player
## Share the tested walking, crouch, jump, collision and footstep controller.
## Exploration starts unarmed; shared weapon cheats can equip the explorer.
func _unhandled_input(event: InputEvent) -> void:
	var game := get_tree().current_scene
	if game.weapons and active and event is InputEventKey and event.pressed and not event.echo:
		var slots := {KEY_1:"pistol",KEY_2:"ak47",KEY_3:"shotgun"}
		if slots.has(event.physical_keycode):
			game.weapons.set_weapon(slots[event.physical_keycode])
			get_viewport().set_input_as_handled()
	if game.weapons and active and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if (game.defences and game.defences.placing) or (game.field_building and game.field_building.placing): return
		var owned: Array = []
		for id in Weapons.ORDER:
			if game.weapons.unlocked.get(id,false): owned.append(id)
		if not owned.is_empty(): game.weapons.set_weapon(owned[posmod(owned.find(game.weapons.current)+(1 if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else -1),owned.size())])
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion or event.is_action("flashlight"):
		super._unhandled_input(event)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not active or not alive: return
	preload("res://scripts/planes_boundary.gd").confine(self)
	_motion_to = global_position

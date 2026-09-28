extends Player
## Share the tested walking, crouch, jump, collision and footstep controller.
## The shared survival loadout includes the field knife.
func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not active or not alive: return
	preload("res://scripts/planes_boundary.gd").confine(self)
	_motion_to = global_position

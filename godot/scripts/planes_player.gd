extends Player
## Share the tested walking, crouch, jump, collision and footstep controller.
## Exploration has no combat/economy input or survival HUD.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event.is_action("flashlight"):
		super._unhandled_input(event)

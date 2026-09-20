# Collectible with its own removable visuals. main.gd shows the prompt and calls take().
class_name Loot
extends Node3D

var kind := "ammo"        # "weapon" | "ammo" | "mushroom"
var id := ""              # weapon id for kind == "weapon"
var label := ""
var taken := false

func setup(k: String, weapon_id: String, text: String) -> void:
	kind = k
	id = weapon_id
	label = text
	add_to_group("render_dynamic") # Every visible child must disappear with this pickup.

func prompt_text() -> String:
	return "[E] %s sammeln" % label if kind == "mushroom" else "[E] %s aufnehmen" % label

func take(weapons: Weapons, hud: Hud) -> void:
	if NetSession.enabled:
		NetSession.command("interact", [str(get_meta("coop_id", ""))])
		return
	if taken:
		return
	taken = true
	hide()
	if kind == "mushroom":
		get_tree().current_scene.inventory.add_mushroom(id)
		if id == "steinpilz": get_tree().current_scene.progression.event("edible_mushrooms")
		Sfx.play(get_tree().current_scene, "pickup", -10.0)
		queue_free()
		return
	# World crates supply the selected gun, never grant merchant-exclusive weapons.
	var wid: String = weapons.current
	weapons.add_ammo(wid, int(Weapons.DEFS[wid].mag))
	hud.message("Vorräte: ein Magazin für " + str(Weapons.DEFS[wid].name), 2.5)
	weapons.update_hud()
	Sfx.play(get_tree().current_scene, "pickup", -6.0)
	queue_free()

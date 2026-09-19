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
		Sfx.play(get_tree().current_scene, "pickup", -10.0)
		queue_free()
		return
	if kind == "weapon":
		if weapons.unlocked.get(id, false):
			var d: Dictionary = weapons.DEFS[id]
			weapons.add_ammo(id, int(d["reserve"]))
			hud.message("%s: Munition aufgefüllt" % d["name"], 2.0)
		else:
			weapons.unlock(id)
			hud.message("%s aufgenommen" % weapons.DEFS[id]["name"], 2.5)
	else:
		for wid in weapons.unlocked:
			if weapons.unlocked[wid]:
				weapons.add_ammo(wid, int(weapons.DEFS[wid]["reserve"]))
		weapons.grenades += 2
		hud.message("Munitionskiste: alle Waffen aufgefüllt, +2 Granaten", 2.5)
	weapons.update_hud()
	Sfx.play(get_tree().current_scene, "pickup", -6.0)
	queue_free()

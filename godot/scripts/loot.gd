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
	if kind == "maze_cache":
		if not grant_cache(weapons.player, weapons): return
		taken = true
		hide()
		queue_free()
		return
	if kind != "mushroom" and not weapons.has_ammo_space(weapons.ammo_weapon()):
		hud.message("Munitionsreserve voll", 1.4)
		return
	taken = true
	hide()
	if kind == "mushroom":
		get_tree().current_scene.inventory.add_mushroom(id)
		if id == "steinpilz": get_tree().current_scene.progression.event("edible_mushrooms")
		Sfx.event(get_tree().current_scene, weapons.player.peer_id, "mushroom_pickup")
		queue_free()
		return
	# World crates supply the selected gun, never grant merchant-exclusive weapons.
	var wid: String = weapons.ammo_weapon()
	weapons.add_ammo(wid, int(Weapons.DEFS[wid].mag))
	hud.message("Vorräte: ein Magazin für " + str(Weapons.DEFS[wid].name), 2.5)
	weapons.update_hud()
	Sfx.play(get_tree().current_scene, "pickup", -6.0)
	queue_free()

# Shared host-side transaction: full inventories leave their cache untouched.
func grant_cache(p: Player, w: Weapons) -> bool:
	var game := get_tree().current_scene
	if id in ["fire","frost"]:
		var data: Dictionary = game.progression.rare_market.data(p.peer_id)
		if int(data.ammo[id])+12>96:
			p.hud.message("Spezialmunition voll",1.5)
			return false
		data.ammo[id] += 12
	elif id == "cache_cash": p.add_score(250)
	elif id == "cache_grenade":
		if w.grenades>=w.grenades_max:
			p.hud.message("Granaten voll",1.5)
			return false
		w.grenades += 1
	else:
		if not w.has_ammo_space(w.ammo_weapon()):
			p.hud.message("Munitionsreserve voll",1.5)
			return false
		w.add_ammo(w.ammo_weapon(),int(Weapons.DEFS[w.ammo_weapon()].mag)*2)
	p.hud.message(label+" gefunden",2.5)
	w.update_hud()
	Sfx.play(game,"pickup",-6)
	return true

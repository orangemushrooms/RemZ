# Collectible with its own removable visuals. main.gd shows the prompt and calls take().
class_name Loot
extends Node3D

var kind := "ammo"        # "weapon" | "ammo" | "mushroom"
var id := ""              # weapon id for kind == "weapon"
var label := ""
var taken := false

var renewable := false
var first_wave := 0
var stocked_wave := -1
var magazines := 1

func restock(wave: int) -> void:
	if not renewable or wave <= stocked_wave: return
	stocked_wave = wave
	magazines = mini(4, 1 + maxi(0, wave - 1) / 4)
	taken = wave < first_wave
	visible = not taken

func grant_supplies(w: Weapons, hud: Hud) -> bool:
	var wid := id if kind == "weapon" else w.ammo_weapon()
	if kind == "weapon" and not w.unlocked.get(wid, false):
		var reason: String = get_tree().current_scene.progression.lock_reason(w.player, wid)
		if not reason.is_empty():
			hud.message(reason, 3.0)
			return false
		w.unlock(wid)
		hud.message(Weapons.DEFS[wid].name + " gefunden", 2.5)
	else:
		if not w.has_ammo_space(wid):
			hud.message("Munitionsreserve voll", 1.4)
			return false
		hud.message("Vorräte: %d Magazin(e) für %s" % [magazines, Weapons.DEFS[wid].name], 2.5)
	w.add_ammo(wid, int(Weapons.DEFS[wid].mag) * magazines)
	w.update_hud()
	return true

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
	if kind == "mushroom":
		get_tree().current_scene.inventory.add_mushroom(id)
		if id == "steinpilz": get_tree().current_scene.progression.event("edible_mushrooms")
		Sfx.event(get_tree().current_scene, weapons.player.peer_id, "mushroom_pickup")
	else:
		if not grant_supplies(weapons, hud): return
		Sfx.play(get_tree().current_scene, "pickup", -6.0)
	taken = true
	hide()
	if not renewable: queue_free()

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

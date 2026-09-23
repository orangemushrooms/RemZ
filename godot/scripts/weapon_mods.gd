extends RefCounted

const SLOTS := ["Muzzle", "Magazine", "Bolt", "Barrel"]
const DEFS := {
	"suppressor": {"name": "Suppressor", "npc": "mechanic", "slot": "Muzzle", "price": 220, "level": 3, "quest": "arrival", "weapons": ["pistol", "smg", "ak47", "marksman", "titanbreaker", "deagle", "lever_rifle"], "desc": "14 dB quieter, 15% less recoil; 10% less range.", "mul": {"kick_pitch": 0.85, "kick_yaw": 0.85, "range": 0.9}, "db": -14.0, "flash": 0.15},
	"compensator": {"name": "Compensator", "npc": "mechanic", "slot": "Muzzle", "price": 320, "level": 4, "quest": "line", "desc": "35% less recoil.", "mul": {"kick_pitch": 0.65, "kick_yaw": 0.65}},
	"extended": {"name": "Extended Magazine", "npc": "mechanic", "slot": "Magazine", "price": 250, "level": 3, "quest": "arrival", "desc": "50% more magazine capacity (rounded up); 10% longer reload. Ammo sold separately.", "mul": {"mag": 1.5, "reload": 1.1}},
	"quick_action": {"name": "Quick Bolt", "npc": "mechanic", "slot": "Bolt", "price": 350, "level": 5, "quest": "supplies", "desc": "20% shorter reload time.", "mul": {"reload": 0.8}},
	"match_barrel": {"name": "Match Barrel", "npc": "mechanic", "slot": "Barrel", "price": 450, "level": 6, "quest": "steady_aim", "desc": "30% less spread, 20% more range.", "mul": {"spread": 0.7, "range": 1.2}},
	"ghost": {"name": "Phantom · Legendary", "npc": "secret", "slot": "Muzzle", "price": 1200, "level": 10, "quest": "silent_deal", "weapons": ["pistol", "smg", "ak47", "marksman", "titanbreaker", "deagle", "lever_rifle", "cryo_smg"], "desc": "24 dB quieter, 30% less recoil, almost no muzzle flash. Full range.", "mul": {"kick_pitch": 0.7, "kick_yaw": 0.7}, "db": -24.0, "flash": 0.03},
	"endless": {"name": "Siege Magazine · Legendary", "npc": "secret", "slot": "Magazine", "price": 1400, "level": 12, "quest": "clockwork", "desc": "Double magazine capacity; 15% longer reload. Ammo sold separately.", "mul": {"mag": 2.0, "reload": 1.15}},
	"titan_core": {"name": "Titan Core · Legendary", "npc": "secret", "slot": "Barrel", "price": 1800, "level": 16, "quest": "giant_debt", "weapons": ["marksman", "lmg", "titanbreaker", "graviton_cannon", "plasma_sniper"], "desc": "20% more damage and one extra penetration target.", "mul": {"damage": 1.2}, "pierce": 1},
}

# A mod fits when the mod itself lists the weapon (or lists nothing, meaning "any firearm") and the
# weapon does not veto it. The veto lives in Weapons.DEFS as "mod_block": an energy rifle has no
# magazine to extend, a six barrel rotary gun has no muzzle to thread and a flare launcher has no
# rifling to match - without it, every mod without a whitelist would be buyable on all of them.
static func compatible(id: String, wid: String, base: Dictionary) -> bool:
	if not DEFS.has(id) or base.get("melee", false): return false
	if id in base.get("mod_block", []): return false
	return wid in DEFS[id].get("weapons", [wid])

static func definition(base: Dictionary, loadout: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for slot in SLOTS:
		var id: String = loadout.get(slot, "")
		if not DEFS.has(id): continue
		var spec: Dictionary = DEFS[id]
		for key in spec.mul:
			result[key] = float(result[key]) * float(spec.mul[key])
		result.sfx_db = float(result.get("sfx_db", -6.0)) + float(spec.get("db", 0))
		result.flash_scale = float(spec.get("flash", result.get("flash_scale", 1.0)))
		if spec.has("pierce"): result.pierce_targets = int(result.get("pierce_targets", 1)) + int(spec.pierce)
	result.mag = ceili(float(result.mag))
	return result

# Portable text: each name is its own segment, so a joined list still translates where it is shown.
static func summary(loadout: Dictionary) -> String:
	var names := PackedStringArray()
	for slot in SLOTS:
		var id: String = loadout.get(slot, "")
		if DEFS.has(id): names.append(Lang.t(DEFS[id].name))
	return Lang.t("No mods") if names.is_empty() else " · ".join(names)

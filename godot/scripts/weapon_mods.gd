extends RefCounted

const SLOTS := ["Mündung", "Magazin", "Verschluss", "Lauf"]
const DEFS := {
	"suppressor": {"name": "Schalldämpfer", "npc": "mechanic", "slot": "Mündung", "price": 220, "level": 3, "quest": "arrival", "weapons": ["pistol", "smg", "ak47", "marksman", "titanbreaker"], "desc": "14 dB leiser, 15 % weniger Rückstoß; 10 % weniger Reichweite.", "mul": {"kick_pitch": 0.85, "kick_yaw": 0.85, "range": 0.9}, "db": -14.0, "flash": 0.15},
	"compensator": {"name": "Kompensator", "npc": "mechanic", "slot": "Mündung", "price": 320, "level": 4, "quest": "line", "desc": "35 % weniger Rückstoß.", "mul": {"kick_pitch": 0.65, "kick_yaw": 0.65}},
	"extended": {"name": "Erweitertes Magazin", "npc": "mechanic", "slot": "Magazin", "price": 250, "level": 3, "quest": "arrival", "desc": "50 % mehr Magazinkapazität (aufgerundet); 10 % längeres Nachladen. Munition separat.", "mul": {"mag": 1.5, "reload": 1.1}},
	"quick_action": {"name": "Schnellverschluss", "npc": "mechanic", "slot": "Verschluss", "price": 350, "level": 5, "quest": "supplies", "desc": "20 % kürzere Nachladezeit.", "mul": {"reload": 0.8}},
	"match_barrel": {"name": "Präzisionslauf", "npc": "mechanic", "slot": "Lauf", "price": 450, "level": 6, "quest": "steady_aim", "desc": "30 % weniger Streuung, 20 % mehr Reichweite.", "mul": {"spread": 0.7, "range": 1.2}},
	"ghost": {"name": "Phantom · Legendär", "npc": "secret", "slot": "Mündung", "price": 1200, "level": 10, "quest": "silent_deal", "weapons": ["pistol", "smg", "ak47", "marksman", "titanbreaker"], "desc": "24 dB leiser, 30 % weniger Rückstoß, fast kein Mündungsblitz. Volle Reichweite.", "mul": {"kick_pitch": 0.7, "kick_yaw": 0.7}, "db": -24.0, "flash": 0.03},
	"endless": {"name": "Belagerungsmagazin · Legendär", "npc": "secret", "slot": "Magazin", "price": 1400, "level": 12, "quest": "clockwork", "desc": "Doppelte Magazinkapazität; 15 % längeres Nachladen. Munition separat.", "mul": {"mag": 2.0, "reload": 1.15}},
	"titan_core": {"name": "Titanenkern · Legendär", "npc": "secret", "slot": "Lauf", "price": 1800, "level": 16, "quest": "giant_debt", "weapons": ["marksman", "lmg", "titanbreaker"], "desc": "20 % mehr Schaden und ein zusätzliches Durchschussziel.", "mul": {"damage": 1.2}, "pierce": 1},
}

static func compatible(id: String, wid: String, base: Dictionary) -> bool:
	return DEFS.has(id) and not base.get("melee", false) and wid in DEFS[id].get("weapons", [wid])

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

static func summary(loadout: Dictionary) -> String:
	var names := PackedStringArray()
	for slot in SLOTS:
		var id: String = loadout.get(slot, "")
		if DEFS.has(id): names.append(DEFS[id].name)
	return "Keine Mods" if names.is_empty() else " · ".join(names)

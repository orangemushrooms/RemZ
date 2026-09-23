extends RefCounted

const DEFS := {
	"hawk": {"name": "Hawk Eye · Legendary", "price": 1800, "level": 5, "kind": "relic", "desc": "35% less spread and 20% less recoil.", "bonuses": {"spread": 0.65, "recoil": 0.8}},
	"bark": {"name": "Heart of the Ancient Oak · Legendary", "price": 2200, "level": 8, "kind": "relic", "desc": "20% less damage taken.", "bonuses": {"guard": 0.8}},
	"blood": {"name": "Bloodstone · Legendary", "price": 2600, "level": 10, "kind": "relic", "desc": "Your own weapon and burn kills heal 3 health; tower kills do not heal.", "bonuses": {}},
	"wind": {"name": "Storm Feather · Legendary", "price": 2500, "level": 9, "kind": "relic", "desc": "20% faster reloads and 10% more movement speed.", "bonuses": {"reload": 0.8, "speed": 1.1}},
	"phoenix": {"name": "Phoenix Ash · Legendary", "price": 3800, "level": 15, "kind": "relic", "desc": "Prevents one fatal hit per wave and restores 40% health. Switching does not reset the charge.", "bonuses": {}},
	"coin": {"name": "The Peddler's Toll · Legendary", "price": 1900, "level": 6, "kind": "relic", "desc": "20% more Rem Dollars for your own kills.", "bonuses": {"score": 1.2}},
	"owl": {"name": "Owl Eye · Legendary", "price": 2000, "level": 6, "kind": "relic", "time": ["night"], "desc": "30% less spread and 15% less recoil. Only on offer at night.", "bonuses": {"spread": 0.7, "recoil": 0.85}},
	"moss": {"name": "Moss Cloak · Legendary", "price": 2100, "level": 7, "kind": "relic", "region": ["N", "W"], "desc": "15% less damage taken and 5% more speed. The peddler carries it in the North and West Forest.", "bonuses": {"guard": 0.85, "speed": 1.05}},
	"raven": {"name": "Raven Feather · Legendary", "price": 2200, "level": 8, "kind": "relic", "time": ["night"], "desc": "30% faster reloads. Only on offer at night.", "bonuses": {"reload": 0.7}},
	"ember": {"name": "Ember Core · Legendary", "price": 2400, "level": 8, "kind": "relic", "time": ["day"], "desc": "15% more weapon damage. Only on offer in daylight.", "bonuses": {"damage": 1.15}},
	"stag": {"name": "Stag Crown · Legendary", "price": 2300, "level": 9, "kind": "relic", "region": ["E", "S"], "desc": "18% more movement speed. The peddler carries it in the East and South Forest.", "bonuses": {"speed": 1.18}},
	"steel": {"name": "Steel Heart · Legendary", "price": 2500, "level": 10, "kind": "relic", "time": ["day"], "desc": "45% less recoil. Only on offer in daylight.", "bonuses": {"recoil": 0.55}},
	"lantern": {"name": "Mist Lantern · Legendary", "price": 2800, "level": 11, "kind": "relic", "time": ["night"], "region": ["N", "E"], "desc": "15% less damage taken and 8% more weapon damage. At night in the North and East Forest.", "bonuses": {"guard": 0.85, "damage": 1.08}},
	"root": {"name": "Root Band · Legendary", "price": 3000, "level": 12, "kind": "relic", "region": ["W", "S"], "desc": "25% less damage taken. The peddler carries it in the West and South Forest.", "bonuses": {"guard": 0.75}},
	"fire": {"name": "Dragon's Breath · Fire Rounds", "price": 480, "level": 5, "kind": "ammo", "amount": 24, "desc": "24 rounds. Hits set zombies on fire: 36 burn damage over 3 s. Further hits refresh the duration, they do not stack."},
	"frost": {"name": "Winter's Bite · Frost Rounds", "price": 520, "level": 7, "kind": "ammo", "amount": 18, "desc": "18 rounds. Hits slow zombies by 45% for 3 s, titans by 20%."},
}
const AMMO_CAP := 96

static func multiplier(relic: String, attribute: String) -> float:
	return float(DEFS.get(relic, {}).get("bonuses", {}).get(attribute, 1.0))

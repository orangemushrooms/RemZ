class_name RunRules
extends RefCounted
## Stable seeded domains: art, loot and frame timing cannot alter wave composition.
const VERSION := 1
const MODES := ["standard", "pistols", "fortress", "sprint"]
const MODE_NAMES := ["Standard expedition", "Pistols only", "Four tower challenge", "Ten wave assault"]
const PROFILE_NAMES := ["Open field assault", "Woodland emergence", "Cornfield ambush", "Concentrated assault"]
const AUGMENTS := {
	"frost": ["Frost grenades", "Grenades chill survivors for six seconds. Bosses resist the slow."],
	"overdrive": ["Tower overdrive", "Your towers fire 25% faster and generate 40% more heat."],
	"swap": ["Swap rhythm", "Switching weapons grants three seconds of faster reload and improved precision. Eight second cooldown."],
	"medic": ["Field medic", "Start with two extra bandages. Healing a teammate restores 45 health."],
	"scout": ["Light equipment", "Move 8% faster while carrying no supply crate."],
	"reserve": ["Reserve supply", "Receive ammunition and one grenade when selecting this augment."]
}
const BESTIARY := {
	"shambler": ["Shambler", "Slow pursuit. Aim at the head and keep an escape route."],
	"runner": ["Runner", "Fast flanking attacks. Slow it with frost or suppressive fire."],
	"nurse": ["Nurse", "Heals nearby enemies. Eliminate her before clearing the crowd."],
	"soldier": ["Soldier", "Armour can absorb head hits. Break the helmet or aim at exposed limbs."],
	"brute": ["Brute", "Strong melee attacks. Keep distance and concentrate fire."],
	"bride": ["Bride", "Calls reinforcements. Interrupt her approach and clear her escort."],
	"spitter": ["Spitter", "Ranged acid attacks. Move sideways and avoid acid pools."],
	"screamer": ["Screamer", "Marks a player for the horde. Kill her quickly and regroup."],
	"stalker": ["Stalker", "Uses darkness and crops. Listen for movement and cover your flanks."],
	"zombie_dog": ["Infected dog", "Small, fast target. Shotguns and slow fields control a pack."],
	"zombie_stag": ["Infected stag", "Charges across open ground. Dodge sideways and avoid antlers."],
	"titan": ["Titan", "Heavy boss. Shoot exposed weak points and avoid the charge and thrown debris."],
	"titan_hunter": ["Hunter Titan", "Pursues isolated players. Stay together and move between cover."],
	"titan_siege": ["Siege Titan", "Attacks fortifications. Repair between attacks and focus its weak points."],
	"titan_ash": ["Ash Titan", "Fire makes close defence dangerous. Keep room to retreat."],
	"earthworm": ["Earthworm", "Burrows underground. Avoid earth rings and fire when it emerges."],
	"earthworm_ancient": ["Ancient earthworm", "Longer, stronger burrowing assault. Save heavy ammunition for exposed phases."],
	"forest_spirit": ["Forest spirit", "Uses forest cover and supernatural attacks. Watch its telegraphs and keep moving."]
}
const LORE := [
	["The last transmission", "The radio log ends with a promise: hold the signal until sunrise. Someone is still listening."],
	["Supply manifest", "A drone carried medicine to the camp. Its route was changed after lights appeared in the corn."],
	["Station notebook", "Three transmitters repeat the same call. Their order changes each night. The receiver remembers only a complete sequence."],
	["A survivor's note", "We left supplies along the field paths. The hill gives a clear shot, but the woods hide the return journey."],
	["Morning watch", "The barricades bought us time. What remains at dawn tells the story of those who stood here."]
]

static func clean(raw: Dictionary) -> Dictionary:
	var seed_value: Variant = raw.get("seed", 1)
	var run_seed := 1
	if (seed_value is int or seed_value is float) and is_finite(float(seed_value)):
		run_seed = clampi(int(seed_value), 1, 2147483647)
	return {"seed": run_seed, "region": "planes" if raw.get("region") == "planes" else "forest",
		"difficulty": clampi(int(raw.get("difficulty", 0)), 0, GameSettings.DIFFICULTIES.size()-1),
		"mode": str(raw.get("mode")) if raw.get("mode") in MODES else "standard"}

static func encode(raw: Dictionary) -> String:
	var c := clean(raw)
	var body := "RZ1-%s-%08X-%d-%d" % ["P" if c.region == "planes" else "F", c.seed, c.difficulty, MODES.find(c.mode)]
	return body + "-" + body.sha256_text().left(8).to_upper()

static func decode(value: String) -> Dictionary:
	var code := value.strip_edges().to_upper()
	if code.length() > 48: return {}
	var p := code.split("-")
	if p.size() != 6 or p[0] != "RZ1" or p[1] not in ["P", "F"] or p[2].length() != 8: return {}
	if not p[2].is_valid_hex_number() or not p[3].is_valid_int() or not p[4].is_valid_int(): return {}
	var body := "-".join(p.slice(0, 5))
	if body.sha256_text().left(8).to_upper() != p[5]: return {}
	var run_seed := p[2].hex_to_int()
	var difficulty := int(p[3])
	var mode := int(p[4])
	if run_seed < 1 or run_seed > 2147483647 or difficulty < 0 or difficulty >= GameSettings.DIFFICULTIES.size() or mode < 0 or mode >= MODES.size(): return {}
	return {"seed": run_seed, "region": "planes" if p[1] == "P" else "forest", "difficulty": difficulty, "mode": MODES[mode]}

static func rng(config: Dictionary, domain: String, index: int = 0) -> RandomNumberGenerator:
	var result := RandomNumberGenerator.new()
	result.seed = ("%d:%s:%d" % [int(config.seed), domain, index]).sha256_text().left(15).hex_to_int()
	return result

static func shuffled(values: Array, random: RandomNumberGenerator) -> Array:
	var copy := values.duplicate(true)
	for i in range(copy.size()-1, 0, -1):
		var j := random.randi_range(0, i)
		var old: Variant = copy[i]
		copy[i] = copy[j]
		copy[j] = old
	return copy

static func rounds(config: Dictionary) -> int:
	return 10 if config.mode == "sprint" else Campaign.ROUNDS

static func weapon_allowed(config: Dictionary, id: String) -> bool:
	return config.mode != "pistols" or id in ["pistol", "magnum", "sig_p226", "nighthawk", "deagle", "revolver", "flare_pistol", "knife"]

static func tower_limit(config: Dictionary) -> int:
	return 4 if config.mode == "fortress" else DefenceTower.LIMIT

static func weather_plan(config: Dictionary) -> Array:
	var random := rng(config, "weather")
	var result: Array = [{"state": "clear", "seconds": random.randi_range(150, 240)}]
	for i in 32:
		var choices := ["clear", "fog", "rain", "storm"]
		choices.erase(result[-1].state)
		result.append({"state": choices[random.randi_range(0, choices.size()-1)], "seconds": random.randi_range(90, 210)})
	return result

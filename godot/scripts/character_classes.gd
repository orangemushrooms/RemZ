extends RefCounted
## Stable IDs are shared by saves, the lobby and combat. Balancing lives here and in class_combat.gd.
const MAX_LEVEL := 30
const TIERS := [5, 10, 15, 20, 25, 30]
const ORDER := ["gunslinger", "assault", "breacher", "marksman", "assassin"]
const ACHIEVEMENTS := [
	["first_blood", "First Blood", "Defeat your first zombie.", 250],
	["exterminator", "Exterminator", "Defeat 10,000 zombies across all classes.", 5000],
	["perfect_aim", "Perfect Aim", "Score 100 headshots across all classes.", 1000],
	["veteran", "Class Veteran", "Reach level 30 with one class.", 2500],
	["master_of_arms", "Master of Arms", "Reach level 30 with all five classes.", 5000],
	["untouchable", "Untouchable Survivor", "Complete an entire Hard or Nightmare mission without taking damage.", 2000]
]
const XP_STEPS := [1100, 1650, 2200, 2750, 3300, 4180, 5060, 5940, 6820, 7700,
	9020, 10340, 11660, 12980, 14300, 16060, 17820, 19580, 21340, 23100,
	25520, 27940, 30360, 32780, 35200, 40150, 45100, 50050, 55000]
const CLASSES := {
	"gunslinger": {"name": "Gunslinger", "role": "Mobility and precision with pistols and revolvers.", "color": Color("e5b660"), "weapons": ["pistol", "revolver", "deagle", "flare_pistol"], "talents": [
		[["quick_hands", "Quick Hands", "Pistols reload 20% faster."], ["steady_hand", "Steady Hand", "15% less pistol recoil."]],
		[["duelist", "Duelist", "Repeated pistol hits on one target add 5% damage per hit, up to 25%, for 3 seconds."], ["quick_swap", "Quick Draw", "Switching to or from a pistol is 50% faster."]],
		[["bounty", "Bounty", "Pistol headshots deal 15% more damage. Headshot kills grant 5 extra XP."], ["fan_hammer", "Fan the Hammer", "Pistol shots build 40% less spread."]],
		[["sidestep", "Sidestep", "Pistol kills grant 15% movement speed for 3 seconds."], ["ice_cold", "Ice Cold", "Pistol headshots reduce recoil by 30% for 3 seconds."]],
		[["high_noon", "High Noon", "Pistol headshot kills reduce reload time by 8% for 5 seconds, up to 3 stacks."], ["executioner", "Executioner", "Pistols deal 25% more damage to targets below 30% health."]],
		[["deadeye", "Deadeye", "Consecutive pistol headshots add 8% critical damage, up to 40%. A miss or body hit resets the chain."], ["gunslinger", "Gunslinger Mastery", "10% more pistol damage and 15% faster movement while aiming a pistol."]]
	]},
	"assault": {"name": "Assault Trooper", "role": "Controlled sustained fire and reliable crowd control with assault rifles.", "color": Color("90bc91"), "weapons": ["ak47", "lmg"], "talents": [
		[["tactical_reload", "Tactical Reload", "Assault rifles reload 18% faster."], ["ammo_discipline", "Ammo Discipline", "15% larger assault rifle magazines."]],
		[["burst", "Controlled Burst", "The first 3 shots of an assault rifle burst have 25% less spread."], ["suppression", "Suppressing Fire", "Repeated assault rifle hits slow common enemies by 15% for 2 seconds."]],
		[["frontline", "Frontline", "Assault rifle kills reduce recoil by 25% for 4 seconds."], ["combat_drill", "Combat Drill", "Assault rifle kills reduce reload time by 25% for 4 seconds."]],
		[["armor_breaker", "Armor Breaker", "Assault rifles deal 25% more damage against armoured enemies."], ["crowd_control", "Crowd Control", "Assault rifles deal 12% more damage against common zombies."]],
		[["combat_momentum", "Combat Momentum", "Assault rifle kills increase fire rate by 6% for 4 seconds, up to 3 stacks."], ["veteran", "Veteran", "Assault rifles reload 30% faster with a quarter magazine or less."]],
		[["weapons_expert", "Weapons Expert", "Assault rifles gain 10% less recoil, 10% faster reloads and 10% larger magazines."], ["last_stand", "Last Stand", "Below 30% health: 20% less recoil, 20% faster reloads and 10% more movement speed."]]
	]},
	"breacher": {"name": "Breacher", "role": "Shotguns, close quarters and powerful penetration.", "color": Color("da8770"), "weapons": ["shotgun", "breacher"], "talents": [
		[["large_caliber", "Large Calibre", "Shotguns deal 12% more damage."], ["speed_loader", "Speed Loader", "Shotguns reload 20% faster."]],
		[["penetration", "Penetration", "Shotgun pellets penetrate one additional common enemy."], ["tight_spread", "Spread Control", "25% less shotgun spread."]],
		[["knockback", "Knockback", "Shotgun hits shove common zombies back more strongly."], ["bloodbath", "Bloodbath", "Shotgun kills within 5 metres grant 15% shotgun damage for 4 seconds."]],
		[["breaching", "Breaching", "Shotguns deal 25% more damage against armoured and large enemies."], ["crowd_breaker", "Crowd Breaker", "20% more shotgun damage when 3 enemies stand within 5 metres of the target."]],
		[["no_mercy", "No Mercy", "Shotgun hits within 4 metres deal 20% more damage."], ["stand_ground", "Stand Your Ground", "15% less damage taken while at least 3 enemies are within 6 metres."]],
		[["juggernaut", "Juggernaut", "Shotgun kills grant 20% damage resistance for 4 seconds."], ["boomstick", "Boomstick", "The first shotgun blast from a full magazine deals 35% more damage."]]
	]},
	"marksman": {"name": "Marksman", "role": "Precision rifles, critical hits and dangerous elite targets.", "color": Color("86b8d9"), "weapons": ["marksman", "lever_rifle", "plasma_sniper", "titanbreaker"], "talents": [
		[["firm_stance", "Firm Stance", "50% less weapon sway while aiming a precision rifle."], ["fast_focus", "Fast Focus", "Aim a precision rifle 30% faster."]],
		[["weak_spot", "Weak Spot", "Precision rifle headshots deal 20% more damage."], ["piercing", "Piercing Shot", "Precision rifle shots penetrate one additional enemy."]],
		[["hunter", "Elite Hunter", "Precision rifles deal 20% more damage against special enemies."], ["one_shot", "One Shot", "The first precision rifle hit on each target deals 20% more damage."]],
		[["breath_control", "Breath Control", "Aiming a precision rifle steadily reduces spread by up to 40% over 3 seconds."], ["quickscope", "Quickscope", "Precision headshots within 0.6 seconds of aiming deal 20% more damage."]],
		[["kill_chain", "Kill Chain", "A precision headshot kill boosts the next precision hit by 25% for 5 seconds."], ["big_game", "Big Game Hunter", "Precision rifles deal 30% more damage against elites and bosses."]],
		[["perfect_shot", "Perfect Shot", "After 4 seconds without a miss, the next precision headshot deals 50% more damage. Resets on use."], ["rhythm", "Marksman's Rhythm", "Consecutive precision hits reduce reload time and aim time by 5%, up to 25%. A miss resets the chain."]]
	]},
	"assassin": {"name": "Assassin", "role": "Speed, stealth and positioning. Flexible with every weapon.", "color": Color("b6a0d8"), "weapons": [], "talents": [
		[["light_footed", "Light Footed", "10% faster movement."], ["ghost_step", "Ghost Step", "Quieter footsteps and 20% less detection range for common enemies."]],
		[["opportunist", "Opportunist", "15% more damage against enemies attacking another player."], ["escape_artist", "Escape Artist", "Taking at least 25 damage grants 20% movement speed for 3 seconds."]],
		[["weapon_master", "Weapon Master", "10% faster reloads and 25% faster weapon switches."], ["silent_killer", "Silent Killer", "Attacks from behind deal 20% more damage."]],
		[["shadow", "Shadow", "After 4 seconds without attacking, common enemies detect you from 35% less distance."], ["momentum", "Momentum", "Weapon kills grant 15% movement speed for 4 seconds."]],
		[["assassination", "Assassination", "The first hit from behind or against an unaware target deals 35% more damage."], ["untouchable", "Untouchable Movement", "After 8 seconds without taking damage, gain 12% movement speed until hit."]],
		[["master_assassin", "Master Assassin", "5% faster movement, 20% faster weapon switches and 15% less detection range."], ["predator", "Predator", "After 5 seconds without attacking or taking damage, the next attack has 50% less spread and 25% more headshot damage."]]
	]}
}

static func level_for(total: int) -> int:
	var level := 1
	for cost in XP_STEPS:
		if total < cost: break
		total -= cost
		level += 1
	return level

static func threshold(level: int) -> int:
	var total := 0
	for i in clampi(level - 1, 0, 29): total += XP_STEPS[i]
	return total

static func quest_xp(dollars: int) -> int:
	return maxi(500, dollars * 2)

static func progress(total: int) -> Dictionary:
	var level := level_for(total)
	return {"level": level, "xp": total - threshold(level), "required": XP_STEPS[level - 1] if level < MAX_LEVEL else 0}

static func valid_choices(id: String, level: int, choices: Variant) -> Array:
	var result: Array = [-1, -1, -1, -1, -1, -1]
	if not CLASSES.has(id) or not choices is Array: return result
	for i in mini(choices.size(), TIERS.size()):
		if (choices[i] is int or choices[i] is float) and is_finite(float(choices[i])) and (float(choices[i]) == 0.0 or float(choices[i]) == 1.0) and level >= TIERS[i]: result[i] = int(choices[i])
	return result

static func loadout(id: String, total: int, choices: Array) -> Dictionary:
	if not CLASSES.has(id): id = ORDER[0]
	var level := level_for(total)
	return {"id": id, "level": level, "choices": valid_choices(id, level, choices)}

static func sanitize_loadout(data: Variant) -> Dictionary:
	if not data is Dictionary: return {}
	var id: Variant = data.get("id")
	var level: Variant = data.get("level")
	if not id is String or not CLASSES.has(id) or not (level is int or level is float): return {}
	if not is_finite(float(level)) or float(level) != floor(float(level)) or level < 1 or level > MAX_LEVEL: return {}
	return {"id": id, "level": int(level), "choices": valid_choices(id, int(level), data.get("choices", []))}

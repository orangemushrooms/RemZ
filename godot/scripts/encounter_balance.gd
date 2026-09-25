class_name EncounterBalance
extends RefCounted

# One headline encounter per wave; special enemies replace part of the horde.
static func worm_count(wave: int) -> int:
	if wave < 12 or wave % 4 != 0: return 0
	return 1 if wave < 24 else (2 if wave < 40 else 3)

static func titan_count(wave: int) -> int:
	if wave < 6 or wave % 3 != 0 or worm_count(wave) > 0 or wave % 5 == 0: return 0
	return mini(3, 1 + wave / 18)

static func lesser_count(wave: int) -> int:
	if wave < 8 or worm_count(wave) > 0 or titan_count(wave) > 0 or wave % 5 == 0: return 0
	return 1 if wave < 24 else 2

static func brute_count(wave: int) -> int:
	return mini(7, 2 + wave / 10) if wave % 5 == 0 else 0

static func horde_share(wave: int) -> float:
	if worm_count(wave) > 0: return 0.68
	if titan_count(wave) > 0: return 0.72
	if wave % 5 == 0: return 0.82
	if lesser_count(wave) > 0: return 0.88
	return 1.0

# The common horde toughens with every wave (Sep 2026): +6 % health per wave, capped at x2.5 by wave 26.
# Bosses have their own curve (heavy_hp). Difficulty and party size multiply on top.
static func horde_hp(wave: int) -> float:
	return minf(2.2, 1.0 + maxf(0, wave - 1) * 0.05)

# Every extra teammate makes the common horde tougher as well (25 Sep 2026): +30 % health and +12 % damage
# per additional player, on top of the +55 % head count in Waves.regular_count. Bosses use heavy_hp.
static func party_hp(party: int) -> float:
	return 1.0 + 0.3 * clampi(party - 1, 0, 3)

static func party_damage(party: int) -> float:
	return 1.0 + 0.12 * clampi(party - 1, 0, 3)

static func heavy_limit(wave: int) -> int:
	return 2 if wave < 24 else 3

static func heavy_hp(wave: int, party: int, worm: bool = false) -> float:
	var progression := minf(2.6, 1.0 + maxf(0, wave - (12 if worm else 6)) * 0.045)
	return progression * (1.0 + 0.5 * clampi(party - 1, 0, 3))

static func heavy_damage(wave: int, worm: bool = false) -> float:
	return minf(1.4, 1.0 + maxf(0, wave - (12 if worm else 6)) * 0.012)

static func heavy_speed(speed: float) -> float:
	return clampf(speed, 0.8, 1.25)

static func title(wave: int) -> String:
	if worm_count(wave) > 0: return "WORM WAVE"
	if wave % 5 == 0: return "BOSS WAVE"
	if titan_count(wave) + lesser_count(wave) > 0: return "TITANS"
	return "HORDE"

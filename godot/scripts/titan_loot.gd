# Bonus equipment roll, independent of the titan's normal supply drop.
class_name TitanLoot
extends RefCounted

const EPIC_CHANCE := 0.35
const LEGENDARY_CHANCE := 0.10
const LIFETIME := 180.0
const COLLECT_DELAY := 2.4 # Let the giant finish falling before collecting its reward.
static var _pools: Dictionary = {}

static func rarity(kind: String, id: String) -> String:
	if kind == "weapon" and id in FortuneWheels.weapon_pool():
		var tier := FortuneWheels.tier_of(id).trim_prefix("weapon_")
		return tier if tier in ["epic", "legendary"] else ""
	if kind == "relic" and Player.RareItems.DEFS.get(id, {}).get("kind", "") == "relic": return "legendary"
	return ""

static func pool(tier: String) -> Array:
	if not _pools.has(tier):
		var entries: Array = []
		for id in FortuneWheels.weapon_pool():
			if rarity("weapon", id) == tier: entries.append({"kind": "weapon", "id": id})
		if tier == "legendary":
			for id in Player.RareItems.DEFS:
				if rarity("relic", id) == tier: entries.append({"kind": "relic", "id": id})
		_pools[tier] = entries
	return _pools[tier]

static func roll(rng: RandomNumberGenerator) -> Dictionary:
	var draw := rng.randf()
	var tier := "legendary" if draw < LEGENDARY_CHANCE else "epic" if draw < LEGENDARY_CHANCE + EPIC_CHANCE else ""
	if tier.is_empty(): return {}
	var choices := pool(tier)
	return choices[rng.randi_range(0, choices.size() - 1)].duplicate() if not choices.is_empty() else {}

static func spawn(game: Node, at: Vector3, reward: Dictionary) -> Pickup:
	# Only the authority creates rewards. Replicas receive the item in a snapshot.
	if NetSession.is_client() or reward.is_empty() or rarity(str(reward.get("kind", "")), str(reward.get("id", ""))).is_empty(): return null
	var drop := Pickup.new()
	drop.item_id = reward.id
	drop.setup(reward.kind)
	game.add_child(drop)
	drop.global_position = Vector3(at.x, Map.ground_height(at.x, at.z) + 0.08, at.z)
	return drop

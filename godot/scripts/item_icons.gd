class_name ItemIcons
extends RefCounted

const DIR := "res://assets/ui/items/"
static var _cache: Dictionary = {}

static func texture(id: String) -> Texture2D:
	if not _cache.has(id):
		var path := DIR + id + ".png"
		if not ResourceLoader.exists(path): path = DIR + id + ".svg"
		_cache[id] = load(path) if ResourceLoader.exists(path) else load(DIR + "item.svg")
	return _cache[id]

static func view(id: String, dimensions := Vector2(100, 72)) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture(id)
	image.custom_minimum_size = dimensions
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

static func action_id(action: Callable) -> String:
	var args := action.get_bound_arguments()
	if args.is_empty(): return "item"
	match str(args[0]):
		"rare": return "ammo" if args[1] in ["fire", "frost"] else "relic"
		"mod", "remove_mod": return str(args[2])
		"weapon", "sell_weapon", "sell_mushroom": return str(args[1])
		"ammo", "sell_ammo", "autorefill": return "ammo"
		"medicine": return "medicine"
		"grenade", "sell_grenade": return "grenade"
		"quest": return "quest"
		"training": return "skill_" + str(args[1])
		"tower_upgrade", "tower_sell": return "tower"
		"skin": return "skin_" + str(args[1])
		"stock_skin": return str(args[1])
	return "item"

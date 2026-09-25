class_name ItemIcons
extends RefCounted

const DIR := "res://assets/ui/items/"
static var _cache: Dictionary = {}

static func texture(id: String) -> Texture2D:
	if not _cache.has(id):
		var path := DIR + id + ".png"
		if not ResourceLoader.exists(path): path = DIR + id + ".svg"
		# a tower kind without its own render (tower_<kind>.png) falls back to the generic tower
		if not ResourceLoader.exists(path) and id.begins_with("tower_"): path = DIR + "tower.png"
		_cache[id] = load(path) if ResourceLoader.exists(path) else load(DIR + "item.svg")
	return _cache[id]

# The icon of a standing tower's kind (26 Sep 2026: the Mechanic's upgrade rows show the tower they
# upgrade - its render, not a generic turret).
static func tower_icon(id: String) -> String:
	if not id.is_valid_int(): return "tower"
	var loop := Engine.get_main_loop()
	var scene: Node = loop.current_scene if loop is SceneTree else null
	if scene and "defences" in scene and scene.defences and scene.defences.towers.has(int(id)):
		var tower = scene.defences.towers[int(id)]
		if is_instance_valid(tower): return "tower_" + str(tower.kind)
	return "tower"

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
		"firework": return Fireworks.icon_id(str(args[1]))
		"rare": return "ammo" if args[1] in ["fire", "frost"] else "relic"
		"mod", "remove_mod": return str(args[2])
		"weapon", "sell_weapon", "sell_mushroom", "sell_meat": return str(args[1])
		"ammo", "sell_ammo", "autorefill": return "ammo"
		"medicine": return "medicine"
		"grenade", "sell_grenade": return "grenade"
		"quest": return "quest"
		"training": return "skill_" + str(args[1])
		"tower_upgrade", "tower_sell": return tower_icon(str(args[1]))
		"skin": return "skin_" + str(args[1])
		"stock_skin": return str(args[1])
	return "item"

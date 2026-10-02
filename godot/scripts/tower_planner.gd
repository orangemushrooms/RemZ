# Top-down tower planner (25 Sep 2026): T opens a bird's-eye view over the forest hut, the tower types on a
# card at the left, the six roof slots as markers, the mouse places a tower anywhere within PLANNER_REACH of
# the player, drags a standing ground tower to a new spot and the wheel / R turns the ghost. Everything goes
# through DefenceSystem (placement_error with planner = true, purchase, relocate, rotate_tower) so the host
# validates every move in co-op as before.
class_name TowerPlanner
extends CanvasLayer

const INK := Color(0.035, 0.048, 0.047, 0.97)
const MUTED := Color(0.61, 0.68, 0.65)
const PAPER := Color(0.93, 0.95, 0.9)
const GOLD := Color(0.94, 0.76, 0.43)
const GREEN := Color(0.35, 0.89, 0.66)
const RED := Color(1.0, 0.28, 0.22)
const VIEW_SIZE := 34.0            # the roof and its near surroundings (was 68: the hut was a stamp in the middle)
const VIEW_MIN := 18.0
const VIEW_MAX := 80.0
const PLANNER_REACH := 45.0
const HUT_VIEW_RANGE := 22.0       # farther from the hut than this, the planner opens over the player instead
const ROOF_SNAP := 2.2              # a click this close to a roof slot goes onto the slot

var defences: Node
var game: Node
var player: Player
var is_open := false
var overview: Camera3D
var panel: Control
var kind_buttons: Dictionary = {}
var roof_buttons: Array[Button] = []
var wallet: Label
var status: Label
var hint: Label
var title: Label
# 2 Oct 2026: the type list became a build bar of render tiles along the bottom edge (kind_buttons are the
# tiles) and the left card shows the selected tower large: icon, price, range, effect, tiers, unlock.
const Style = preload("res://scripts/character_style.gd")
var bar: PanelContainer
var bar_row: HBoxContainer
var tile_icons: Dictionary = {}
var tile_prices: Dictionary = {}
var tile_badges: Dictionary = {}
var tile_keys: Dictionary = {}
var selected_icon: TextureRect
var selected_name: Label
var selected_meta: Label
var selected_info: Label
var selected_tiers: Label
var selected_reason: Label
var _hover_kind := ""
var selected_roof := -1
var hover_point := Vector3.INF
var hover_valid := false
var hover_tower: DefenceTower = null
var dragging: DefenceTower = null
var drag_moved := false
var ghost_yaw := 0.0
var roof_markers: Array[MeshInstance3D] = []
var _saved_mouse := Input.MOUSE_MODE_CAPTURED
var _saved_hud := true
var _saved_viewmodel := true
var _was_paused := false
var _refresh_t := 0.0
var _state: Array = []
var player_avatar: Node3D
var player_marker: Label
static var _avatar_materials: Dictionary = {}

func setup(system: Node) -> void:
	defences = system
	game = system.game
	player = game.player
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	overview = Camera3D.new()
	overview.name = "TowerPlannerOverview"
	overview.projection = Camera3D.PROJECTION_ORTHOGONAL
	overview.size = VIEW_SIZE
	overview.near = 0.5
	overview.far = 400.0
	overview.cull_mask = player.camera.cull_mask
	game.add_child(overview)
	_build_ui()
	player_marker = _label("▼  YOU", 18, GREEN)
	player_marker.autowrap_mode = TextServer.AUTOWRAP_OFF
	player_marker.custom_minimum_size = Vector2(110, 28)
	player_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_marker.add_theme_color_override("font_outline_color", Color.BLACK)
	player_marker.add_theme_constant_override("outline_size", 5)
	panel.add_child(player_marker)

static func _style(bg: Color, border := Color(0.2, 0.27, 0.25), pad := 14.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	return box

static func _label(text: String, size: int, color := PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

static func _button(text: String, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _style(Color(0.19, 0.25, 0.22) if accent else Color(0.08, 0.11, 0.10), GOLD if accent else Color(0.23, 0.3, 0.27), 10))
	button.add_theme_stylebox_override("hover", _style(Color(0.22, 0.28, 0.24), GOLD, 10))
	button.add_theme_stylebox_override("pressed", _style(Color(0.1, 0.22, 0.17), GREEN, 10))
	button.add_theme_stylebox_override("disabled", _style(Color(0.065, 0.08, 0.075), Color(0.15, 0.19, 0.17), 10))
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_disabled_color", MUTED)
	return button

func _build_ui() -> void:
	panel = Control.new()
	panel.name = "TowerPlanner"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.hide()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(INK, Color(GOLD, 0.35), 18))
	card.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	card.offset_left = 24
	card.offset_top = 24
	card.offset_bottom = -(BAR_HEIGHT + 24 + 10)
	card.custom_minimum_size.x = 380
	panel.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	column.add_child(_label("THE PLANES   /   DEFENSE" if Map.active_region == "planes" else "REMETSCHWIL SENNHOF   /   DEFENSE", 12, GOLD))
	title = _label("TOWER PLANNER", 34)
	title.add_theme_font_override("font", Style.DISPLAY)
	column.add_child(title)
	wallet = _label("", 17, GOLD)
	column.add_child(wallet)
	column.add_child(_rule())
	# the selected tower, large
	column.add_child(_label("SELECTED TOWER", 12, GOLD))
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _style(Color(0.06, 0.085, 0.08, 0.9), Color(0.25, 0.33, 0.3), 10))
	column.add_child(frame)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 4)
	frame.add_child(detail)
	selected_icon = TextureRect.new()
	selected_icon.custom_minimum_size = Vector2(322, 190)
	selected_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	selected_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	selected_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(selected_icon)
	selected_name = _label("", 24, PAPER)
	selected_name.add_theme_font_override("font", Style.DISPLAY)
	detail.add_child(selected_name)
	selected_meta = _label("", 14, GOLD)
	detail.add_child(selected_meta)
	selected_info = _label("", 14, PAPER)
	detail.add_child(selected_info)
	selected_tiers = _label("", 12, MUTED)
	detail.add_child(selected_tiers)
	selected_reason = _label("", 13, RED)
	selected_reason.hide()
	detail.add_child(selected_reason)
	if Map.active_region != "planes": column.add_child(_label("FOREST HUT ROOF", 12, GOLD))
	var roof_row := GridContainer.new()
	roof_row.columns = 3
	roof_row.add_theme_constant_override("h_separation", 6)
	roof_row.add_theme_constant_override("v_separation", 6)
	column.add_child(roof_row)
	roof_row.visible = Map.active_region != "planes"
	for i in 6:
		var button := _button("")
		button.custom_minimum_size.y = 36
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(place_roof.bind(i))
		roof_row.add_child(button)
		roof_buttons.append(button)
	status = _label("", 14, MUTED)
	column.add_child(status)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	column.add_child(_label("Click the map to build · drag a tower to move it · R / wheel turns · +/- zoom · 1-9, 0 pick a type", 12, MUTED))
	var back := _button("Back to the game  [T / Esc]")
	back.pressed.connect(close)
	column.add_child(back)
	# the build bar: one render tile per tower kind along the bottom edge
	bar = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _style(INK, Color(GOLD, 0.35), 8))
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 24
	bar.offset_right = -24
	bar.offset_top = -(BAR_HEIGHT + 24)
	bar.offset_bottom = -24
	panel.add_child(bar)
	bar_row = HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", TILE_GAP)
	bar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(bar_row)
	for kind in DefenceTower.TYPES:
		_build_tile(kind)
	hint = _label("", 18, GOLD)
	var hint_background := StyleBoxFlat.new()
	hint_background.bg_color = Color(0.025, 0.045, 0.06, 0.55)
	hint_background.border_color = Color(GOLD, 0.24)
	hint_background.set_border_width_all(1)
	hint_background.set_corner_radius_all(8)
	hint_background.content_margin_left = 20
	hint_background.content_margin_right = 20
	hint_background.content_margin_top = 10
	hint_background.content_margin_bottom = 10
	hint.add_theme_stylebox_override("normal", hint_background)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	hint.add_theme_constant_override("outline_size", 2)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 428
	hint.offset_right = -24
	hint.offset_bottom = bar.offset_top - 8
	hint.offset_top = hint.offset_bottom - 64
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(hint)
	get_viewport().size_changed.connect(_fit_tiles)
	_fit_tiles.call_deferred()

const TILE_HEIGHT := 138
const BAR_HEIGHT := TILE_HEIGHT + 16     # the bar's own padding (8 px each side)
const TILE_GAP := 6
# the strip along the top edge of a tile: guns gold, area weapons blue, support green
const CATEGORY_COLOURS := {"gun": GOLD, "area": Color(0.5, 0.76, 1.0), "support": GREEN}
const AREA_KINDS := ["flame", "mortar", "frost", "tesla", "rocket", "graviton"]

static func category(kind: String) -> String:
	if kind in DefenceTower.SUPPORT: return "support"
	if kind in AREA_KINDS: return "area"
	return "gun"

static func _rule() -> Control:
	var line := ColorRect.new()
	line.color = Color(GOLD, 0.35)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

# One tile: the kind's own render (assets/ui/items/tower_<kind>.png), its key number, its price, and a wave
# badge while it is locked. The button itself carries the frame; the children ignore the mouse.
func _build_tile(kind: String) -> void:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(112, TILE_HEIGHT)
	tile.focus_mode = Control.FOCUS_NONE
	tile.add_theme_stylebox_override("normal", _style(Color(0.08, 0.11, 0.10), Color(0.23, 0.3, 0.27), 4))
	tile.add_theme_stylebox_override("hover", _style(Color(0.16, 0.21, 0.19), GOLD, 4))
	tile.add_theme_stylebox_override("pressed", _style(Color(0.1, 0.22, 0.17), GREEN, 4))
	tile.add_theme_stylebox_override("disabled", _style(Color(0.05, 0.065, 0.06), Color(0.14, 0.18, 0.16), 4))
	tile.pressed.connect(select_kind.bind(kind))
	tile.mouse_entered.connect(func(): _hover_kind = kind)
	tile.mouse_exited.connect(func(): if _hover_kind == kind: _hover_kind = "")
	var strip := ColorRect.new()
	strip.color = CATEGORY_COLOURS[category(kind)]
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_left = 9
	strip.offset_right = -9
	strip.offset_top = 1
	strip.offset_bottom = 4
	tile.add_child(strip)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_top = 10
	stack.offset_bottom = -4
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(stack)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/ui/items/tower_%s.png" % kind) if ResourceLoader.exists("res://assets/ui/items/tower_%s.png" % kind) else load("res://assets/ui/items/tower.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)
	tile_icons[kind] = icon
	var name_label := _label(DefenceTower.SPECS[kind].name, 12, PAPER)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	name_label.add_theme_font_override("font", Style.MEDIUM)
	stack.add_child(name_label)
	var price := _label("", 13, GOLD)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.autowrap_mode = TextServer.AUTOWRAP_OFF
	stack.add_child(price)
	tile_prices[kind] = price
	var key := _label("", 12, GOLD)
	key.position = Vector2(7, 7)
	key.autowrap_mode = TextServer.AUTOWRAP_OFF
	key.add_theme_font_override("font", Style.MEDIUM)
	tile.add_child(key)
	tile_keys[kind] = key
	var badge := _label("", 11, Color(1.0, 0.74, 0.68))
	badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge.add_theme_font_override("font", Style.MEDIUM)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.36, 0.07, 0.05, 0.94)
	pill.set_corner_radius_all(6)
	pill.content_margin_left = 5
	pill.content_margin_right = 5
	pill.content_margin_top = 1
	pill.content_margin_bottom = 1
	badge.add_theme_stylebox_override("normal", pill)
	badge.hide()
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.position = Vector2(0, 6)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tile.add_child(badge)
	tile_badges[kind] = badge
	bar_row.add_child(tile)
	kind_buttons[kind] = tile

# The tiles share the bar's width: 112 px each on a 1600 px screen, never under 76 (1280 px).
func _fit_tiles() -> void:
	if not bar or not is_inside_tree(): return
	var width: float = get_viewport().get_visible_rect().size.x - 48 - 16
	var count := DefenceTower.TYPES.size()
	var tile_w := clampf((width - float(TILE_GAP) * (count - 1)) / count, 76.0, 118.0)
	for kind in kind_buttons:
		(kind_buttons[kind] as Button).custom_minimum_size = Vector2(tile_w, TILE_HEIGHT)
		(tile_badges[kind] as Label).position.x = tile_w - 7

func _build_roof_markers() -> void:
	if Map.active_region == "planes": return
	for i in 6:
		var marker := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.55
		ring.outer_radius = 0.8
		marker.mesh = ring
		marker.material_override = Barricade._marker_material(GOLD, 0.85)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.position = defences.roof_position(i) + Vector3.UP * 0.1
		marker.hide()
		game.add_child(marker)
		roof_markers.append(marker)

func open() -> void:
	if is_open or not game.started or game.over or not player.alive or not player.active or player.mounted_tower: return
	_was_paused = get_tree().paused
	_saved_mouse = Input.mouse_mode
	_saved_hud = game.hud.visible
	_saved_viewmodel = game.weapons.viewmodel.visible
	is_open = true
	defences.is_open = true
	selected_roof = -1
	dragging = null
	hover_tower = null
	ghost_yaw = player.rotation.y
	player.active = false
	get_tree().paused = not NetSession.enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.hud.hide()
	game.weapons.viewmodel.hide()
	# the roof view when the player is at the hut; anywhere else the map opens over the player, so towers
	# can be planned out on the meadow or at a gate too (PLANNER_REACH is measured from the player)
	var centre: Vector3 = game.hut.center if game.hut else player.global_position
	if Vector2(player.global_position.x - centre.x, player.global_position.z - centre.z).length() > HUT_VIEW_RANGE:
		centre = Map.ground_pos(player.global_position.x, player.global_position.z)
	centre = centre.lerp(player.global_position, 0.5)
	overview.size = maxf(VIEW_SIZE, centre.distance_to(player.global_position) * 2.8)
	overview.global_position = centre + Vector3(-7, 60, 0)
	overview.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	overview.make_current()
	if not player_avatar:
		player_avatar = preload("res://scripts/coop_avatar.gd").new()
		game.add_child(player_avatar)
		player_avatar.setup(player, "", 0)
		player_avatar.label.hide()
		player_avatar.process_mode = Node.PROCESS_MODE_DISABLED
		# The planner's survivor remains readable at night and under a hut roof.
		for mesh: MeshInstance3D in player_avatar.find_children("*", "MeshInstance3D", true, false):
			mesh.visibility_range_end = 0
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(surface) as BaseMaterial3D
				if not source: continue
				var key := source.resource_path if not source.resource_path.is_empty() else str(source.get_instance_id())
				if not _avatar_materials.has(key):
					var material := source.duplicate() as BaseMaterial3D
					material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					material.no_depth_test = true
					_avatar_materials[key] = material
				mesh.set_surface_override_material(surface, _avatar_materials[key])
		var ring := TorusMesh.new()
		ring.inner_radius = 0.72
		ring.outer_radius = 0.80
		ring.rings = 24
		ring.ring_segments = 6
		var marker_material := Barricade._marker_material(GREEN, 0.6)
		marker_material.no_depth_test = true
		DefenceTower.piece(player_avatar, ring, Vector3.UP * 0.1, marker_material)
	player_avatar.global_transform = player.global_transform
	player_avatar._process(0.0)
	player_avatar.show()
	_update_player_marker()
	if roof_markers.is_empty(): _build_roof_markers()
	for marker in roof_markers: marker.show()
	for crowns in get_tree().get_nodes_in_group("tree_crowns"): crowns.visible = false   # see the ground, not the canopy
	defences._build_preview()
	panel.show()
	_state = []
	_refresh()

func close() -> void:
	if not is_open: return
	is_open = false
	defences.is_open = false
	dragging = null
	panel.hide()
	if player_avatar: player_avatar.hide()
	for marker in roof_markers: marker.hide()
	for crowns in get_tree().get_nodes_in_group("tree_crowns"): crowns.visible = true
	if defences.ghost: defences.ghost.hide()
	if defences.range_marker: defences.range_marker.hide()
	player.camera.make_current()
	game.hud.visible = _saved_hud
	game.weapons.viewmodel.visible = _saved_viewmodel
	get_tree().paused = not NetSession.enabled and (_was_paused or game.over)
	player.active = player.alive and not game.over and not get_tree().paused
	Input.mouse_mode = _saved_mouse if player.active else Input.MOUSE_MODE_VISIBLE
	game.hud.set_prompt("")
	defences.input_grace = 0.2

func select_kind(kind: String) -> void:
	var reason: String = defences.build_requirement(player, kind)
	if not reason.is_empty():
		status.text = Lang.t(reason)
		status.add_theme_color_override("font_color", RED)
		return
	defences.selected_kind = kind
	defences._build_preview()
	status.text = Lang.t("%s selected. Click the map to place it, drag a standing tower to move it.", [DefenceTower.SPECS[kind].name])
	status.add_theme_color_override("font_color", GREEN)
	_state = []

# the roof slot a point snaps to (-1 = none): the six rings are the targets, not the roof tiles between them
func roof_slot_near(point: Vector3) -> int:
	if Map.active_region == "planes": return -1
	if not point.is_finite(): return -1
	var best := -1
	var best_d := ROOF_SNAP
	for i in 6:
		var slot: Vector3 = defences.roof_position(i)
		var d := Vector2(slot.x - point.x, slot.z - point.z).length()
		if d < best_d and absf(slot.y - point.y) < 4.0:
			best_d = d
			best = i
	return best

# the ground (or roof) point under a screen position, INF when the ray misses
func point_at(screen: Vector2) -> Vector3:
	var origin := overview.project_ray_origin(screen)
	var normal := overview.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + normal * 200.0, 1)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return Vector3.INF
	return hit.position

func tower_near(point: Vector3, radius := 2.2) -> DefenceTower:
	var best: DefenceTower = null
	var best_d := radius
	for tower: DefenceTower in defences.towers.values():
		if not is_instance_valid(tower): continue
		var d: float = Vector2(tower.global_position.x - point.x, tower.global_position.z - point.z).length()
		if d < best_d:
			best_d = d
			best = tower
	return best

# ---- actions (the mouse handlers and the tests call these)
func place_at(point: Vector3) -> String:
	if not point.is_finite(): return "Point the map at a building site."
	var kind: String = defences.selected_kind
	var target := point
	var slot: int = defences.roof_index(point)
	if slot < 0: slot = roof_slot_near(point)
	if slot >= 0: target = defences.roof_position(slot)
	else: target = Map.ground_pos(point.x, point.z)
	if NetSession.enabled:
		NetSession.command("tower_place", [target, ghost_yaw, kind, true])
		return ""
	var error: String = defences.purchase(player, target, ghost_yaw, kind, true)
	_state = []
	return error

func place_roof(slot: int) -> void:
	selected_roof = slot
	var tower: DefenceTower = defences.roof_tower(slot)
	if tower:
		status.text = Lang.t("Roof slot %d: %s · Tier %d · %d / %d HP", [slot + 1, tower.spec().name, tower.level, ceili(tower.hp), int(tower.max_hp())])
		status.add_theme_color_override("font_color", GOLD)
		return
	_report(place_at(defences.roof_position(slot)))

func move_tower(tower: DefenceTower, point: Vector3) -> String:
	if not is_instance_valid(tower) or not point.is_finite(): return "Tower not found."
	if NetSession.enabled:
		NetSession.command("tower_move", [tower.tower_id, Map.ground_pos(point.x, point.z)])
		return ""
	var error: String = defences.relocate(player, tower.tower_id, Map.ground_pos(point.x, point.z))
	_state = []
	return error

func rotate_hovered(steps: int) -> void:
	if hover_tower and not dragging:
		var yaw := wrapf(hover_tower.rotation.y + deg_to_rad(15.0) * steps, -PI, PI)
		if NetSession.enabled: NetSession.command("tower_rotate", [hover_tower.tower_id, yaw, true])
		else: _report(defences.rotate_tower(player, hover_tower.tower_id, yaw, true))
	else:
		ghost_yaw = wrapf(ghost_yaw + deg_to_rad(15.0) * steps, -PI, PI)

func _report(error: String) -> void:
	if error.is_empty():
		status.text = "Done."
		status.add_theme_color_override("font_color", GREEN)
		Sfx.play(self, "confirm", -8.0)
	else:
		status.text = Lang.t(error)
		status.add_theme_color_override("font_color", RED)

# ---- input
func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		hover_point = point_at(event.position)
		if dragging and hover_point.is_finite(): drag_moved = true
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				hover_point = point_at(event.position)
				var tower := tower_near(hover_point) if hover_point.is_finite() else null
				if tower and not tower.rooftop:
					dragging = tower
					drag_moved = false
				elif hover_point.is_finite():
					_report(place_at(hover_point))
			elif dragging:
				var target := point_at(event.position)
				if drag_moved and target.is_finite(): _report(move_tower(dragging, target))
				dragging = null
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			rotate_hovered(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			rotate_hovered(-1 if event.shift_pressed else 1)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE or event.physical_keycode == KEY_T:
			close()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			overview.size = clampf(overview.size * 0.8, VIEW_MIN, VIEW_MAX)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			overview.size = clampf(overview.size * 1.25, VIEW_MIN, VIEW_MAX)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode >= KEY_0 and event.physical_keycode <= KEY_9:
			var index: int = 9 if event.physical_keycode == KEY_0 else event.physical_keycode - KEY_1
			if index < DefenceTower.TYPES.size(): select_kind(DefenceTower.TYPES[index])
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_open: return
	_update_player_marker()
	if not player.alive or game.over:
		close()
		return
	_refresh_t += delta
	if _refresh_t >= 0.25:
		_refresh_t = 0.0
		_refresh()
	var ghost: Node3D = defences.ghost
	if not _hover_kind.is_empty() and not dragging:
		var hovered: Dictionary = DefenceTower.SPECS[_hover_kind]
		var reason: String = defences.build_requirement(player, _hover_kind)
		hint.text = Lang.t("%s · %d R · %d m · %s", [hovered.name, hovered.cost, hovered.range, Lang.t(hovered.info)]) if reason.is_empty() else Lang.t("%s · %d R · %s", [hovered.name, hovered.cost, Lang.t(reason)])
		if ghost: ghost.hide()
		if defences.range_marker: defences.range_marker.hide()
		return
	if not hover_point.is_finite():
		if ghost: ghost.hide()
		if defences.range_marker: defences.range_marker.hide()
		return
	hover_tower = dragging if dragging else tower_near(hover_point)
	var kind: String = defences.selected_kind
	var spec: Dictionary = DefenceTower.SPECS[kind]
	if dragging:
		var target := Map.ground_pos(hover_point.x, hover_point.z)
		var error: String = defences.placement_error(player, target, dragging.kind, true, dragging.tower_id)
		hover_valid = error.is_empty()
		if ghost:
			ghost.global_position = target
			ghost.rotation.y = dragging.rotation.y
			ghost.show()
			defences.ghost_material.albedo_color = Color(0.2, 0.95, 0.5, 0.28) if hover_valid else Color(1, 0.16, 0.08, 0.3)
		if defences.range_marker: defences.range_marker.display(target, dragging.attack_range(), dragging.rotation.y, false, not hover_valid)
		hint.text = Lang.t("Moving %s · release to drop it here", [dragging.spec().name]) if hover_valid else Lang.t("Moving %s · %s", [dragging.spec().name, Lang.t(error)])
		return
	if hover_tower:
		if ghost: ghost.hide()
		if defences.range_marker: defences.range_marker.display(hover_tower.global_position, hover_tower.attack_range(), hover_tower.rotation.y, false)
		hint.text = Lang.t("%s · Tier %d · %d / %d HP · drag to move · R / wheel to turn", [hover_tower.spec().name, hover_tower.level, ceili(hover_tower.hp), int(hover_tower.max_hp())])
		return
	var slot: int = defences.roof_index(hover_point)
	if slot < 0: slot = roof_slot_near(hover_point)
	var target: Vector3 = defences.roof_position(slot) if slot >= 0 else Map.ground_pos(hover_point.x, hover_point.z)
	var error: String = defences.placement_error(player, target, kind, true)
	hover_valid = error.is_empty()
	if ghost:
		ghost.global_position = target
		ghost.rotation.y = ghost_yaw
		ghost.show()
		defences.ghost_material.albedo_color = Color(0.2, 0.95, 0.5, 0.28) if hover_valid else Color(1, 0.16, 0.08, 0.3)
	if defences.range_marker: defences.range_marker.display(target, defences.preview_range(), ghost_yaw, false, not hover_valid)
	if slot >= 0 and hover_valid:
		hint.text = Lang.t("Roof slot %d · %s · %d R · click to build", [slot + 1, spec.name, spec.cost])
	else:
		hint.text = Lang.t("%s · %d R · click to build · R / wheel to turn · +/- zoom", [spec.name, spec.cost]) if hover_valid else Lang.t("%s · %s", [spec.name, Lang.t(error)])

func _update_player_marker() -> void:
	if player_avatar: player_avatar.global_transform = player.global_transform
	var point := overview.unproject_position(player.global_position + Vector3.UP * 2.2)
	var screen := get_viewport().get_visible_rect().size
	player_marker.position = Vector2(clampf(point.x - 55, 405, screen.x - 120), clampf(point.y - 45, 12, screen.y - (BAR_HEIGHT + 24 + 36)))
	player_marker.text = "▼  YOU"

func _refresh() -> void:
	var state := [game.waves.completed, player.score, defences.towers.size(), defences.selected_kind, Lang.current]
	if state == _state: return
	_state = state
	wallet.text = Lang.t("%d  REM DOLLARS  ·  %d / %d towers", [player.score, defences.towers.size(), DefenceTower.LIMIT])
	for kind in kind_buttons:
		var spec: Dictionary = DefenceTower.SPECS[kind]
		var tile: Button = kind_buttons[kind]
		var reason: String = defences.build_requirement(player, kind)
		var locked := not reason.is_empty()
		var index: int = DefenceTower.TYPES.find(kind)
		tile.disabled = locked
		tile.tooltip_text = Lang.t("%s · %d R · %d m\n%s", [spec.name, spec.cost, spec.range, Lang.t(spec.info)])
		var frame_style := _style(Color(0.14, 0.2, 0.17) if kind == defences.selected_kind else Color(0.08, 0.11, 0.10), GOLD if kind == defences.selected_kind else Color(0.23, 0.3, 0.27), 4)
		if kind == defences.selected_kind: frame_style.set_border_width_all(2)
		tile.add_theme_stylebox_override("normal", frame_style)
		(tile_icons[kind] as TextureRect).modulate = Color(0.45, 0.45, 0.45) if locked else Color.WHITE
		(tile_prices[kind] as Label).text = Lang.t("%d R", [spec.cost])
		(tile_prices[kind] as Label).add_theme_color_override("font_color", MUTED if locked else GOLD)
		(tile_keys[kind] as Label).text = str(index + 1) if index < 9 else ("0" if index == 9 else "")
		(tile_keys[kind] as Label).add_theme_color_override("font_color", MUTED if locked else GOLD)
		var required: int = defences.unlock_waves(kind)
		(tile_badges[kind] as Label).text = (Lang.t("W%d", [required]) if game.waves.completed < required else "") if locked else ""
		(tile_badges[kind] as Label).visible = not (tile_badges[kind] as Label).text.is_empty()
	var selected: String = defences.selected_kind
	var chosen: Dictionary = DefenceTower.SPECS[selected]
	var icon_path := "res://assets/ui/items/tower_%s.png" % selected
	selected_icon.texture = load(icon_path) if ResourceLoader.exists(icon_path) else load("res://assets/ui/items/tower.png")
	selected_name.text = Lang.t(chosen.name)
	var available := "From the start" if defences.unlock_waves(selected) == 0 else Lang.t("After wave %d", [defences.unlock_waves(selected)])
	selected_meta.text = Lang.t("%d R · %d m · %s", [chosen.cost, chosen.range, Lang.t(available)])
	selected_info.text = Lang.t(chosen.info)
	selected_tiers.text = Lang.t("Tier 2 after wave %d · Tier 3 after wave %d", [defences.unlock_waves(selected, 2), defences.unlock_waves(selected, 3)])
	var blocked: String = defences.build_requirement(player, selected)
	selected_reason.visible = not blocked.is_empty()
	selected_reason.text = Lang.t(blocked)
	for i in roof_buttons.size():
		var tower: DefenceTower = defences.roof_tower(i)
		roof_buttons[i].text = Lang.t("%d · %s", [i + 1, tower.spec().name if tower else "free"])
		roof_buttons[i].add_theme_color_override("font_color", GREEN if tower else PAPER)

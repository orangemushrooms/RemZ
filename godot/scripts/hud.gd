# In-game HUD plus the start / pause / game-over menu (tabs: Briefing, Difficulty, Controls, Settings, High scores,
# Achievements, Summary). main.gd sets `game` so the menu can read statistics, achievements and settings.
# Text is English; labels translate themselves (docs/LOCALIZATION.md).
class_name Hud
extends CanvasLayer

signal start_pressed
signal main_menu_pressed

const GOLD := Color(1.0, 0.7, 0.28)
const PAPER := Color(0.93, 0.92, 0.88)
const MUTED := Color(0.62, 0.64, 0.6)
const INK := Color(0.043, 0.06, 0.08)

var game: Node
var hp_bar: ProgressBar
var score_label: Label
var money_delta: Label
var _money_delta_t := 0.0
var _money_pulse := 0.0
var _money_shown := 0
var ammo_label: Label
var weapon_label: Label
var wave_label: Label
var wave_info: Label
var wave_bar: ProgressBar
var hut_label: Label
var hut_alarm: PanelContainer
var hut_alarm_text: Label
var clock_label: Label
var clock_phase: Label
var clock_rate: Label
var clock_progress: ProgressBar
var msg_label: Label
var prompt_label: Label
var streak_label: Label
var damage_rect: ColorRect
var vignette: TextureRect
var hit_dir: Control
var overlay: Control
var overlay_title: Label
var overlay_text: Label
var overlay_button: Button
var overlay_status: Label
var overlay_content: VBoxContainer
var overlay_logo: TextureRect
var overlay_mode := "start"
var loading_bar: ProgressBar
var fps_label: Label
var playtime_label: Label
var team_label: Label
var reload_bar: ProgressBar
var reload_label: Label
# Second gauge under the reload bar: barrel heat, energy cells, minigun spin-up. Weapons that feed
# from a plain magazine never show it.
var charge_bar: ProgressBar
var charge_label: Label
var _charge_colour := Color(0, 0, 0, 0)
var minimap: Minimap
var settings_box: VBoxContainer
var difficulty_button: Button
var hit_marks: Array = []
var crosshair_parts: Array[Control] = []
var _msg_timer := 0.0
var _damage_t := 0.0
var _hit_t := 0.0
var _loading := false
var _stats_time := 0.0
var _stats_frames := 0
var _message_tween: Tween
var _streak_t := 0.0
var _hit_dirs: Array = []           # [angle, time left]
var trip_rect: ColorRect
var _trip_material: ShaderMaterial
var _trip_t := 0.0
var _trip_len := 0.0
const TRIP_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
void fragment() {
	float w = strength;
	vec2 uv = SCREEN_UV;
	uv += vec2(sin(uv.y * 9.0 + TIME * 1.7), cos(uv.x * 7.0 + TIME * 1.3)) * 0.014 * w;
	float lod = 2.6 * w;
	vec2 shift = vec2(0.012 * w, 0.0);
	vec3 col = vec3(textureLod(screen, uv + shift, lod).r, textureLod(screen, uv, lod).g, textureLod(screen, uv - shift, lod).b);
	col = mix(col, col.gbr, 0.3 * w * (0.5 + 0.5 * sin(TIME * 0.8)));
	col = mix(col, vec3(dot(col, vec3(0.3, 0.5, 0.2))) * vec3(0.9, 0.7, 1.2), 0.25 * w);
	COLOR = vec4(col, 1.0);
}
"""
var attack_dir: Control
# 26 Sep 2026: weather line in the clock, the down panel, the radio log and the world markers of the callouts
var weather_label: Label
var downed_panel: PanelContainer
var downed_text: Label
var bleed_bar: ProgressBar
var hold_bar: ProgressBar
var radio_box: VBoxContainer
var _radio_lines: Array = []        # [Label, time left]
var marked_label: Label
var pings_layer: Control
var _attack_arrows: Array = []      # [angle, name, strength 0..1] refreshed every frame from the gates under attack
var _attack_pulse := 0.0
var _popups: Array = []             # [Label, time left]
var _popup_pool: Array[Label] = []
var _pending_popups: Array = []
var _pending_score := -1
var _pending_streak := Vector2i(-1, 0)
var _low_hp := false
var _pulse := 0.0
var _tabs := {}                     # id -> Control (content)
var _tab_buttons := {}              # id -> Button
var _tab_title: Label
var _briefing_box: VBoxContainer
var _pause_stats: Label
var _diff_cards: Array = []
var _diff_defs: Array = []
var _diff_locked := false
var _records_box: VBoxContainer
var _achievements_box: VBoxContainer
var _summary_box: VBoxContainer
var _home_button: Button
var _quit_button: Button
var _card: PanelContainer
var _root: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var root := Control.new()
	_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	fps_label = _label("", 13)
	fps_label.position = Vector2(16, 16)
	root.add_child(fps_label)
	playtime_label = _label(Lang.t("Play time %s", ["00:00"]), 14)
	playtime_label.position = Vector2(16, 38)
	playtime_label.add_theme_constant_override("outline_size", 4)
	playtime_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(playtime_label)
	team_label = _label("", 15)
	team_label.position = Vector2(16, 66)
	team_label.add_theme_constant_override("outline_size", 4)
	team_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(team_label)

	# low-health vignette (radial gradient, red rim) and the flat damage flash on top
	vignette = TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.5, 0.0, 0.0, 0.0))
	grad.add_point(0.62, Color(0.5, 0.0, 0.0, 0.0))
	grad.set_color(grad.get_point_count() - 1, Color(0.45, 0.0, 0.0, 0.85))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(0.5, 1.0)
	gtex.width = 256
	gtex.height = 256
	vignette.texture = gtex
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	root.add_child(vignette)
	damage_rect = ColorRect.new()
	damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_rect.color = Color(0.7, 0.07, 0.1, 0.0)
	damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_rect)
	# the strange mushroom: a swimming, colour-shifted blur over the whole screen (see hallucinate)
	trip_rect = ColorRect.new()
	trip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trip_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var trip_shader := Shader.new()
	trip_shader.code = TRIP_SHADER
	_trip_material = ShaderMaterial.new()
	_trip_material.shader = trip_shader
	trip_rect.material = _trip_material
	trip_rect.hide()
	root.add_child(trip_rect)
	# hit direction arcs around the crosshair
	hit_dir = Control.new()
	hit_dir.set_anchors_preset(Control.PRESET_CENTER)
	hit_dir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_dir.draw.connect(_draw_hit_dirs)
	root.add_child(hit_dir)
	# red arrows around the crosshair towards every gate (and the hut) under attack
	attack_dir = Control.new()
	attack_dir.set_anchors_preset(Control.PRESET_CENTER)
	attack_dir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attack_dir.draw.connect(_draw_attack_dirs)
	root.add_child(attack_dir)

	# One transparent, ballistic reticle; menus can hide it through the common list.
	var reticle := preload("res://scripts/aim_reticle.gd").new()
	root.add_child(reticle)
	crosshair_parts.append(reticle)
	# hitmarker: four short diagonal ticks around the crosshair
	for k in 4:
		var m := ColorRect.new()
		m.color = Color(1, 1, 1, 0.0)
		m.custom_minimum_size = Vector2(10, 2)
		m.set_anchors_preset(Control.PRESET_CENTER)
		m.pivot_offset = Vector2(5, 1)
		m.position = Vector2(-5, -1) + Vector2(cos(k * PI / 2.0 + PI / 4.0), sin(k * PI / 2.0 + PI / 4.0)) * 14.0
		m.rotation = k * PI / 2.0 + PI / 4.0
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(m)
		hit_marks.append(m)
	# kill streak under the crosshair
	streak_label = _label("", 20)
	streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	streak_label.set_anchors_preset(Control.PRESET_CENTER)
	streak_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	streak_label.position.y = 34
	streak_label.add_theme_color_override("font_color", GOLD)
	streak_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	streak_label.add_theme_constant_override("shadow_offset_y", 1)
	streak_label.modulate.a = 0.0
	root.add_child(streak_label)

	# stats bottom-left
	var stats := _panel(root, Control.PRESET_BOTTOM_LEFT, Vector2(16, -16))
	# money: as prominent as the ammunition counter, with a delta popup on every change
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 10)
	money_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(money_row)
	money_row.add_child(preload("res://scripts/currency.gd").icon(44.0, GOLD))
	score_label = _label("0 R", 26, GOLD)
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	score_label.add_theme_constant_override("shadow_offset_y", 1)
	score_label.pivot_offset = Vector2(0, 16)
	money_row.add_child(score_label)
	money_delta = _label("", 16, GOLD)
	money_delta.modulate.a = 0.0
	money_delta.size_flags_vertical = Control.SIZE_SHRINK_END
	money_row.add_child(money_delta)
	var money_caption := _label("REM DOLLARS · Build, buy, train", 10, MUTED)
	stats.add_child(money_caption)
	stats.add_child(_spacer(4))
	stats.add_child(_label("Health", 14))
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(180, 12)
	hp_bar.show_percentage = false
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.add_theme_stylebox_override("fill", _flat(Color(0.7, 0.07, 0.1), 4))
	hp_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.12), 4))
	stats.add_child(hp_bar)

	# ammunition beside the minimap, lifted clear of the quick bar's band along the bottom edge
	var ammo := _panel(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-332, -100))
	ammo_label = _label("12 / 72", 22)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo.add_child(ammo_label)
	weapon_label = _label("Pistol", 12)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.modulate.a = 0.7
	ammo.add_child(weapon_label)
	reload_label = _label("", 12)
	ammo.add_child(reload_label)
	reload_bar = ProgressBar.new()
	reload_bar.custom_minimum_size = Vector2(180, 5)
	reload_bar.max_value = 1.0
	reload_bar.show_percentage = false
	reload_bar.visible = false
	ammo.add_child(reload_bar)
	charge_label = _label("", 12)
	charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	charge_label.visible = false
	ammo.add_child(charge_label)
	charge_bar = ProgressBar.new()
	charge_bar.custom_minimum_size = Vector2(180, 5)
	charge_bar.max_value = 1.0
	charge_bar.show_percentage = false
	charge_bar.visible = false
	charge_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.12), 3))
	ammo.add_child(charge_bar)
	minimap = Minimap.new()
	root.add_child(minimap)

	# wave top-center with a remaining-enemies bar
	var wave := _panel(root, Control.PRESET_CENTER_TOP, Vector2(0, 16))
	wave_label = _label(Lang.t("Wave %d", [1]), 18)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.add_theme_color_override("font_color", GOLD)
	wave.add_child(wave_label)
	wave_info = _label("Ready", 14)
	wave_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave.add_child(wave_info)
	wave_bar = ProgressBar.new()
	wave_bar.custom_minimum_size = Vector2(150, 4)
	wave_bar.max_value = 1.0
	wave_bar.value = 0.0
	wave_bar.show_percentage = false
	wave_bar.add_theme_stylebox_override("fill", _flat(Color(0.85, 0.3, 0.22), 2))
	wave_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.1), 2))
	wave_bar.visible = false
	wave.add_child(wave_bar)
	hut_label = _label("", 12)
	hut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hut_label.add_theme_constant_override("outline_size", 3)
	hut_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	wave.add_child(hut_label)
	hut_alarm = PanelContainer.new()
	root.add_child(hut_alarm)
	hut_alarm.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hut_alarm.offset_left = -390
	hut_alarm.offset_right = 390
	hut_alarm.offset_top = 142
	hut_alarm.offset_bottom = 238
	hut_alarm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var alarm_style := StyleBoxFlat.new()
	alarm_style.bg_color = Color(0.12, 0.005, 0.005, 0.94)
	alarm_style.border_color = Color(1, 0.08, 0.06)
	alarm_style.set_border_width_all(3)
	alarm_style.set_corner_radius_all(8)
	alarm_style.set_content_margin_all(14)
	hut_alarm.add_theme_stylebox_override("panel", alarm_style)
	hut_alarm_text = _label("ALARM! THE FOREST HUT IS UNDER ATTACK!", 32, Color(1, 0.12, 0.08))
	hut_alarm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hut_alarm_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hut_alarm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hut_alarm_text.add_theme_constant_override("outline_size", 5)
	hut_alarm_text.add_theme_color_override("font_outline_color", Color(0.05, 0, 0))
	hut_alarm_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hut_alarm.add_child(hut_alarm_text)
	hut_alarm.hide()

	# world clock
	var clock := _panel(root, Control.PRESET_TOP_RIGHT, Vector2(-16, 16))
	clock.custom_minimum_size.x = 156
	clock.add_child(_label("LOCAL TIME", 10))
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation", 16)
	clock.add_child(clock_row)
	clock_label = _label("06:00", 30)
	clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_row.add_child(clock_label)
	clock_phase = _label("Morning", 13)
	clock_phase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clock_row.add_child(clock_phase)
	clock_progress = ProgressBar.new()
	clock_progress.custom_minimum_size.y = 3
	clock_progress.max_value = 24.0 * 3600.0
	clock_progress.show_percentage = false
	clock_progress.add_theme_stylebox_override("background", _flat(Color(1.0, 1.0, 1.0, 0.1), 0))
	clock_progress.add_theme_stylebox_override("fill", _flat(Color(0.94, 0.67, 0.34), 0))
	clock.add_child(clock_progress)
	clock_rate = _label(Lang.t("%d× · game time", [96]), 11)
	clock_rate.modulate.a = 0.6
	clock.add_child(clock_rate)
	weather_label = _label("", 12, Color(0.75, 0.85, 1.0))
	weather_label.visible = false
	clock.add_child(weather_label)

	# the radio: the last callouts of the team, under the team list top left
	radio_box = VBoxContainer.new()
	radio_box.position = Vector2(16, 540)
	radio_box.add_theme_constant_override("separation", 2)
	radio_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(radio_box)
	# markers of the callouts in the world
	pings_layer = Control.new()
	pings_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	pings_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pings_layer.draw.connect(_draw_pings)
	root.add_child(pings_layer)
	# a screamer's mark
	marked_label = _label("SPOTTED - the horde knows where you are!", 18, Color(1.0, 0.35, 0.6))
	marked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marked_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	marked_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	marked_label.position.y = 118
	marked_label.add_theme_constant_override("outline_size", 4)
	marked_label.add_theme_color_override("font_outline_color", Color(0.1, 0, 0.05))
	marked_label.visible = false
	root.add_child(marked_label)
	# down: bleed-out and the E hold, above the prompt
	downed_panel = PanelContainer.new()
	root.add_child(downed_panel)
	downed_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	downed_panel.offset_left = -260
	downed_panel.offset_right = 260
	downed_panel.offset_top = -286
	downed_panel.offset_bottom = -196
	downed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var down_style := StyleBoxFlat.new()
	down_style.bg_color = Color(0.14, 0.01, 0.01, 0.92)
	down_style.border_color = Color(1, 0.2, 0.15)
	down_style.set_border_width_all(2)
	down_style.set_corner_radius_all(8)
	down_style.set_content_margin_all(10)
	downed_panel.add_theme_stylebox_override("panel", down_style)
	var down_box := VBoxContainer.new()
	down_box.add_theme_constant_override("separation", 4)
	downed_panel.add_child(down_box)
	downed_text = _label("", 16, Color(1, 0.35, 0.3))
	downed_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	down_box.add_child(downed_text)
	bleed_bar = ProgressBar.new()
	bleed_bar.custom_minimum_size = Vector2(480, 6)
	bleed_bar.max_value = 1.0
	bleed_bar.show_percentage = false
	bleed_bar.add_theme_stylebox_override("fill", _flat(Color(0.9, 0.12, 0.1), 3))
	bleed_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.12), 3))
	down_box.add_child(bleed_bar)
	hold_bar = ProgressBar.new()
	hold_bar.custom_minimum_size = Vector2(480, 6)
	hold_bar.max_value = 1.0
	hold_bar.show_percentage = false
	hold_bar.add_theme_stylebox_override("fill", _flat(GOLD, 3))
	hold_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.12), 3))
	down_box.add_child(hold_bar)
	downed_panel.hide()

	# message center, prompt lower center
	msg_label = _label("", 24)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.set_anchors_preset(Control.PRESET_CENTER)
	msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_label.position.y = -80
	msg_label.modulate.a = 0.0
	msg_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	msg_label.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(msg_label)
	prompt_label = _label("", 15)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_label.position.y = -170
	prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(prompt_label)

	_build_overlay()

# ---------------------------------------------------------------- menu
func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.03, 0.9)
	overlay.add_child(dim)
	_card = PanelContainer.new()
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var cs := StyleBoxFlat.new()
	cs.bg_color = INK
	cs.border_color = Color(1, 1, 1, 0.15)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(10)
	cs.content_margin_left = 30; cs.content_margin_right = 30; cs.content_margin_top = 24; cs.content_margin_bottom = 24
	_card.add_theme_stylebox_override("panel", cs)
	overlay.add_child(_card)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	_card.add_child(columns)

	# left column: logo, title, buttons
	var v := VBoxContainer.new()
	overlay_content = v
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(340, 600)
	columns.add_child(v)
	overlay_logo = TextureRect.new()
	var logo_path := "res://assets/ui/konm_games_logo.png"
	if ResourceLoader.exists(logo_path):
		overlay_logo.texture = load(logo_path)
	overlay_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	overlay_logo.custom_minimum_size = Vector2(0, 130)
	overlay_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(overlay_logo)
	overlay_title = _label("REMETSCHWIL FOREST HUT", 30)
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_title.add_theme_color_override("font_color", GOLD)
	v.add_child(overlay_title)
	var sub := _label("NIGHT ON THE HEITERSBERG", 12)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.6
	v.add_child(sub)
	v.add_child(_spacer(6))
	overlay_button = _menu_button("Start game", true)
	overlay_button.pressed.connect(func(): Sfx.play(self, "click", -6.0); start_pressed.emit())
	v.add_child(overlay_button)
	overlay_status = _label("", 12)
	overlay_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_status.modulate.a = 0.6
	v.add_child(overlay_status)
	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size = Vector2(0, 6)
	loading_bar.max_value = 1.0
	loading_bar.show_percentage = false
	loading_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.08), 3))
	loading_bar.add_theme_stylebox_override("fill", _flat(GOLD, 3))
	loading_bar.visible = false
	v.add_child(loading_bar)
	v.add_child(_spacer(4))
	for tab in [["briefing", "Briefing"], ["multiplayer", "Multiplayer"], ["difficulty", "Difficulty"], ["controls", "Controls"], ["settings", "Settings"], ["records", "High scores"], ["achievements", "Achievements"]]:
		var b := _menu_button(tab[1], false)
		var id: String = tab[0]
		b.pressed.connect(func(): Sfx.play(self, "click", -8.0); show_tab(id))
		v.add_child(b)
		_tab_buttons[id] = b
	difficulty_button = _tab_buttons["difficulty"]
	v.add_child(_spacer(4))
	_menu_button_row(v)

	# right column: tab content
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(700, 600)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0.03, 0.042, 0.055)
	rs.border_color = Color(1, 1, 1, 0.08)
	rs.set_border_width_all(1)
	rs.set_corner_radius_all(8)
	rs.content_margin_left = 22; rs.content_margin_right = 22; rs.content_margin_top = 16; rs.content_margin_bottom = 16
	right.add_theme_stylebox_override("panel", rs)
	columns.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	_tab_title = _label("BRIEFING", 13)
	_tab_title.add_theme_color_override("font_color", GOLD)
	rv.add_child(_tab_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(scroll)
	var host := VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(host)
	for id in ["briefing", "multiplayer", "difficulty", "controls", "settings", "records", "achievements", "summary"]:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 10)
		box.visible = false
		host.add_child(box)
		_tabs[id] = box
	_build_briefing(_tabs["briefing"])
	_build_controls(_tabs["controls"])
	var coop_menu = preload("res://scripts/coop_menu.gd").new()
	_tabs["multiplayer"].add_child(coop_menu)
	coop_menu.setup(self)
	settings_box = _tabs["settings"]
	settings_box.add_child(_label("Changes apply immediately and are saved.", 12, MUTED))
	_records_box = _tabs["records"]
	_achievements_box = _tabs["achievements"]
	_summary_box = _tabs["summary"]
	show_tab("briefing")

func _menu_button_row(v: VBoxContainer) -> void:
	_home_button = _menu_button("Back to main menu", false)
	_home_button.pressed.connect(func(): Sfx.play(self, "click", -6.0); main_menu_pressed.emit())
	_home_button.visible = false
	v.add_child(_home_button)
	_quit_button = _menu_button("Quit game", false)
	_quit_button.pressed.connect(func():
		if game and "settings" in game and game.settings:
			game.settings.save()
		get_tree().quit())
	v.add_child(_quit_button)

func _build_briefing(box: VBoxContainer) -> void:
	_briefing_box = box
	overlay_text = _label("", 15)
	overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(overlay_text)
	_pause_stats = _label("", 14, MUTED)
	_pause_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_stats.visible = false
	box.add_child(_pause_stats)
	box.add_child(_heading("HOW TO SURVIVE"))
	for tip in [
		"Four approaches lead to the hut: the Hut Path (north-east), the Meadow Gate (east), the Village Path (south) and the North Forest Path. E builds or repairs right at the line; building costs 50 Rem Dollars. Mechanic advises you on defense.",
		"Headshots deal 2.2 times the damage. Kills in quick succession build a streak worth up to 100% bonus points.",
		"Fallen zombies drop ammo, grenades and bandage packs. Just walk through them.",
		"Vendor sells weapons at the campfire. Complete quests and survive waves to unlock his stock. A secret trader waits in the forest.",
		"Porcini heal, fly agarics briefly double your damage. Eat both from the inventory (I).",
		"T opens the tower preview. R/mouse wheel rotates, E confirms. At a tower: E mounts it, R re-aims it, F repairs it. Upgrades at Mechanic. Q shows your quests. Hold Tab for the leaderboard.",
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var dot := _label("▸", 14, GOLD)
		row.add_child(dot)
		var l := _label(tip, 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		box.add_child(row)

func _build_controls(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for pair in [["WASD", "Move"], ["Mouse", "Look around"], ["Shift", "Sprint"], ["Hold Ctrl", "Crouch / aim more precisely"], ["Space", "Jump"],
			["Left click", "Shoot / strike"], ["Right click", "Aim (ADS)"], ["R", "Reload / align tower"], ["1–9 / 0", "Quick bar: slots 1–10"], ["Mouse wheel", "Switch weapon"],
			["G", "Throw grenade"], ["E", "NPC / barricade / mount tower / repair hut"], ["V", "Defense planning with Mechanic"], ["T", "Build turret · at the hut also on the roof · E confirms"], ["E · drone station", "Fly a drone (hut, upper floor) · RMB rocket · R self-destruct · Esc recall"], ["I", "Inventory"], ["B", "Drop 100 Rem Dollars"],
			["Hold Tab", "Leaderboard of this round"], ["Q", "Quest tracker on/off"], ["M", "Minimap large / small"], ["F", "Flashlight"], ["H", "Melee / rifle butt"], ["Enter", "Next wave now"],
			["X / middle mouse", "Callout: ping what you look at (gate, hut, enemy, spot)"], ["Hold E (down)", "Get back up once per wave · teammates revive with E"], ["Esc", "Pause / menu"], ["F11", "Fullscreen"]]:
		var k := _label(pair[0], 14, GOLD)
		k.custom_minimum_size.x = 110
		grid.add_child(k)
		var d := _label(pair[1], 14)
		d.custom_minimum_size.x = 190
		grid.add_child(d)
	box.add_child(_spacer(6))
	box.add_child(_heading("TIPS"))
	var l := _label("Aiming cuts recoil by a quarter and spread by 60%. Sustained fire makes the barrel climb: short bursts hit better. The minimap shows enemies as red dots and barrier lines red (open), green (built) or yellow (damaged).", 13, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)

# difficulty cards; names/descriptions come from GameSettings.DIFFICULTIES
func set_difficulties(defs: Array, current: int, on_change: Callable) -> void:
	var box: VBoxContainer = _tabs["difficulty"]
	for c in box.get_children():
		c.queue_free()
	_diff_cards.clear()
	_diff_defs = defs
	var intro := _label("The difficulty applies to the whole round and can only be changed before the start.", 13, MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	for i in defs.size():
		var d: Dictionary = defs[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 74)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = Lang.t("%s\n%s", [d["name"], d["desc"]])
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", PAPER)
		b.add_theme_color_override("font_disabled_color", MUTED)
		b.pressed.connect(func():
			if _diff_locked:
				return
			Sfx.play(self, "confirm", -8.0)
			on_change.call(i)
			_mark_difficulty(i))
		box.add_child(b)
		_diff_cards.append(b)
	_mark_difficulty(current)

func _mark_difficulty(i: int) -> void:
	for k in _diff_cards.size():
		var b: Button = _diff_cards[k]
		var on := k == i
		var st := _flat(Color(0.16, 0.14, 0.1) if on else Color(0.07, 0.09, 0.11), 6)
		st.border_color = GOLD if on else Color(1, 1, 1, 0.12)
		st.set_border_width_all(2 if on else 1)
		st.set_content_margin_all(12)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_stylebox_override("pressed", st)
		b.add_theme_stylebox_override("focus", st)
		b.add_theme_stylebox_override("disabled", st)
		if on and difficulty_button:
			difficulty_button.text = Lang.t("Difficulty: %s", [_diff_defs[k]["name"]])

func set_difficulty_locked(locked: bool) -> void:
	_diff_locked = locked
	for b: Button in _diff_cards:
		b.disabled = locked

func show_tab(id: String) -> void:
	if not _tabs.has(id):
		return
	if game and game.music and not game.started and not "--no-music" in game._flags:
		if id == "multiplayer": game.music.play("lobby")
		elif game.music.current == "lobby": game.music.play("title")
	for k in _tabs:
		_tabs[k].visible = k == id
	var titles := { "briefing": "BRIEFING", "multiplayer": "MULTIPLAYER", "difficulty": "DIFFICULTY", "controls": "CONTROLS", "settings": "SETTINGS", "records": "HIGH SCORES", "achievements": "ACHIEVEMENTS", "summary": "ROUND SUMMARY" }
	_tab_title.text = titles.get(id, id.to_upper())
	for k in _tab_buttons:
		var b: Button = _tab_buttons[k]
		b.add_theme_stylebox_override("normal", _button_style(k == id, false))
	if id == "records":
		_fill_records()
	elif id == "achievements":
		_fill_achievements()
	elif id == "briefing" and overlay_mode == "pause":
		_fill_pause_stats()

func _fill_records(highlight_rank: int = 0) -> void:
	for c in _records_box.get_children():
		c.queue_free()
	var table: Array = []
	if game and "stats" in game and game.stats:
		table = game.stats.table
	if table.is_empty():
		_records_box.add_child(_label("No round played yet. Your ten best rounds end up here.", 14, MUTED))
		return
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 5)
	_records_box.add_child(grid)
	for h in ["#", "Rem Dollars", "Wave", "Kills", "Heads", "Hit %", "Time", "Mode · Date"]:
		grid.add_child(_label(h, 12, GOLD))
	for i in table.size():
		var r: Dictionary = table[i]
		var col := GOLD if i + 1 == highlight_rank else (PAPER if i < 3 else MUTED)
		for cell in ["%d" % (i + 1), "%d" % int(r.get("score", 0)), "%d" % int(r.get("wave", 0)), "%d" % int(r.get("kills", 0)), "%d" % int(r.get("headshots", 0)),
				"%d %%" % int(round(float(r.get("accuracy", 0.0)) * 100.0)), RunStats.time_text(float(r.get("seconds", 0))), Lang.t("%s · %s", [str(r.get("difficulty", "")), str(r.get("date", ""))])]:
			grid.add_child(_label(cell, 13, col))

func _fill_achievements() -> void:
	for c in _achievements_box.get_children():
		c.queue_free()
	if not game or not ("achievements" in game) or game.achievements == null:
		_achievements_box.add_child(_label("No achievements available.", 14, MUTED))
		return
	var a = game.achievements
	var info := _label(Lang.t("%s unlocked. Achievements stay saved; progress and rewards count per round. In multiplayer you reach the goals together as a team.", [a.progress_text()]), 13, MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_achievements_box.add_child(info)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	_achievements_box.add_child(grid)
	for d in Achievements.DEFS:
		var done: bool = a.unlocked.has(d["id"])
		grid.add_child(_label("★" if done else "○", 15, GOLD if done else MUTED))
		grid.add_child(_label(d["title"], 14, PAPER if done else MUTED))
		var progress := mini(int(a.counters.get(d["counter"], 0)), int(d["target"]))
		var t := _label(Lang.t("%s · Round: %d/%d", [d["text"], progress, d["target"]]), 13, MUTED)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(t)

func _fill_pause_stats() -> void:
	if not game or not ("stats" in game) or game.stats == null:
		_pause_stats.visible = false
		return
	var s = game.stats
	_pause_stats.visible = true
	_pause_stats.text = Lang.t("So far: wave %d · %d Rem Dollars · %d kills (%d headshots) · hits %d%% · best streak %d · %s", [
		game.waves.completed, game.player.score, s.kills, s.headshots, int(round(s.accuracy() * 100.0)), s.best_streak, RunStats.time_text(s.seconds)])

# game over: run summary and the updated high-score table
func show_run_summary(s: RunStats, score: int, wave: int, rank: int, difficulty_name: String) -> void:
	for c in _summary_box.get_children():
		c.queue_free()
	var head := _label(Lang.t("Reached wave %d · %d Rem Dollars · %s", [wave, score, difficulty_name]), 20)
	_summary_box.add_child(head)
	if rank > 0:
		var r := _label(Lang.t("Rank %d in the high scores  ·  NEW RECORD" if rank == 1 else "Rank %d in the high scores", [rank]), 15, GOLD)
		_summary_box.add_child(r)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 8)
	_summary_box.add_child(grid)
	for pair in [["Kills", "%d" % s.kills], ["Headshots", "%d" % s.headshots], ["Accuracy", "%d %%" % int(round(s.accuracy() * 100.0))], ["Shots", "%d" % s.shots],
			["Best streak", "%d" % s.best_streak], ["Grenades", "%d" % s.grenades_thrown], ["Barricades built", "%d" % s.barricades_built], ["Play time", RunStats.time_text(s.seconds)]]:
		grid.add_child(_label(pair[0], 13, MUTED))
		grid.add_child(_label(pair[1], 16))
	_summary_box.add_child(_spacer(6))
	_summary_box.add_child(_heading("HIGH SCORES"))
	var holder := VBoxContainer.new()
	_summary_box.add_child(holder)
	var saved := _records_box
	_records_box = holder
	_fill_records(rank)
	_records_box = saved
	show_tab("summary")

func show_overlay(title: String, text: String, button: String, status: String = "", mode: String = "") -> void:
	if mode.is_empty():
		mode = "over" if title == "YOU DIED" else ("pause" if title == "PAUSED" else "start")
	overlay_mode = mode
	overlay_title.text = title
	overlay_text.text = text
	overlay_button.text = button
	overlay_button.disabled = _loading
	overlay_status.text = status
	overlay_logo.visible = mode == "start"
	_home_button.visible = mode != "start"
	_quit_button.visible = true
	set_difficulty_locked(mode != "start")
	_tab_buttons["difficulty"].visible = true
	overlay.visible = true
	_root.visible = mode != "start"   # the in-game HUD stays hidden behind the start menu
	if mode == "over":
		if _tabs["summary"].get_child_count() > 0:
			show_tab("summary")
		else:
			show_tab("records")
	else:
		show_tab("briefing")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_overlay() -> void:
	overlay.visible = false
	_root.visible = true

func set_loading(on: bool) -> void:
	_loading = on
	loading_bar.visible = on
	if on:
		loading_bar.value = 0.0

# ---------------------------------------------------------------- widgets
func _panel(parent: Control, preset: int, offset: Vector2) -> VBoxContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(preset)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	p.set_anchors_and_offsets_preset(preset)
	p.position += offset
	match preset:
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT:
			p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	match preset:
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_TOP_RIGHT:
			p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP:
			p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v

func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _heading(text: String) -> Label:
	return _label(text, 12, GOLD)

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

static func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb

func _button_style(active: bool, primary: bool) -> StyleBoxFlat:
	var st := _flat(Color(0.2, 0.16, 0.09) if primary else (Color(0.13, 0.15, 0.17) if active else Color(0.075, 0.095, 0.115)), 6)
	st.border_color = GOLD if (primary or active) else Color(1, 1, 1, 0.12)
	st.set_border_width_all(1)
	st.content_margin_left = 14; st.content_margin_right = 14; st.content_margin_top = 8; st.content_margin_bottom = 8
	return st

func _menu_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44 if primary else 36)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if not primary else HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 17 if primary else 14)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.add_theme_stylebox_override("normal", _button_style(false, primary))
	var hv := _button_style(true, primary)
	hv.bg_color = Color(0.22, 0.2, 0.14) if primary else Color(0.15, 0.17, 0.19)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", hv)
	var dis := _button_style(false, primary)
	dis.bg_color = Color(0.06, 0.07, 0.08)
	b.add_theme_stylebox_override("disabled", dis)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func(): if not b.disabled: Sfx.play(self, "hover", -16.0))
	return b

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if _pending_score >= 0:
		_show_score(_pending_score)
		_pending_score = -1
	if _pending_streak.x >= 0:
		_show_streak(_pending_streak.x, _pending_streak.y)
		_pending_streak.x = -1
	for popup: Array in _pending_popups: _show_score_popup(popup[0], popup[1])
	_pending_popups.clear()
	if _loading:
		loading_bar.value = fmod(loading_bar.value + delta * 0.45, 1.0)
	_stats_time += delta
	_stats_frames += 1
	if _stats_time >= 0.5:
		# The existing round clock pauses in solo menus and is host-synchronised
		# in multiplayer. A new scene starts with a fresh RunStats instance.
		playtime_label.visible = game != null and game.started
		var elapsed := maxi(0, floori(game.stats.seconds)) if game and game.stats else 0
		var time := "%02d:%02d" % [elapsed / 60, elapsed % 60] if elapsed < 3600 else "%d:%02d:%02d" % [elapsed / 3600, (elapsed / 60) % 60, elapsed % 60]
		playtime_label.text = Lang.t("Play time %s", [time])
		team_label.visible = NetSession.enabled and NetSession.phase == "running"
		if team_label.visible and NetSession.world:
			var teammates: Array[String] = []
			for id in NetSession.roster:
				var p: Player = NetSession.world.actor(id)
				if p: teammates.append(Lang.t("%s%s  ·  %s", [Lang.raw(NetSession.roster[id]), Lang.t(" (you)") if id == NetSession.local_id() else "", Lang.t("%d HP", [ceili(p.hp)]) if p.alive else Lang.t("down")]))
			team_label.text = "\n".join(teammates)
		fps_label.text = "%d FPS · %.1f ms" % [roundi(_stats_frames / _stats_time), _stats_time * 1000.0 / _stats_frames]
		_stats_time = 0.0
		_stats_frames = 0
	if get_tree().paused:
		return
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_message_tween = create_tween()
			_message_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
			_message_tween.tween_property(msg_label, "modulate:a", 0.0, 0.3)
	if _damage_t > 0.0:
		_damage_t -= delta
	damage_rect.color.a = clampf(_damage_t * 3.0, 0.0, 0.45)
	# low health: slow pulse of the red rim, faster the lower the health
	if _low_hp:
		var frac := clampf(hp_bar.value / maxf(hp_bar.max_value, 1.0), 0.0, 1.0)
		_pulse += delta * lerpf(6.0, 2.5, frac / 0.35)
		vignette.modulate.a = lerpf(0.75, 0.25, frac / 0.35) * (0.7 + 0.3 * sin(_pulse))
	else:
		vignette.modulate.a = maxf(0.0, vignette.modulate.a - delta * 2.0)
	if _hit_t > 0.0:
		_hit_t -= delta
		if _hit_t <= 0.0:
			for m in hit_marks:
				m.color.a = 0.0
	if _streak_t > 0.0:
		_streak_t -= delta
		streak_label.modulate.a = clampf(_streak_t * 2.0, 0.0, 1.0)
	if _money_delta_t > 0.0:
		_money_delta_t -= delta
		money_delta.modulate.a = clampf(_money_delta_t * 1.5, 0.0, 1.0)
	if _money_pulse > 0.0:
		_money_pulse = maxf(_money_pulse - delta * 4.0, 0.0)
		score_label.scale = Vector2.ONE * (1.0 + 0.18 * _money_pulse)
	if not _popups.is_empty():
		var alive: Array = []
		for p in _popups:
			p[1] -= delta
			var l: Label = p[0]
			if p[1] <= 0.0:
				l.hide()
				_popup_pool.append(l)
				continue
			l.position.y -= delta * 28.0
			l.modulate.a = clampf(p[1] * 2.0, 0.0, 1.0)
			alive.append(p)
		_popups = alive
	_update_attack_dirs(delta)
	_update_trip(delta)
	if not _radio_lines.is_empty():
		var keep: Array = []
		for entry in _radio_lines:
			entry[1] -= delta
			var label: Label = entry[0]
			if entry[1] <= 0.0:
				label.queue_free()
				continue
			label.modulate.a = clampf(entry[1] / 1.5, 0.0, 1.0)
			keep.append(entry)
		_radio_lines = keep
	if pings_layer and game and "pings" in game and game.pings and (not game.pings.active.is_empty() or _pings_drawn):
		_pings_drawn = not game.pings.active.is_empty()
		pings_layer.queue_redraw()
	if marked_label and marked_label.visible:
		marked_label.modulate.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.012)
	if not _hit_dirs.is_empty():
		var keep: Array = []
		for h in _hit_dirs:
			h[1] -= delta
			if h[1] > 0.0:
				keep.append(h)
		_hit_dirs = keep
		hit_dir.queue_redraw()

# The strange mushroom: the view swims and shifts colour for the given seconds, fading in and out.
func hallucinate(seconds: float) -> void:
	_trip_len = maxf(seconds, 1.0)
	_trip_t = _trip_len
	trip_rect.show()
	message("The forest begins to swim. Wait it out.", 3.5)

func _update_trip(delta: float) -> void:
	if _trip_t <= 0.0: return
	_trip_t = maxf(0.0, _trip_t - delta)
	var t := _trip_t / _trip_len
	var strength := clampf(minf((1.0 - t) * 6.0, t * 4.0), 0.0, 1.0)
	_trip_material.set_shader_parameter("strength", strength)
	if _trip_t <= 0.0: trip_rect.hide()

func tripping() -> bool:
	return _trip_t > 0.0

# the Clear Head drink: whatever is left of a trip fades within a second and a half
func sober() -> void:
	if _trip_t > 0.0:
		_trip_len = maxf(_trip_len, 1.0)
		_trip_t = minf(_trip_t, minf(1.5, _trip_len * 0.25))

# Gates under attack (barricade.under_attack(), the hut's under_attack()) become pulsing red arrows around
# the crosshair with the gate's name, using the same angle convention as the hit arcs (0 = ahead, +PI/2 right).
func _update_attack_dirs(delta: float) -> void:
	_attack_pulse += delta * 5.0
	var arrows: Array = []
	if game and "player" in game and game.player and game.player.camera and visible:
		var cam: Camera3D = game.player.camera
		var forward := -cam.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := Vector3(-forward.z, 0.0, forward.x)
		var targets: Array = []
		if "barricades" in game:
			for b in game.barricades:
				if b is Barricade and b.under_attack(): targets.append([b.center, b.slot["name"]])
		if "sandbags" in game:
			for line in game.sandbags:
				if line.under_attack(): targets.append([line.center, "Sandbags"])
		if "hut" in game and game.hut and game.hut.has_method("under_attack") and game.hut.under_attack():
			targets.append([game.hut.attack_point(cam.global_position), "Forest hut"])
		for t in targets:
			var d: Vector3 = (t[0] as Vector3) - cam.global_position
			d.y = 0.0
			if d.length() < 0.5: continue
			var angle := atan2(d.dot(right), d.dot(forward))
			arrows.append([angle, t[1], clampf(1.0 - d.length() / 160.0, 0.35, 1.0)])
	var changed := arrows.size() != _attack_arrows.size()
	_attack_arrows = arrows
	if attack_dir and (changed or not arrows.is_empty()):
		attack_dir.queue_redraw()

func _draw_attack_dirs() -> void:
	var pulse := 0.75 + 0.25 * sin(_attack_pulse)
	for a in _attack_arrows:
		var angle: float = a[0]
		var col := Color(1.0, 0.16, 0.1, 0.9 * pulse)
		var tip := Vector2(sin(angle), -cos(angle))
		var side := tip.orthogonal()
		attack_dir.draw_colored_polygon(PackedVector2Array([tip * 176.0, tip * 148.0 + side * 14.0, tip * 148.0 - side * 14.0]), col)
		attack_dir.draw_colored_polygon(PackedVector2Array([tip * 152.0 + side * 6.0, tip * 152.0 - side * 6.0, tip * 136.0 - side * 6.0, tip * 136.0 + side * 6.0]), col)
		var font := ThemeDB.fallback_font
		var text := Lang.text(a[1])
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
		var at := tip * 198.0 - Vector2(size.x * 0.5, -5.0)
		attack_dir.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8 * pulse))
		attack_dir.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

func _draw_hit_dirs() -> void:
	for h in _hit_dirs:
		var a: float = h[0]
		var k: float = clampf(h[1] / 0.9, 0.0, 1.0)
		var col := Color(0.95, 0.15, 0.1, 0.85 * k)
		var pts := PackedVector2Array()
		var steps := 12
		for i in steps + 1:
			var t := a - 0.42 + 0.84 * float(i) / steps
			pts.append(Vector2(sin(t), -cos(t)) * 58.0)
		hit_dir.draw_polyline(pts, col, 5.0, true)
		var tip := Vector2(sin(a), -cos(a))
		hit_dir.draw_colored_polygon(PackedVector2Array([tip * 72.0, tip * 60.0 + tip.orthogonal() * 8.0, tip * 60.0 - tip.orthogonal() * 8.0]), col)

# ---------------------------------------------------------------- 26 Sep 2026: weather, down, radio, markers
var _pings_drawn := false

func set_weather(text: String) -> void:
	if not weather_label: return
	weather_label.visible = not text.is_empty()
	if weather_label.text != text: weather_label.text = text

func set_marked(active: bool) -> void:
	if marked_label and marked_label.visible != active: marked_label.visible = active

# active: the player is down. seconds_left of bleed-out, hold 0..1 of the E hold, can_self: a self revive
# is left, teammates: someone else could come.
func set_downed(active: bool, seconds_left: float, hold: float, can_self: bool, teammates: bool, watching := "", dead := false) -> void:
	if not downed_panel: return
	if downed_panel.visible != active: downed_panel.visible = active
	if not active: return
	var line: String = Lang.t("YOU BLED OUT") if dead else Lang.t("YOU ARE DOWN  ·  %d s", [ceili(maxf(seconds_left, 0.0))])
	if can_self and not dead: line += "  ·  " + Lang.t("hold E to get back up")
	elif teammates: line += "  ·  " + Lang.t("a teammate can revive you with E")
	if not watching.is_empty(): line += "\n" + Lang.t("Watching %s  ·  LMB / RMB: next teammate", [Lang.raw(watching)])
	if downed_text.text != line: downed_text.text = line
	bleed_bar.visible = not dead
	bleed_bar.value = clampf(seconds_left / Player.DOWN_SECONDS, 0.0, 1.0)
	hold_bar.visible = can_self and not dead
	hold_bar.value = clampf(hold, 0.0, 1.0)

func radio_line(text: String, colour: Color = Color.WHITE) -> void:
	if not radio_box: return
	var label := _label(text, 14, colour.lightened(0.25))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	radio_box.add_child(label)
	_radio_lines.append([label, 9.0])
	while _radio_lines.size() > 4:
		var old: Array = _radio_lines.pop_front()
		(old[0] as Label).queue_free()

# every live callout: a diamond with its text where it points, clamped to the screen edge when off screen
func _draw_pings() -> void:
	if not game or not "pings" in game or not game.pings or not game.player or not game.player.camera: return
	var camera: Camera3D = game.player.camera
	if not camera.current: return
	var font := ThemeDB.fallback_font
	var size := pings_layer.size
	for entry in game.pings.active:
		var world: Vector3 = entry.position + Vector3.UP * 1.2
		var behind := camera.is_position_behind(world)
		var point := camera.unproject_position(world)
		if behind: point = Vector2(size.x - point.x, size.y - point.y)
		var clamped := point.clamp(Vector2(40, 60), size - Vector2(40, 120))
		var edge := behind or clamped != point
		var alpha := clampf(float(entry.time) / 1.5, 0.0, 1.0)
		var colour: Color = entry.colour
		colour.a = alpha
		var d := 9.0
		pings_layer.draw_colored_polygon(PackedVector2Array([clamped + Vector2(0, -d - 2), clamped + Vector2(d + 2, 0), clamped + Vector2(0, d + 2), clamped + Vector2(-d - 2, 0)]), Color(0, 0, 0, 0.75 * alpha))
		pings_layer.draw_colored_polygon(PackedVector2Array([clamped + Vector2(0, -d), clamped + Vector2(d, 0), clamped + Vector2(0, d), clamped + Vector2(-d, 0)]), colour)
		if edge: continue
		var text := Lang.text(str(entry.text))
		var distance := roundi(camera.global_position.distance_to(entry.position))
		var caption := "%s  %d m" % [text, distance]
		var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var at := clamped + Vector2(-width * 0.5, -d - 8)
		pings_layer.draw_string_outline(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85 * alpha))
		pings_layer.draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, colour)

# ---------------------------------------------------------------- API used by the systems
func set_health(v: float) -> void:
	hp_bar.value = v
	var frac := v / maxf(hp_bar.max_value, 1.0)
	_low_hp = frac < 0.35 and v > 0.0

func set_score(v: int) -> void:
	_pending_score = v

func _show_score(v: int) -> void:
	var diff := v - _money_shown
	_money_shown = v
	score_label.text = "%s R" % _thousands(v)
	if diff != 0:
		money_delta.text = ("+%s R" if diff > 0 else "−%s R") % _thousands(absi(diff))
		money_delta.add_theme_color_override("font_color", GOLD if diff > 0 else Color(1.0, 0.45, 0.35))
		money_delta.modulate.a = 1.0
		_money_delta_t = 1.6
		_money_pulse = 1.0

static func _thousands(v: int) -> String:
	var t := str(absi(v))
	var out := ""
	while t.length() > 3:
		out = " " + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if v < 0 else "") + t + out

func set_ammo(now: int, reserve: int, weapon: String) -> void:
	ammo_label.text = "%d / %d" % [now, reserve]
	weapon_label.text = weapon

func set_wave(n: int, info: String) -> void:
	wave_label.text = Lang.t("Wave %d", [n])
	wave_info.text = info

# Waldhütte health under the wave bar: green when intact, orange when damaged, pulsing red under attack
func set_hut(hp: float, max_hp: float, under_attack: bool) -> void:
	if not hut_label: return
	hut_alarm.visible = under_attack and hp > 0 and game != null and game.started and not game.over
	if hut_alarm.visible:
		hut_alarm.modulate.a = 0.85 + 0.15 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))
	hut_label.text = Lang.t("HUT %d / %d", [ceili(hp), int(max_hp)])
	var ratio := clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	var color := Color(0.75, 0.9, 0.7) if ratio > 0.6 else (Color(1.0, 0.65, 0.3) if ratio > 0.25 else Color(1.0, 0.35, 0.25))
	if under_attack:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		color = Color(1.0, 0.15 + 0.35 * pulse, 0.1)
	hut_label.add_theme_color_override("font_color", color)

func set_wave_progress(remaining: int, total: int) -> void:
	wave_bar.visible = total > 0 and remaining > 0
	wave_bar.value = float(remaining) / maxf(total, 1)

func message(text: String, seconds: float = 2.5) -> void:
	if _message_tween and _message_tween.is_valid():
		_message_tween.kill()
	msg_label.text = text
	msg_label.modulate.a = 1.0
	_msg_timer = seconds

func set_prompt(text: String) -> void:
	prompt_label.text = text

func hitmarker(head: bool) -> void:
	_hit_t = 0.12
	for m in hit_marks:
		m.color = Color(1.0, 0.25, 0.2, 1.0) if head else Color(1, 1, 1, 1)

# floating "+N" beside the crosshair that drifts up and fades
func score_popup(points: int, head: bool) -> void:
	_pending_popups.append([points, head])
	if _pending_popups.size() > 6: _pending_popups.pop_front()

func _show_score_popup(points: int, head: bool) -> void:
	var l: Label
	if not _popup_pool.is_empty(): l = _popup_pool.pop_back()
	elif _popups.size() >= 6: l = _popups.pop_front()[0]
	else:
		l = _label("", 15, GOLD)
		_root.add_child(l)
	l.text = Lang.t("+%d R  HEADSHOT", [points]) if head else "+%d R" % points
	l.add_theme_font_size_override("font_size", 17 if head else 15)
	l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if head else GOLD)
	l.modulate.a = 1.0
	l.show()
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(30 + randf_range(-6.0, 6.0), -8 + randf_range(-4.0, 4.0))
	_popups.append([l, 1.1])

func streak(n: int, bonus_percent: int) -> void:
	_pending_streak = Vector2i(n, bonus_percent)

func _show_streak(n: int, bonus_percent: int) -> void:
	streak_label.text = Lang.t("%d× STREAK  +%d%%", [n, bonus_percent]) if bonus_percent > 0 else Lang.t("%d× STREAK", [n])
	streak_label.add_theme_font_size_override("font_size", mini(20 + n, 30))
	_streak_t = 1.6

# angle: direction of the attacker relative to the view (0 = ahead, +PI/2 = right); NAN = unknown
func damage_flash(angle: float = NAN) -> void:
	_damage_t = 0.25
	if not is_nan(angle):
		_hit_dirs.append([angle, 0.9])
		hit_dir.queue_redraw()

func set_reload(remaining: float, duration: float) -> void:
	reload_bar.visible = remaining > 0.0
	reload_label.text = "Reloading ..." if remaining > 0.0 else ""
	if remaining > 0.0:
		reload_bar.value = 1.0 - remaining / maxf(0.01, duration)

# The weapon's own gauge: text plus a 0..1 bar in the weapon's colour. An empty text hides it.
func set_charge(text: String, value: float, colour: Color = Color(1.0, 0.7, 0.28)) -> void:
	if not charge_bar: return
	var shown := not text.is_empty()
	charge_label.visible = shown
	charge_bar.visible = shown
	if not shown: return
	charge_label.text = text
	charge_label.modulate = colour
	charge_bar.value = clampf(value, 0.0, 1.0)
	# The colour changes on a weapon switch or when heat turns red, not sixty times a second.
	if colour != _charge_colour:
		_charge_colour = colour
		charge_bar.add_theme_stylebox_override("fill", _flat(colour, 3))

func set_world_time(seconds: float, phase: String, speed: float) -> void:
	clock_label.text = DayNightCycle.clock_text(seconds)
	clock_phase.text = phase
	clock_phase.modulate = Color(0.61, 0.75, 1.0) if phase == "Night" else Color(1.0, 0.76, 0.43)
	clock_progress.value = seconds
	clock_rate.text = Lang.t("%d× · game time", [roundi(speed)])

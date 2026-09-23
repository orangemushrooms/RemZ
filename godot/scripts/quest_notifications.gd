extends Control

# One reusable card; at most one queued message per quest. Counters are observed
# by Progression's existing 4 Hz refresh, never by the per-frame animation.
const WIDTH := 372.0
const GREEN := Color(0.48, 0.88, 0.61)
const GOLD := Color(1.0, 0.81, 0.43)
var _seen := {}
var _rewarded := {}
var _peer := -1
var _queue: Array[Dictionary] = []
var _current := {}
var _elapsed := 0.0
var _card: PanelContainer
var _style: StyleBoxFlat
var _heading: Label
var _title: Label
var _detail: Label
var _symbol: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(WIDTH, 104)
	_card.size.x = WIDTH
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.035, 0.055, 0.043, 0.95)
	_style.set_corner_radius_all(6)
	_style.set_border_width_all(1)
	_style.border_width_left = 3
	_style.set_content_margin_all(15)
	_style.shadow_color = Color(0, 0, 0, 0.25)
	_style.shadow_size = 5
	_card.add_theme_stylebox_override("panel", _style)
	add_child(_card)
	_card.minimum_size_changed.connect(_fit_card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	_card.add_child(row)
	_symbol = _label(27)
	_symbol.text = "✓"
	row.add_child(_symbol)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	row.add_child(column)
	_heading = _label(12)
	_title = _label(19)
	_detail = _label(14)
	_detail.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	for label: Label in [_heading, _title, _detail]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	_card.hide()

func _fit_card() -> void:
	# Wrapped labels first report a tall minimum before the container assigns
	# their width. Shrink again after that layout pass instead of retaining it.
	_card.size = Vector2(WIDTH, _card.get_combined_minimum_size().y)

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label

func reset() -> void:
	_stop_sound()
	_seen.clear()
	_rewarded.clear()
	_queue.clear()
	_current.clear()
	_card.hide()

func observe(progression: Node, peer: int, silent := false) -> void:
	if (_peer != -1 and _peer != peer) or silent:
		reset()
	_peer = peer
	var data: Dictionary = progression.data(peer)
	for id: String in data.accepted:
		if not data.accepted[id] or not Progression.QUESTS.has(id): continue
		if data.claimed.get(id, false):
			if silent: _rewarded[id] = true
			else: rewarded(id)
			continue
		if _rewarded.has(id): continue # A reliable reward may precede its snapshot.
		var known: Dictionary = _seen.get(id, {"goals": {}, "ready": false})
		var achieved: Dictionary = progression.completed_milestones(id, peer)
		var fresh: Array[String] = []
		for goal: String in achieved:
			if not known.goals.has(goal): fresh.append(achieved[goal])
			known.goals[goal] = true
		var ready: bool = progression.complete(id, peer)
		if not silent:
			if ready and not known.ready:
				_enqueue({"id": id, "kind": "ready", "goals": []})
			elif not known.ready and not fresh.is_empty():
				_enqueue({"id": id, "kind": "progress", "goals": fresh})
		known.ready = known.ready or ready
		_seen[id] = known

func rewarded(id: String) -> void:
	if not Progression.QUESTS.has(id) or _rewarded.has(id): return
	_rewarded[id] = true
	_enqueue({"id": id, "kind": "complete", "goals": []})

func _enqueue(message: Dictionary) -> void:
	# Upgrade an outstanding progress message when the whole quest is fulfilled.
	# This also prevents a quick turn-in from leaving an obsolete reminder behind.
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i].id != message.id: continue
		if message.kind == "progress":
			for goal: String in _queue[i].goals:
				if goal not in message.goals: message.goals.push_front(goal)
		_queue.remove_at(i)
	if _current.get("id", "") == message.id:
		if message.kind == "progress" and _current.kind == "progress":
			for goal: String in _current.goals:
				if goal not in message.goals: message.goals.push_front(goal)
		_current.clear()
		_card.hide()
		_queue.push_front(message)
	elif message.kind == "complete":
		_queue.push_front(message)
	else:
		_queue.append(message)
	_next()

func _next() -> void:
	if not is_visible_in_tree() or not _current.is_empty() or _queue.is_empty(): return
	_current = _queue.pop_front()
	_elapsed = 0.0
	var quest: Dictionary = Progression.QUESTS[_current.id]
	var progress: bool = _current.kind == "progress"
	var color := GREEN if progress else GOLD
	_heading.text = "MILESTONE REACHED" if progress else ("QUEST COMPLETED" if _current.kind == "complete" else "QUEST FULFILLED")
	_title.text = quest.name
	if progress:
		_detail.text = " · ".join(_current.goals)
	elif _current.kind == "complete":
		_detail.text = Lang.t("+%d Rem Dollars · reward received", [int(quest.reward)])
	else:
		_detail.text = Lang.t("All goals reached!\nTurn in to %s · %d R", [Progression.NPCS[quest.npc].name, quest.reward])
	_style.border_color = color
	_heading.add_theme_color_override("font_color", color)
	_symbol.add_theme_color_override("font_color", color)
	_card.size.y = 0
	_card.modulate.a = 0
	_card.show()
	var sound: String = "quest_progress" if progress else ("quest_complete" if _current.kind == "complete" else "quest_ready")
	_stop_sound()
	Sfx.play(self, sound, Sfx.EVENTS[sound])

func _stop_sound() -> void:
	# Replacing a milestone or immediately handing in a quest must not layer
	# several notification chimes over one another.
	for child in get_children():
		if child is AudioStreamPlayer: child.stop()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_next()
	if _current.is_empty(): return
	_elapsed += delta
	var duration := 3.4 if _current.kind == "progress" else 4.6
	var alpha := minf(clampf(_elapsed / 0.2, 0, 1), clampf((duration - _elapsed) / 0.35, 0, 1))
	_card.modulate.a = alpha
	_card.position = Vector2(size.x - WIDTH - 22 + (1.0 - alpha) * 14, 164)
	if _elapsed >= duration:
		_current.clear()
		_card.hide()
		_next()

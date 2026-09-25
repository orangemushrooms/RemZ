extends Hud

# Server-side feedback adapter: remote players do not create UI or viewports.
var peer_id := 1

func _ready() -> void:
	hp_bar = ProgressBar.new()
	add_child(hp_bar)
	hide()
	set_process(false)

func set_health(_v: float) -> void: pass
func set_score(_v: int) -> void: pass
func set_ammo(_now: int, _reserve: int, _weapon: String) -> void: pass
func set_reload(_remaining: float, _duration: float) -> void: pass
func set_charge(_text: String, _value: float, _colour: Color = Color.WHITE) -> void: pass
func message(text: String, seconds: float = 2.5) -> void:
	NetSession.feedback(peer_id, "message", [text, seconds])
func hitmarker(head: bool) -> void:
	NetSession.feedback(peer_id, "hit", [head])
func damage_flash(angle: float = NAN) -> void:
	NetSession.feedback(peer_id, "hurt", [angle])
func score_popup(points: int, head: bool) -> void:
	NetSession.feedback(peer_id, "score", [points, head])
func streak(n: int, bonus_percent: int) -> void:
	NetSession.feedback(peer_id, "streak", [n, bonus_percent])
func set_downed(_active: bool, _seconds_left: float, _hold: float, _can_self: bool, _teammates: bool) -> void: pass
func radio_line(_text: String, _colour: Color = Color.WHITE) -> void: pass
func set_weather(_text: String) -> void: pass
func set_marked(_active: bool) -> void: pass

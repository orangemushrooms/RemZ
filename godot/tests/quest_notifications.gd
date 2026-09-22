extends SceneTree

const Notifications := preload("res://scripts/quest_notifications.gd")
var checks := 0
var failures := 0

class Actor extends Node:
	var peer_id := 1
class WaveState extends Node:
	var completed := 1
class DefenceState extends Node:
	var towers := {}
class GameState extends Node3D:
	var player: Node
	var waves: Node
	var defences: Node
	var barricades: Array[Barricade] = []
	var progression: Progression

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	if "--world-only-quest-notifications" in OS.get_cmdline_user_args():
		await render_world()
		print("QUEST_NOTIFICATIONS_RENDER_DONE checks=%d failures=%d" % [checks, failures])
		quit(0 if failures == 0 else 1)
		return
	var game := GameState.new()
	root.add_child(game)
	game.player = Actor.new()
	game.waves = WaveState.new()
	game.defences = DefenceState.new()
	for node: Node in [game.player, game.waves, game.defences]: game.add_child(node)
	var shop := Progression.new()
	shop.game = game
	game.progression = shop
	game.add_child(shop)
	shop.set_process(false)
	shop.cache_node = Node3D.new()
	game.add_child(shop.cache_node)
	var popup := Notifications.new()
	shop.notifications = popup
	shop.add_child(popup)
	popup.set_process(false)
	var d := shop.data(1)
	d.claimed.arrival = true
	shop.team.built = 1
	shop.refresh_notifications()
	check(popup._current.is_empty(), "Unaccepted quests stay silent")
	d.accepted.watch = true
	d.accepted_wave.watch = 1
	shop.refresh_notifications()
	check(popup._current.get("kind") == "progress" and popup._detail.text.contains("Turm bauen"), "A completed subgoal names the quest and objective")
	check(popup._title.text == Progression.QUESTS.watch.name and Sfx._voices.has("quest_progress"), "Subgoal popup has its own sound")
	popup._process(1.0)
	var elapsed := popup._elapsed
	for i in 100: shop.refresh_notifications()
	check(popup._elapsed == elapsed and popup._queue.is_empty(), "Repeated refreshes never restart or duplicate milestones")
	shop.team.kills = 800
	shop.team.built = 2
	shop.refresh_notifications()
	check(popup._elapsed == elapsed, "Further counter increments are silent after the target")
	shop.team.turned = 1
	shop.refresh_notifications()
	check(popup._detail.text.contains("Turm ausrichten") and popup._detail.text.contains("Turm bauen"), "Rapid subgoals combine into one readable popup")
	var wall := Barricade.new()
	wall.level = 1
	game.barricades.append(wall)
	shop.refresh_notifications()
	check(popup._current.kind == "progress" and not shop.complete("watch"), "Completing build goals still waits for the required wave")
	game.waves.completed = 2
	shop.refresh_notifications()
	check(popup._current.kind == "ready" and popup._detail.text.contains("Mechanic") and not d.claimed.get("watch", false), "All goals show a turn-in reminder without claiming the reward")
	check(Sfx._voices.has("quest_ready") and popup._queue.is_empty(), "The final subgoal produces one completion sound and popup")
	wall.level = 0
	shop.refresh_notifications()
	wall.level = 1
	shop.refresh_notifications()
	check(popup._queue.is_empty(), "Rebuilding a lost objective does not repeat its milestone")
	paused = true
	popup.rewarded("watch")
	check(popup._current.kind == "complete" and popup._detail.text.contains("110 Rem Dollars"), "Turn-in replaces the pending reminder with the reward")
	check(Sfx._voices.quest_complete.back().playing and Sfx._voices.quest_complete.back().process_mode == Node.PROCESS_MODE_ALWAYS, "Reward audio plays in a paused shop")
	check(not Sfx._voices.quest_ready.back().playing, "A quick turn-in replaces the previous chime without overlapping it")
	var before: Array = Sfx._voices.quest_complete.duplicate()
	popup.rewarded("watch")
	check(popup._queue.is_empty() and before == Sfx._voices.quest_complete, "Duplicate reward feedback is silent")
	popup._process(0.5)
	check(popup._card.modulate.a == 1.0, "Popup animates while the shop pauses gameplay")
	paused = false
	d.claimed.watch = true
	shop.refresh_notifications()
	check(popup._queue.is_empty(), "A later reward snapshot does not duplicate the reliable popup")
	var snapshot := shop.snapshot()
	shop.apply_snapshot(snapshot, true)
	shop.refresh_notifications()
	check(popup._current.is_empty() and popup._queue.is_empty(), "Joining or resynchronizing never replays completed quests")
	d = shop.data(1)
	d.accepted.line = true
	d.accepted_wave.line = 2
	shop.team.kills = 29
	shop.refresh_notifications()
	check(popup._current.kind == "progress" and not popup._detail.text.contains("Zombies"), "Only reached thresholds count as subgoals")
	shop.team.kills = 30
	shop.refresh_notifications()
	check(popup._detail.text.contains("Zombies 30/30"), "Crossing a kill threshold produces a milestone")
	game.waves.completed = 3
	shop.refresh_notifications()
	check(popup._current.kind == "ready", "Required waves after accepting are included in full completion")
	shop.apply_snapshot(shop.snapshot())
	shop.refresh_notifications()
	check(popup._queue.is_empty(), "Repeated network snapshots remain silent")
	popup.hide()
	popup._process(10.0)
	check(popup._current.kind == "ready", "Menus suspend popup lifetime so it is not missed")
	popup.show()
	popup._process(10.0)
	check(popup._current.is_empty() and not popup._card.visible, "Notifications fade out and release the card")
	# The recipient's quest state is separate from the shared team counters.
	var other := shop.data(2)
	other.accepted.watch = true
	other.accepted_wave.watch = 1
	other.claimed.arrival = true
	popup.observe(shop, 2, true)
	check(popup._current.is_empty(), "An existing teammate's ready quests form a silent baseline")
	popup.observe(shop, 1, true)
	NetSession.game = game
	NetSession.enabled = true
	NetSession.feedback(2, "quest_complete", ["line"])
	check(popup._current.is_empty(), "Remote quest turn-ins do not notify the host")
	NetSession._feedback(NetSession.epoch + 1, "quest_complete", ["line"])
	check(popup._current.is_empty(), "Old-session reward feedback is ignored")
	NetSession._feedback(NetSession.epoch, "quest_complete", ["not_a_quest"])
	check(popup._current.is_empty(), "Malformed reward feedback is ignored")
	NetSession._feedback(NetSession.epoch, "quest_complete", ["line"])
	check(popup._current.kind == "complete", "The recipient displays authoritative reward feedback")
	NetSession.enabled = false
	NetSession.game = null
	# Every quest can finish together; UI nodes remain constant and queued messages
	# are capped by the finite quest catalogue, with one message per quest.
	popup.reset()
	popup.hide()
	var child_count := popup.find_children("*", "", true, false).size()
	for id: String in Progression.QUESTS:
		popup.rewarded(id)
		popup.rewarded(id)
	check(popup._queue.size() == Progression.QUESTS.size(), "Concurrent completions queue once per quest")
	check(popup.find_children("*", "", true, false).size() == child_count, "Burst notifications reuse the existing UI")
	popup.reset()
	popup.show()
	popup.rewarded("watch")
	popup._process(0.5)
	if "--render-quest-notifications" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://../artifacts/quest-notifications/")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder + "reward.png")
		check(popup._card.size.y <= 160, "Reward card remains compact after text layout")
		popup.reset()
		popup._enqueue({"id": "line", "kind": "ready", "goals": []})
		popup._process(0.5)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "ready.png")
	wall.free()
	game.queue_free()
	await process_frame
	if "--render-quest-notifications" in OS.get_cmdline_user_args(): await render_world()
	print("QUEST_NOTIFICATIONS_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func render_world() -> void:
	print("QUEST_RENDER_WORLD_LOADING")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	var shop: Progression = game.progression
	shop.set_process(false)
	var popup: Control = shop.notifications
	popup.show()
	popup.set_process(false)
	var d := shop.local_data()
	d.claimed.arrival = true
	d.accepted.watch = true
	d.accepted_wave.watch = 1
	game.waves.completed = 1
	shop.team.built = 1
	shop.refresh_notifications()
	popup._process(0.5)
	await capture("world-progress")
	check(popup._card.get_global_rect().end.x <= popup.size.x and popup._card.position.x >= 0, "Popup fits the game viewport")
	check(popup._card.size.y <= 180, "Subgoal card stays compact in the game HUD")
	check(popup._card.mouse_filter == Control.MOUSE_FILTER_IGNORE and popup.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Popup leaves aiming and menu input untouched")
	shop.team.turned = 1
	game.barricades[0].level = 1
	game.waves.completed = 2
	shop.refresh_notifications()
	popup._process(0.5)
	await capture("world-ready")
	popup.rewarded("watch")
	popup._process(0.5)
	await capture("world-reward")
	game.queue_free()
	await process_frame

func capture(file_name: String) -> void:
	# Allow layout and the renderer's initial font uploads to settle.
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/quest-notifications/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + file_name + ".png")

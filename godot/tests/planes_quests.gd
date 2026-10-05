extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)

func run() -> void:
	var game: Node3D = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_for_exploration: await process_frame
	game.waves.set_process(false)
	var q: Node = game.progression
	game.player.global_position = q.npcs.camp.global_position
	q.open_field("camp")
	q.page = "Quests"
	q.refresh_field()
	check(q._row_nodes[0][2].text=="View introduction" and not q._row_nodes[0][2].disabled,"Optional Vendor guidance can be opened separately from paid supplies and quests")
	check(q._row_nodes.size()==5 and q._row_nodes[1][2].text=="Accept quest" and not q._row_nodes[1][2].disabled,"Only the introductory Vendor quest is available at level one")
	check(q._row_nodes[2][2].text=="Locked" and q._row_nodes[2][2].disabled,"Later quests appear locked in the Vendor menu")
	check(not q.authoritative_action(game.player,"quest_action",["bouquet","camp"]).is_empty() and not q.accepted.has("bouquet"),"Direct quest requests cannot bypass prerequisites")
	q.claimed.welcome = true
	check(not q.field_quest_lock_reason("bouquet").is_empty(),"Completing the intro alone does not skip the wave gate")
	game.waves.completed = 1
	q.refresh_field()
	check(q._row_nodes[2][2].text=="Accept quest" and not q._row_nodes[2][2].disabled,"Flower quest unlocks after the first wave")
	q.field_counts.flowers = 6
	q.quest_action("bouquet")
	check(q.accepted.has("bouquet") and q.quest_ready("bouquet"),"Earlier flower collection counts after the quest unlocks")
	check(Lang.text(q.field_quest_progress("bouquet")).contains("Collect six marked wildflower bundles") and q.field_quest_progress("bouquet").contains("[color=#79df96]"),"Quest progress explains the objective and checks off completed collection")
	q.quest_action("bouquet")
	check(q.claimed.has("bouquet"),"Unlocked quest pays its reward once")
	game.waves.completed = 2
	q.field_counts.kills = 30
	q.quest_action("watch")
	check(q.accepted.has("watch") and not q.quest_ready("watch"),"Combat quest requires a wave after acceptance despite completed objectives")
	check(q.field_quest_progress("watch").contains("[color=#79df96]") and Lang.text(q.field_quest_progress("watch")).contains("survive through wave 3") and q.field_quest_progress("watch").contains("□"),"Completed kills and the outstanding wave appear as separate checklist steps")
	game.waves.completed = 3
	check(q.quest_ready("watch"),"Combat reward becomes ready after the required wave")
	check(q.field_quest_progress("watch").count("[color=#79df96]")==2,"Both checklist steps turn green after the required wave")
	q.close()
	q._update_tracker()
	check(Lang.text(q.tracker.text).contains("Open sky, steady hands") and Lang.text(q.tracker.text).contains("Ready to turn in") and q.tracker.text.contains("#ffd479"),"HUD tracker names the completed quest and highlights its next action: collect the reward")
	var book_quests: Array = q.fieldbook_quests()
	check(book_quests.size()==1 and book_quests[0].ready and Lang.text(book_quests[0].details).contains("Defeat thirty zombies"),"The fieldbook preserves the completed objective checklist behind the compact HUD")
	q.quest_action("watch")
	check(q.claimed.has("watch") and not q.field_quest_lock_reason("veteran").is_empty(),"Late survival quest remains locked after early quest completion")
	q.close()
	game.player.global_position = q.npcs.mechanic.global_position
	q.open_field("mechanic")
	check(q.page=="Quests" and q._tabs.Quests.visible and q._row_nodes.size()==2,"Mechanic opens on the quest tab")
	q.page = "Training"
	q.refresh_field()
	check(q._tabs.Training.visible and q._row_nodes.size()>=2,"Mechanic training remains available from its tab")
	check(q._row_nodes.all(func(row): return not row[0].text.contains("kit")),"Training no longer mixes in fortification purchases")
	q.page = "Barricades"
	q.refresh_field()
	check(q._tabs.Barricades.visible and q._row_nodes.size()==2,"Mechanic has a separate barricade shop")
	check(q._row_nodes[0][3].texture==ItemIcons.texture("barricade") and q._row_nodes[1][3].texture==ItemIcons.texture("sandbags"),"Palisade and sandbag purchases show their own icons")
	print("PLANES_QUESTS_DONE checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)

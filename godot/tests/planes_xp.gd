extends SceneTree
const Classes = preload("res://scripts/character_classes.gd")
var game: Node
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)
func xp() -> int: return int(CharacterProfile.data.classes.gunslinger.total_xp)
func run() -> void:
	CharacterProfile.data = CharacterProfile.empty_profile("Planes XP test")
	CharacterProfile.data.classes.gunslinger.total_xp = Classes.threshold(5)-10
	CharacterProfile.data.achievements.first_blood = true
	CharacterProfile.data.achievements["world:first_blood"] = true
	var initial := xp()
	game = load("res://scenes/planes.tscn").instantiate()
	root.add_child(game); current_scene = game
	while not game.ready_for_exploration: await process_frame
	game.waves.set_process(false)
	check(xp()==initial and CharacterProfile.context=="match","Planes retains the selected Forest profile and XP")
	check(game.player.class_combat.build.id=="gunslinger","Selected class build is applied")
	var display: Node = game.hud._root.get_node("CharacterHud")
	check(display.bar.max_value>0 and not display.title.text.is_empty(),"Shared Forest XP bar and level are present")
	var enemy: Zombie = game.create_enemy("shambler",game.player.position+Vector3(5,0,0),1)
	enemy.killer_weapon = "pistol"
	game._enemy_killed(enemy)
	game.discard_enemy(enemy)
	check(xp()==initial+15 and CharacterProfile.level("gunslinger")==5,"Kill uses Forest XP and triggers a level-up")
	check(display._level_time>0,"Level-up is shown in the shared HUD")
	var before := xp()
	game.waves.wave = 1; game.waves.phase = "spawning"; game.waves.queue.clear()
	game.waves.complete_wave()
	check(xp()==before+220,"Completing a Planes wave awards Forest wave XP")
	game.waves.complete_wave()
	check(xp()==before+220,"Completed wave cannot award XP twice")
	game.progression.accepted.bouquet = true
	game.progression.claimed.welcome = true
	game.progression.field_counts.flowers = 6
	game.player.position = game.progression.npcs.camp.position
	before = xp()
	game.progression.quest_action("bouquet")
	check(xp()==before+Classes.quest_xp(120) and CharacterProfile.data.quests.get("planes:bouquet",0)==1,"Field quest awards shared XP under a map-specific ID")
	game.progression.quest_action("bouquet")
	check(xp()==before+Classes.quest_xp(120),"Quest reward cannot be claimed twice")
	before = xp()
	game.waves.wave = 25; game.waves.phase = "spawning"
	game.waves.complete_wave()
	# Jumping straight from wave one also earns the new 5/15/25 milestones.
	check(xp()==before+700+2000+250+500+2000 and CharacterProfile.data.classes.gunslinger.stats.missions==1,"Wave 25 awards wave, mission and Planes achievement XP exactly once")
	check(CharacterProfile.data.achievements.has("world:planes_wave5") and CharacterProfile.data.achievements.has("world:planes_wave15") and CharacterProfile.data.achievements.has("world:planes_wave25"),"Planes milestone achievements persist in the shared character profile")
	before = xp()
	await game.start_survival()
	game.waves.set_process(false)
	check(xp()==before and CharacterProfile.context=="match","Retry preserves XP and starts a new class session")
	game.waves.wave = 1; game.waves.phase = "spawning"; game.waves.queue.clear()
	game.waves.complete_wave()
	check(xp()==before+220,"New run can earn wave rewards again")
	game.finish_survival(false)
	check(CharacterProfile.data.classes.gunslinger.stats.deaths==1,"Death updates the shared profile once")
	before = xp()
	game.finish_survival(false)
	check(CharacterProfile.data.classes.gunslinger.stats.deaths==1,"Repeated game-over cannot duplicate death statistics")
	game.stop_survival()
	check(game.classes==null and CharacterProfile.context=="main","Exploration ends the XP session")
	CharacterProfile.directory = ProjectSettings.globalize_path("user://planes-xp-test")
	DirAccess.make_dir_recursive_absolute(CharacterProfile.directory)
	CharacterProfile.profile_id = "planes_test"
	CharacterProfile.persist = true; CharacterProfile.dirty = true
	check(CharacterProfile.save(),"Progress saves successfully to an isolated profile")
	CharacterProfile.data = {}
	check(CharacterProfile.load_profile("planes_test") and xp()==before,"Saved XP survives profile reload")
	CharacterProfile.persist = false
	game.queue_free(); await process_frame
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game); current_scene = game
	while not game.navigation_ready: await process_frame
	check(xp()==before and game.player.class_combat.build.level==CharacterProfile.level("gunslinger"),"Returning to Forest retains the earned level and XP")
	print("PLANES_XP_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

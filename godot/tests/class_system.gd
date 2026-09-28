extends SceneTree
const Classes = preload("res://scripts/character_classes.gd")
const Profile = preload("res://scripts/character_profile.gd")
const Combat = preload("res://scripts/class_combat.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

class Target extends Node3D:
	var alive := true
	var net_kind := "shambler"
	var armored := false
	var height := 1.8
	var hp := 100.0
	var max_hp := 100.0
	var player: Node
	var hunting := true
	var _aggro_target: Node
	var class_slow_time := 0.0
	var impulse := Vector3.ZERO
	static func is_boss_kind(kind: String) -> bool: return kind == "titan"
	func shove(value: Vector3) -> void: impulse = value

func perk(id: String) -> RefCounted:
	var combat := Combat.new()
	for cls in Classes.ORDER:
		for tier in 6:
			for option in 2:
				if Classes.CLASSES[cls].talents[tier][option][0] != id: continue
				var choices := [-1, -1, -1, -1, -1, -1]
				choices[tier] = option
				combat.configure({"id": cls, "level": 30, "choices": choices})
	return combat

func run() -> void:
	check(not CharacterProfile.persist, "Automated runs never load or save the real character")
	check(Classes.XP_STEPS.size() == 29, "Exactly 29 level transitions")
	for level in range(2, 31):
		var threshold := Classes.threshold(level)
		check(Classes.level_for(threshold - 1) == level - 1 and Classes.level_for(threshold) == level, "XP boundary %d" % level)
	check(Classes.level_for(99999999) == 30 and Classes.progress(99999999).required == 0, "Level cap keeps lifetime XP without extra tiers")
	var ids := {}
	for cls in Classes.ORDER:
		check(Classes.CLASSES[cls].talents.size() == 6, "%s has six talent pairs" % cls)
		for pair in Classes.CLASSES[cls].talents:
			check(pair.size() == 2, "Exactly two options per tier")
			for talent in pair:
				check(not ids.has(talent[0]), "Stable unique talent: " + talent[0])
				ids[talent[0]] = true
	check(ids.size() == 60, "All sixty passive talents are defined")
	check(Classes.sanitize_loadout({"id": "assassin", "level": 31}).is_empty(), "Out-of-range network levels rejected")
	check(Classes.sanitize_loadout({"id": "assassin", "level": NAN}).is_empty(), "Non-finite network levels rejected")
	check(Classes.sanitize_loadout({"id": "assassin", "level": 1.5}).is_empty(), "Fractional levels rejected")
	check(Classes.valid_choices("marksman", 5, [1, 1, 1, 1, 1, 1]) == [1,-1,-1,-1,-1,-1], "Locked talents are removed from hostile loadouts")
	var profile := Profile.new()
	profile.persist = false
	profile.data = Profile.empty_profile("Test")
	profile.add_xp(Classes.threshold(15), "test")
	check(profile.level("gunslinger") == 15 and profile.level("assassin") == 1, "Only the selected class receives XP, including multiple level-ups")
	check(profile.choose_skill("gunslinger", 0, 0) and profile.choose_skill("gunslinger", 0, 1) and profile.data.classes.gunslinger.choices[0] == 1, "A tier can be freely respecced and keeps one selection")
	check(not profile.choose_skill("gunslinger", 3, 0), "Locked tiers cannot be activated")
	profile.context = "multiplayer"
	check(not profile.choose_skill("gunslinger", 0, 0), "Skills are locked in the multiplayer menu before connecting")
	profile.context = "lobby"
	check(not profile.choose_skill("gunslinger", 0, 0) and not profile.select_class("marksman"), "Lobby edits go through the host, never the local skill API")
	profile.begin_match("gunslinger")
	check(not profile.choose_skill("gunslinger", 0, 0) and not profile.select_class("assassin"), "Class and talent changes rejected during matches")
	profile.record_kill(true, false, true, 7)
	profile.record_headshot()
	var before: int = profile.data.classes.gunslinger.total_xp
	profile.record_kill(true, false, true, 8)
	profile.record_headshot()
	check(profile.data.classes.gunslinger.total_xp == before and profile.data.achievements.first_blood, "Achievement XP is granted once across the profile")
	check(profile.data.classes.gunslinger.stats.best_streak == 8 and profile.data.classes.gunslinger.stats.multiplayer_kills == 2, "Per-class kill and multiplayer statistics")
	profile.end_match()
	profile.select_class("assassin")
	check(profile.level("gunslinger") == 15 and profile.loadout().id == "assassin", "Changing classes preserves earlier progress")
	profile.quest("supplies", 500)
	check(profile.data.quests.supplies == 1 and profile.data.classes.assassin.total_xp == 500, "Quest XP belongs to the played class")
	profile.data.classes.assassin.stats.seconds = 500
	check(profile.favourite() == "assassin", "Favourite class follows lifetime play time")
	var folder := ProjectSettings.globalize_path("res://../artifacts/class-profile-test/%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	profile.directory = folder
	profile.persist = true
	profile.dirty = true
	check(profile.save(), "Profile writes atomically into the game folder")
	profile.add_xp(500, "test")
	check(profile.save() and FileAccess.file_exists(profile.path_for("local") + ".bak"), "A replacement preserves the previous valid save")
	var copy := Profile.new()
	copy.directory = folder
	var loaded := copy.load_profile("local")
	check(loaded and copy.data == Profile.sanitize(profile.data), "Profile survives a fresh process-style reload")
	FileAccess.open(profile.path_for("local"), FileAccess.WRITE).store_string("broken")
	check(copy.load_profile("local") and copy.data.classes.assassin.total_xp == 500, "Corrupt current file recovers the valid backup")
	copy.dirty = true
	check(copy.save(), "Recovered profile can be saved again")
	var bad := Profile.sanitize({"selected": "invalid", "classes": {"gunslinger": {"total_xp": -7, "choices": [1,1,1,1,1,1], "stats": {"kills": "oops", "seconds": NAN}}}})
	check(bad.classes.gunslinger.total_xp == 0 and bad.classes.gunslinger.stats.seconds == 0 and bad.classes.gunslinger.choices == [-1,-1,-1,-1,-1,-1], "Malformed save fields are safely normalised")
	profile.persist = false
	copy.persist = false
	profile.free()
	copy.free()
	combat_checks()
	print("CLASS_SYSTEM_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func combat_checks() -> void:
	var actor := Node3D.new()
	var enemies := Node3D.new()
	root.add_child(actor)
	root.add_child(enemies)
	var target := Target.new()
	enemies.add_child(target)
	target.player = actor
	target._aggro_target = actor
	actor.position = Vector3(0,0,-3)
	for spec in [["quick_hands", "reload", "pistol", 0.8], ["steady_hand", "recoil", "pistol", 0.85], ["quick_swap", "switch", "pistol", 0.5], ["fan_hammer", "bloom", "pistol", 0.6], ["tactical_reload", "reload", "ak47", 0.82], ["ammo_discipline", "magazine", "ak47", 1.15], ["burst", "spread", "ak47", 0.75], ["speed_loader", "reload", "shotgun", 0.8], ["tight_spread", "spread", "shotgun", 0.75], ["fast_focus", "ads", "marksman", 1.3], ["light_footed", "speed", "knife", 1.1], ["ghost_step", "detection", "knife", 0.8], ["weapon_master", "reload", "knife", 0.9], ["master_assassin", "switch", "knife", 0.8], ["weapons_expert", "recoil", "ak47", 0.9]]:
		var c = perk(spec[0])
		check(is_equal_approx(c.modifier(spec[1], spec[2]), spec[3]), "%s affects %s" % [spec[0], spec[1]])
	check(is_equal_approx(perk("firm_stance").modifier("sway", "marksman", 1), 0.5), "Firm Stance reduces aimed sway")
	check(is_equal_approx(perk("last_stand").modifier("speed", "ak47", 0, true), 1.1), "Last Stand requires low health")
	check(is_equal_approx(perk("veteran").modifier("reload", "ak47", 0, false, true), 0.7), "Veteran requires a low magazine")
	check(perk("quick_hands").modifier("reload", "shotgun") == 1.0, "Pistol specialisation never improves a shotgun")
	for spec in [["bounty", "pistol", true, 1.15], ["gunslinger", "pistol", false, 1.1], ["large_caliber", "shotgun", false, 1.12], ["weak_spot", "marksman", true, 1.2], ["one_shot", "marksman", false, 1.2], ["no_mercy", "shotgun", false, 1.2], ["crowd_control", "ak47", false, 1.12], ["silent_killer", "knife", false, 1.2], ["assassination", "knife", false, 1.35]]:
		var c = perk(spec[0])
		c.begin_shot(false)
		check(is_equal_approx(c.damage_multiplier(spec[1], target, spec[2], actor, enemies), spec[3]), "%s changes actual damage under its trigger" % spec[0])
	var one = perk("one_shot")
	one.begin_shot(false)
	one.damage_multiplier("marksman", target, false, actor, enemies)
	one.begin_shot(false)
	check(one.damage_multiplier("marksman", target, false, actor, enemies) == 1.0, "First-hit bonus cannot be reused on the same enemy")
	var duel = perk("duelist")
	duel.begin_shot(false)
	duel.damage_multiplier("pistol", target, false, actor, enemies)
	duel.begin_shot(false)
	check(duel.damage_multiplier("pistol", target, false, actor, enemies) > 1.0, "Duelist builds damage on repeated hits")
	var boom = perk("boomstick")
	boom.begin_shot(true)
	check(is_equal_approx(boom.damage_multiplier("shotgun", target, false, actor, enemies), 1.35), "Boomstick recognises the full magazine before ammo is spent")
	var deadeye = perk("deadeye")
	deadeye.begin_shot(false)
	deadeye.damage_multiplier("pistol", target, true, actor, enemies)
	deadeye.end_shot("pistol", true)
	deadeye.begin_shot(false)
	check(deadeye.damage_multiplier("pistol", target, true, actor, enemies) > 1, "Deadeye builds a headshot chain")
	deadeye.end_shot("pistol", false)
	check(deadeye.head_chain == 0, "A miss ends Deadeye")
	var suppression = perk("suppression")
	for i in 2:
		suppression.begin_shot(false)
		suppression.damage_multiplier("ak47", target, false, actor, enemies)
	check(target.class_slow_time == 2, "Repeated assault hits apply suppression")
	var knock = perk("knockback")
	knock.begin_shot(false)
	knock.damage_multiplier("shotgun", target, false, actor, enemies)
	knock.after_hit("shotgun", target, actor)
	check(target.impulse.length() > 6.9, "Knockback applies a physical shove")
	check(perk("penetration").extra_penetration("shotgun", target) == 1 and perk("piercing").extra_penetration("marksman", target) == 1, "Both penetration talents extend bullet traversal")
	for spec in [["sidestep", "pistol", "speed"], ["high_noon", "pistol", "reload"], ["frontline", "ak47", "recoil"], ["combat_drill", "ak47", "reload"], ["combat_momentum", "ak47", "rate"], ["juggernaut", "shotgun", "guard"], ["momentum", "knife", "speed"]]:
		var c = perk(spec[0])
		c.killed(spec[1], true, 3)
		check(c.modifier(spec[2], spec[1]) != 1.0, "%s grants its kill buff" % spec[0])
		c.tick(6, actor, null, enemies)
		check(c.modifier(spec[2], spec[1]) == 1.0, "%s buff expires" % spec[0])
	var escape = perk("escape_artist")
	escape.hurt(30)
	check(escape.modifier("speed") > 1, "Heavy damage triggers Escape Artist")
	var shadow = perk("shadow")
	shadow.tick(4.1, actor, null, enemies)
	check(shadow.modifier("detection") < 1, "Shadow reduces detection after a quiet interval")
	shadow.begin_shot(false)
	check(shadow.modifier("detection") == 1, "Firing immediately ends Shadow")
	var untouched = perk("untouchable")
	untouched.tick(8.1, actor, null, enemies)
	check(untouched.modifier("speed") > 1, "Untouchable rewards a damage-free interval")
	untouched.hurt(1)
	check(untouched.modifier("speed") == 1, "Taking damage ends Untouchable")
	var predator = perk("predator")
	predator.tick(5.1, actor, null, enemies)
	check(predator.modifier("spread", "pistol") == 0.5, "Predator is ready outside direct combat")
	predator.begin_shot(false)
	check(predator.damage_multiplier("pistol", target, true, actor, enemies) > 1 and predator.modifier("spread", "pistol") == 1, "Predator is consumed by the next shot")
	var ice = perk("ice_cold")
	ice.begin_shot(false)
	ice.damage_multiplier("pistol", target, true, actor, enemies)
	check(ice.modifier("recoil", "pistol") < 1, "Ice Cold applies its headshot recoil buff")
	target.hp = 20
	check(perk("executioner").damage_multiplier("pistol", target, false, actor, enemies) > 1, "Executioner requires a wounded target")
	target.hp = 100
	target.armored = true
	check(perk("armor_breaker").damage_multiplier("ak47", target, false, actor, enemies) > 1, "Armor Breaker rewards armoured targets")
	check(perk("breaching").damage_multiplier("shotgun", target, false, actor, enemies) > 1, "Breaching rewards armour")
	target.armored = false
	target.net_kind = "titan"
	check(perk("hunter").damage_multiplier("marksman", target, false, actor, enemies) > 1, "Hunter rewards special targets")
	check(perk("big_game").damage_multiplier("marksman", target, false, actor, enemies) > 1, "Big Game Hunter rewards bosses")
	check(perk("penetration").extra_penetration("shotgun", target) == 0, "Shotgun penetration cannot pass through bosses")
	target.net_kind = "shambler"
	var blood = perk("bloodbath")
	blood.killed("shotgun", false, 3)
	check(blood.damage_multiplier("shotgun", target, false, actor, enemies) > 1, "Bloodbath is triggered by a close kill")
	for i in 2: enemies.add_child(Target.new())
	check(perk("crowd_breaker").damage_multiplier("shotgun", target, false, actor, enemies) > 1, "Crowd Breaker detects a clustered group")
	var ground = perk("stand_ground")
	ground.tick(0.3, actor, null, enemies)
	check(ground.modifier("guard") < 1, "Stand Your Ground detects surrounding enemies")
	var breath = perk("breath_control")
	breath.aim_time = 3
	check(is_equal_approx(breath.modifier("spread", "marksman", 1), 0.6), "Breath Control reaches its precision cap")
	var quick = perk("quickscope")
	quick.aim_time = 0.2
	quick.begin_shot(false)
	check(quick.damage_multiplier("marksman", target, true, actor, enemies) > 1, "Quickscope rewards a prompt aimed headshot")
	quick.aim_time = 2
	check(quick.damage_multiplier("marksman", target, true, actor, enemies) == 1, "Quickscope expires outside its timing window")
	var chain = perk("kill_chain")
	chain.killed("marksman", true, 10)
	chain.begin_shot(false)
	check(chain.damage_multiplier("marksman", target, false, actor, enemies) > 1 and not chain.active("kill_chain"), "Kill Chain is spent on one precision hit")
	var perfect = perk("perfect_shot")
	perfect.tick(4.1, actor, null, enemies)
	perfect.begin_shot(false)
	check(perfect.damage_multiplier("marksman", target, true, actor, enemies) == 1.5, "Perfect Shot rewards a clean four-second interval")
	check(perfect.damage_multiplier("marksman", target, true, actor, enemies) == 1, "Perfect Shot cannot stack on one shot")
	var rhythm = perk("rhythm")
	for i in 8: rhythm.end_shot("marksman", true)
	check(is_equal_approx(rhythm.modifier("reload", "marksman"), 0.75), "Marksman's Rhythm is capped at five hits")
	rhythm.end_shot("marksman", false)
	check(rhythm.modifier("reload", "marksman") == 1, "A miss clears Marksman's Rhythm")
	var other := Node3D.new()
	root.add_child(other)
	target.player = other
	check(perk("opportunist").damage_multiplier("knife", target, false, actor, enemies) > 1, "Opportunist only rewards another player's target")
	other.free()
	actor.free()
	enemies.free()

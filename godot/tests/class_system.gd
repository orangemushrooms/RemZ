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

# Isolate each talent from the independently tested per-level mastery bonus.
func talent_damage(c: RefCounted, weapon: String, enemy: Node3D, head: bool, actor: Node3D, enemies: Node) -> float:
	return c.damage_multiplier(weapon, enemy, head, actor, enemies) / c.mastery_multiplier(weapon)

func run() -> void:
	check(not CharacterProfile.persist, "Automated runs never load or save the real character")
	check(Classes.XP_STEPS.size() == 29, "Exactly 29 level transitions")
	check(Classes.XP_STEPS[0] == 1100 and Classes.XP_STEPS[28] == 55000, "Levelling is only ten percent slower")
	for old_level in range(1, 31):
		var old := Profile.empty_profile("Existing survivor")
		old.version = 1
		var old_threshold := Classes.threshold(old_level) * 10 / 11
		var partial := int(Classes.XP_STEPS[old_level - 1]) * 5 / 11 if old_level < 30 else 123
		old.classes.marksman.total_xp = old_threshold + partial
		old.classes.marksman.choices = Classes.valid_choices("marksman", old_level, [1,0,1,0,1,0])
		var migrated := Profile.sanitize(old)
		check(Classes.level_for(migrated.classes.marksman.total_xp) == old_level and migrated.classes.marksman.choices == old.classes.marksman.choices, "Version-one level %d and talent choices survive the gentler curve" % old_level)
		check(Profile.sanitize(migrated) == migrated, "Migration is applied only once at level %d" % old_level)
		if old_level < 30:
			var progress := Classes.progress(migrated.classes.marksman.total_xp)
			check(absf(float(progress.xp) / progress.required - 0.5) < 0.001, "Existing progress within level %d is preserved" % old_level)
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
	var legacy := Profile.empty_profile("Earlier save")
	legacy.version = 1
	legacy.classes.gunslinger.total_xp = 8250 # Level 5, half way to level 6 on the old curve.
	legacy.classes.gunslinger.choices[0] = 1
	FileAccess.open(copy.path_for("legacy"), FileAccess.WRITE).store_string(JSON.stringify(legacy))
	check(copy.load_profile("legacy") and copy.level("gunslinger") == 5 and copy.data.classes.gunslinger.choices[0] == 1, "A real version-one file loads with its level and selected talent")
	check(Profile.read_json(copy.path_for("legacy")).version == Profile.VERSION and not copy.dirty, "Loading an old file persists its migration immediately")
	check(Profile.read_json(copy.path_for("legacy") + ".bak").version == 1, "The original version-one file is retained as backup")
	var migrated_xp: int = copy.data.classes.gunslinger.total_xp
	check(copy.load_profile("legacy") and copy.data.classes.gunslinger.total_xp == migrated_xp, "A second disk load never scales XP again")
	var bad := Profile.sanitize({"selected": "invalid", "classes": {"gunslinger": {"total_xp": -7, "choices": [1,1,1,1,1,1], "stats": {"kills": "oops", "seconds": NAN}}}})
	check(bad.classes.gunslinger.total_xp == 0 and bad.classes.gunslinger.stats.seconds == 0 and bad.classes.gunslinger.choices == [-1,-1,-1,-1,-1,-1], "Malformed save fields are safely normalised")
	profile.persist = false
	copy.persist = false
	profile.free()
	copy.free()
	combat_checks()
	balance_checks()
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
	for spec in [["quick_hands", "reload", "pistol", 0.8], ["steady_hand", "recoil", "pistol", 0.85], ["quick_swap", "switch", "pistol", 0.5], ["fan_hammer", "bloom", "pistol", 0.6], ["tactical_reload", "reload", "ak47", 0.82], ["ammo_discipline", "magazine", "ak47", 1.15], ["burst", "spread", "ak47", 0.75], ["speed_loader", "reload", "shotgun", 0.8], ["tight_spread", "spread", "shotgun", 0.75], ["fast_focus", "ads", "marksman", 1.3], ["light_footed", "speed", "knife", 1.1], ["ghost_step", "detection", "knife", 0.8], ["weapon_master", "reload", "knife", 0.9], ["master_assassin", "switch", "knife", 0.4], ["weapons_expert", "recoil", "ak47", 0.55]]:
		var c = perk(spec[0])
		check(is_equal_approx(c.modifier(spec[1], spec[2]), spec[3]), "%s affects %s" % [spec[0], spec[1]])
	check(is_equal_approx(perk("firm_stance").modifier("sway", "marksman", 1), 0.5), "Firm Stance reduces aimed sway")
	check(is_equal_approx(perk("last_stand").modifier("speed", "ak47", 0, true), 1.25), "Last Stand requires low health")
	check(is_equal_approx(perk("veteran").modifier("reload", "ak47", 0, false, true), 0.35), "Veteran requires a low magazine")
	check(perk("quick_hands").modifier("reload", "shotgun") == 1.0, "Pistol specialisation never improves a shotgun")
	for spec in [["bounty", "pistol", true, 1.15], ["gunslinger", "pistol", false, 1.5], ["large_caliber", "shotgun", false, 1.12], ["weak_spot", "marksman", true, 1.2], ["one_shot", "marksman", false, 1.2], ["no_mercy", "shotgun", false, 1.75], ["crowd_control", "ak47", false, 1.12], ["silent_killer", "knife", false, 1.2], ["assassination", "knife", false, 3.0]]:
		var c = perk(spec[0])
		c.begin_shot(false)
		check(is_equal_approx(talent_damage(c, spec[1], target, spec[2], actor, enemies), spec[3]), "%s changes actual damage under its trigger" % spec[0])
	var one = perk("one_shot")
	one.begin_shot(false)
	talent_damage(one, "marksman", target, false, actor, enemies)
	one.begin_shot(false)
	check(talent_damage(one, "marksman", target, false, actor, enemies) == 1.0, "First-hit bonus cannot be reused on the same enemy")
	var duel = perk("duelist")
	duel.begin_shot(false)
	talent_damage(duel, "pistol", target, false, actor, enemies)
	duel.begin_shot(false)
	check(talent_damage(duel, "pistol", target, false, actor, enemies) > 1.0, "Duelist builds damage on repeated hits")
	var boom = perk("boomstick")
	boom.begin_shot(true)
	check(is_equal_approx(talent_damage(boom, "shotgun", target, false, actor, enemies), 3.0), "Boomstick recognises the full magazine before ammo is spent")
	var deadeye = perk("deadeye")
	deadeye.begin_shot(false)
	talent_damage(deadeye, "pistol", target, true, actor, enemies)
	deadeye.end_shot("pistol", true)
	deadeye.begin_shot(false)
	check(talent_damage(deadeye, "pistol", target, true, actor, enemies) > 1, "Deadeye builds a headshot chain")
	deadeye.end_shot("pistol", false)
	check(deadeye.head_chain == 0, "A miss ends Deadeye")
	var suppression = perk("suppression")
	for i in 2:
		suppression.begin_shot(false)
		talent_damage(suppression, "ak47", target, false, actor, enemies)
	check(target.class_slow_time == 2, "Repeated assault hits apply suppression")
	var knock = perk("knockback")
	knock.begin_shot(false)
	talent_damage(knock, "shotgun", target, false, actor, enemies)
	knock.after_hit("shotgun", target, actor)
	check(target.impulse.length() > 6.9, "Knockback applies a physical shove")
	check(perk("penetration").extra_penetration("shotgun", target) == 1 and perk("piercing").extra_penetration("marksman", target) == 1, "Both penetration talents extend bullet traversal")
	for spec in [["sidestep", "pistol", "speed"], ["high_noon", "pistol", "reload"], ["frontline", "ak47", "recoil"], ["combat_drill", "ak47", "reload"], ["combat_momentum", "ak47", "rate"], ["juggernaut", "shotgun", "guard"], ["momentum", "knife", "speed"]]:
		var c = perk(spec[0])
		var base: float = c.modifier(spec[2], spec[1])
		c.killed(spec[1], true, 3)
		check(c.modifier(spec[2], spec[1]) != 1.0, "%s grants its kill buff" % spec[0])
		c.tick(11, actor, null, enemies)
		check(is_equal_approx(c.modifier(spec[2], spec[1]), base), "%s buff expires" % spec[0])
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
	check(predator.modifier("spread", "pistol") == 0.2, "Predator is ready outside direct combat")
	predator.begin_shot(false)
	check(talent_damage(predator, "pistol", target, true, actor, enemies) > 1 and predator.modifier("spread", "pistol") == 1, "Predator is consumed by the next shot")
	var ice = perk("ice_cold")
	ice.begin_shot(false)
	talent_damage(ice, "pistol", target, true, actor, enemies)
	check(ice.modifier("recoil", "pistol") < 1, "Ice Cold applies its headshot recoil buff")
	target.hp = 20
	check(talent_damage(perk("executioner"), "pistol", target, false, actor, enemies) > 1, "Executioner requires a wounded target")
	target.hp = 100
	target.armored = true
	check(talent_damage(perk("armor_breaker"), "ak47", target, false, actor, enemies) > 1, "Armor Breaker rewards armoured targets")
	check(talent_damage(perk("breaching"), "shotgun", target, false, actor, enemies) > 1, "Breaching rewards armour")
	target.armored = false
	target.net_kind = "titan"
	check(talent_damage(perk("hunter"), "marksman", target, false, actor, enemies) > 1, "Hunter rewards special targets")
	check(talent_damage(perk("big_game"), "marksman", target, false, actor, enemies) > 1, "Big Game Hunter rewards bosses")
	check(perk("penetration").extra_penetration("shotgun", target) == 0, "Shotgun penetration cannot pass through bosses")
	target.net_kind = "shambler"
	var blood = perk("bloodbath")
	blood.killed("shotgun", false, 3)
	check(talent_damage(blood, "shotgun", target, false, actor, enemies) > 1, "Bloodbath is triggered by a close kill")
	for i in 2: enemies.add_child(Target.new())
	check(talent_damage(perk("crowd_breaker"), "shotgun", target, false, actor, enemies) > 1, "Crowd Breaker detects a clustered group")
	var ground = perk("stand_ground")
	ground.tick(0.3, actor, null, enemies)
	check(ground.modifier("guard") < 1, "Stand Your Ground detects surrounding enemies")
	var breath = perk("breath_control")
	breath.aim_time = 3
	check(is_equal_approx(breath.modifier("spread", "marksman", 1), 0.6), "Breath Control reaches its precision cap")
	var quick = perk("quickscope")
	quick.aim_time = 0.2
	quick.begin_shot(false)
	check(talent_damage(quick, "marksman", target, true, actor, enemies) > 1, "Quickscope rewards a prompt aimed headshot")
	quick.aim_time = 2
	check(talent_damage(quick, "marksman", target, true, actor, enemies) == 1, "Quickscope expires outside its timing window")
	var chain = perk("kill_chain")
	chain.killed("marksman", true, 10)
	chain.begin_shot(false)
	check(talent_damage(chain, "marksman", target, false, actor, enemies) > 1 and not chain.active("kill_chain"), "Kill Chain is consumed for the current precision shot")
	var perfect = perk("perfect_shot")
	perfect.tick(2.1, actor, null, enemies)
	perfect.begin_shot(false)
	check(talent_damage(perfect, "marksman", target, true, actor, enemies) == 3.5, "Perfect Shot rewards a clean two-second interval")
	check(talent_damage(perfect, "marksman", target, true, actor, enemies) == 3.5, "Perfect Shot applies to every pierced head in one shot")
	var rhythm = perk("rhythm")
	for i in 8: rhythm.end_shot("marksman", true)
	check(is_equal_approx(rhythm.modifier("reload", "marksman"), 0.5), "Marksman's Rhythm is capped at five hits")
	rhythm.end_shot("marksman", false)
	check(rhythm.modifier("reload", "marksman") == 1, "A miss clears Marksman's Rhythm")
	var other := Node3D.new()
	root.add_child(other)
	target.player = other
	check(talent_damage(perk("opportunist"), "knife", target, false, actor, enemies) > 1, "Opportunist rewards another player's target")
	other.free()
	actor.free()
	enemies.free()

func balance_checks() -> void:
	var actor := Target.new()
	var enemies := Node3D.new()
	root.add_child(actor)
	root.add_child(enemies)
	var target := Target.new()
	var second := Target.new()
	enemies.add_child(target)
	enemies.add_child(second)
	actor.position.z = -3
	target.player = actor
	target._aggro_target = actor
	for cls in Classes.ORDER:
		var weapon: String = "knife" if cls=="assassin" else Classes.CLASSES[cls].weapons[0]
		var c := Combat.new()
		var previous := 0.0
		for level in range(1,31):
			c.configure({"id":cls,"level":level,"choices":[]})
			c.begin_shot(false)
			var damage: float = c.damage_multiplier(weapon,target,false,actor,enemies)
			check(damage>previous and is_equal_approx(damage,1.0+(level-1)*0.02),"%s level %d increases actual weapon damage" % [cls,level])
			previous = damage
		check(c.mastery_multiplier("tower")==1.0 and c.mastery_multiplier("grenade")==1.0,"%s mastery excludes external defence damage" % cls)
	var assassination = perk("assassination")
	assassination.begin_shot(true)
	for pellet in 8:
		check(is_equal_approx(talent_damage(assassination,"shotgun",target,false,actor,enemies),3.0),"Assassination boosts pellet %d of the opening attack" % pellet)
	assassination.end_shot("shotgun",true)
	assassination.begin_shot(false)
	check(talent_damage(assassination,"shotgun",target,false,actor,enemies)==1.0,"Assassination cannot repeat against a previously hit survivor")
	var chain = perk("kill_chain")
	chain.killed("marksman",true,10)
	chain.begin_shot(false)
	check(talent_damage(chain,"marksman",target,true,actor,enemies)==2.0,"Kill Chain doubles the first pierced hit")
	chain.killed("marksman",true,10)
	check(talent_damage(chain,"marksman",second,true,actor,enemies)==2.0 and chain.active("kill_chain"),"Later pierced hits retain the bonus and preserve a new headshot-kill charge")
	chain.end_shot("marksman",true)
	chain.begin_shot(false)
	check(talent_damage(chain,"marksman",second,false,actor,enemies)==2.0,"A headshot kill renews the next shot")
	chain.end_shot("marksman",true)
	chain.begin_shot(false)
	check(talent_damage(chain,"marksman",second,false,actor,enemies)==1.0,"Kill Chain ends after a shot without a new headshot kill")
	var perfect = perk("perfect_shot")
	perfect.tick(2.1,actor,null,enemies)
	perfect.begin_shot(false)
	for victim in [target,second]: check(talent_damage(perfect,"marksman",victim,true,actor,enemies)==3.5,"Perfect Shot boosts each pierced head")
	perfect.end_shot("marksman",true)
	perfect.begin_shot(false)
	check(talent_damage(perfect,"marksman",target,true,actor,enemies)==1.0,"Perfect Shot must recharge after its complete shot")
	var predator = perk("predator")
	predator.tick(3.1,actor,null,enemies)
	predator.begin_shot(false)
	check(talent_damage(predator,"knife",target,false,actor,enemies)==2.5,"Predator empowers actual melee body hits")
	predator.end_shot("knife",true)
	predator.begin_shot(false)
	check(talent_damage(predator,"knife",target,false,actor,enemies)==1.0,"Predator cannot be reused before recharging")
	var frontline = perk("frontline")
	frontline.killed("pistol",true,3)
	check(frontline.modifier("recoil","ak47")==1.0,"Off-class kills cannot activate rifle-only kill buffs")
	var stance = perk("firm_stance")
	check(stance.modifier("spread","marksman",1)==0.5 and stance.modifier("spread","marksman",0)==1.0,"Firm Stance changes actual aimed precision without improving hip fire")
	target.hunting = false
	target._aggro_target = null
	check(talent_damage(perk("opportunist"),"knife",target,false,actor,enemies)>1.0,"Opportunist works against unaware enemies in solo")
	var last = perk("last_stand")
	actor.hp = 49
	check(is_equal_approx(talent_damage(last,"ak47",target,false,actor,enemies),1.75) and last.modifier("guard","ak47",0,true)==0.6,"Last Stand provides its stronger damage and resistance below half health")
	check(talent_damage(last,"pistol",target,false,actor,enemies)==1.0 and last.modifier("guard","pistol",0,true)==1.0,"Last Stand requires an equipped assault rifle")
	var original = perk("high_noon")
	for i in 10: original.killed("pistol",true,3)
	check(original.stacks.high_noon==5 and is_equal_approx(original.modifier("reload","pistol"),0.4),"High Noon reaches but never exceeds five stronger stacks")
	original.tick(0.25,actor,null,enemies)
	var replica = perk("high_noon")
	replica.apply_runtime(original.runtime_snapshot())
	check(replica.status("pistol")==original.status("pistol") and replica.modifier("rate","pistol")==original.modifier("rate","pistol"),"Co-op snapshots preserve talent readiness, stacks and effects")
	for cls in Classes.ORDER:
		for pair in Classes.CLASSES[cls].talents:
			for talent in pair:
				check(Lang.resolve(talent[2],"de")!=talent[2],"German description exists for "+talent[0])
	perfect.time_since_miss = 2.1
	check(Lang.resolve(perfect.status("marksman"),"de").contains("BEREIT"),"German HUD translates ultimate readiness")
	actor.free()
	enemies.free()

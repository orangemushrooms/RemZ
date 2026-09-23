# Special mechanics of the eight expansion weapons: barrel heat, rotary spin-up, a freeze that
# builds up hit by hit, burning flares, graviton area damage and the lever action's cycling.
#
# Design rules this file obeys, all of them learned the hard way in this codebase:
#   * Nothing is stored in state[id].def - that dictionary is replaced wholesale on every mod
#     change (weapons.gd equip_mod) and on every host snapshot. Runtime values live in state[id].
#   * No new status, explosion, muzzle flash or tracer system. Burning and freezing go through
#     rare_market (which owns the particles, the label, the kill attribution and the co-op
#     snapshot), the blast borrows Grenade.explosion_visuals, the flash colour goes through
#     WeaponEffects.MODES.
#   * Overheating is not a second ammunition system: venting sets state.reloading, so the HUD bar,
#     the co-op snapshot, autorefill, the shop's refill quote and balance_report keep working.
#   * Every visual, light and sound is guarded by "not w.server_proxy" - a host simulating a
#     teammate's weapon has no view model, no bounds and no viewport.
#   * Damage, status effects and the blast only ever run on the host; clients predict ammunition,
#     heat, spin and everything audiovisual, and the host corrects them 10x per second.
class_name WeaponSpecials
extends Node

const Grenade = preload("res://scripts/grenade.gd")
const MAX_FLARES := 4

var game: Node
# The weapon table, handed over by Weapons.setup(). Naming the Weapons class here instead would
# close the dependency circle weapons.gd -> weapon_specials.gd -> weapons.gd, which Godot rejects.
static var _defs: Dictionary = {}
var _chill: Dictionary = {}      # Zombie -> float 0..1, the freeze that is still building up
var _flares: Array[Node3D] = []
var _loop: AudioStreamPlayer     # the minigun motor, one voice that never gets cut off
var _loop_gain := 0.0
var _spinning_up := false

static func for_scene(scene: Node, defs: Dictionary = {}) -> WeaponSpecials:
	if not defs.is_empty(): _defs = defs
	if scene == null: return null
	var found: WeaponSpecials = scene.get_node_or_null("WeaponSpecials")
	if found: return found
	var made := WeaponSpecials.new()
	made.name = "WeaponSpecials"
	made.game = scene
	scene.add_child(made)
	return made

# The tuning block of a weapon, always read from the base table: Mods.definition() copies it, but
# reading it from DEFS keeps a mod from ever changing what kind of weapon this is.
static func spec(id: String) -> Dictionary:
	return _defs.get(id, {}).get("special", {})

static func weapon_def(id: String) -> Dictionary:
	return _defs.get(id, {})

static func kind(id: String) -> String:
	return str(spec(id).get("kind", ""))

# ---------------------------------------------------------------- fire gates

# The only hard block: a plasma rifle whose barrel is glowing. The lock hangs on the heat itself,
# not on state.reloading - that value is cleared by every weapon switch (weapons.gd set_weapon) and
# by a teammate's fire command on the host, which would otherwise cancel the vent for free. Once
# locked it stays locked until the barrel is nearly cold again (hysteresis), so switching away and
# back changes nothing.
func blocks_fire(w, id: String) -> bool:
	if kind(id) != "heat": return false
	var st: Dictionary = w.state[id]
	# Out of charge with a cold barrel: vent anyway, or the weapon has no way back at all.
	if int(st.get("ammo", 0)) <= 0 and int(st.get("reserve", 0)) > 0 and float(st.get("reloading", 0.0)) <= 0.0:
		_vent(w, id, st)
		return true
	var heat := float(st.get("heat", 0.0))
	if bool(st.get("vent", false)):
		if heat > float(spec(id).get("cold", 0.15)): return true
		st["vent"] = false
		return false
	return heat >= 1.0

# The minigun's barrels have to come up to speed. This multiplies the shot interval instead of
# blocking the trigger, so the first pull still fires (just slowly) - a block would break the
# "one try_fire, one flash" contract of tests/weapon_effects.gd.
func rate_multiplier(w, id: String) -> float:
	var s := spec(id)
	if str(s.get("kind", "")) != "spin": return 1.0
	return lerpf(float(s.get("penalty", 3.2)), 1.0, float(w.state[id].get("spin", 0.0)))

# R on an overheating weapon dumps the heat early instead of doing nothing: the reload bar, the
# scope exit and the co-op snapshot all keep behaving normally. A cold one simply swaps a cell.
func manual_vent(w, id: String) -> bool:
	if kind(id) != "heat": return false
	var st: Dictionary = w.state[id]
	if bool(st.get("vent", false)): return true   # already venting: swallow the key, do not restart
	if float(st.get("reloading", 0.0)) > 0.0 or float(st.get("heat", 0.0)) <= 0.02: return false
	_vent(w, id, st)
	return true

# ---------------------------------------------------------------- per shot (host and client)

func on_shot(w, id: String, muzzle_world: Vector3, direction: Vector3) -> void:
	var s := spec(id)
	var st: Dictionary = w.state[id]
	match str(s.get("kind", "")):
		"heat":
			st["heat"] = minf(1.0, float(st.get("heat", 0.0)) + float(s.get("per_shot", 0.17)))
			st["idle"] = 0.0
			if float(st["heat"]) >= 1.0: _vent(w, id, st)
		"spin":
			st["spin_idle"] = 0.0
		"cycle":
			# The lever is thrown a moment after the shot, not with it.
			st["cycle_t"] = float(st["def"]["rate"]) * float(s.get("at", 0.45))
			if not w.server_proxy: w._model_velocity.y += float(s.get("roll", 0.9))
		"blast":
			if not w.server_proxy: Sfx.play(w, str(s.get("charge_sfx", "graviton_charge")), -14.0)
		"flare":
			_launch_flare(w, id, muzzle_world, direction)

func _vent(w, id: String, st: Dictionary) -> void:
	# Venting reuses the reload machinery: HUD bar, co-op snapshot and refill all keep working.
	# "vent" is the authoritative flag; state.reloading is only the visible countdown.
	# The vent has a floor: stacked reload bonuses (training, morel, raven feather) must not shrink
	# the only drawback this weapon has from 3.6 s to 0.6 s.
	var s := spec(id)
	var base := float(st["def"]["reload"])
	var bar := base * clampf(float(w.effective_reload_mul()), float(s.get("vent_floor", 0.6)), 1.2)
	# The lock hangs on the heat, the bar on this number: without the second term the trigger would
	# stay dead for up to two more seconds after the bar had emptied, with nothing on screen saying so.
	var physical := float(s.get("idle", 0.6)) + (float(st.get("heat", 1.0)) - float(s.get("cold", 0.15))) / maxf(0.01, float(s.get("cool", 0.22)))
	st["reloading"] = maxf(bar, physical)
	st["vent"] = true
	# Cells still in the weapon go back into the pack; venting costs time, not ammunition. No clamp
	# against reserve_limit here: a full weapon carries mag + limit, and the reload that ends the
	# vent takes the magazine straight back out again.
	st["reserve"] = int(st.get("reserve", 0)) + int(st.get("ammo", 0))
	st["ammo"] = 0
	if not w.server_proxy: Sfx.play(w, str(spec(id).get("vent_sfx", "plasma_vent")), -7.0)

# Weapons that colour their own muzzle flash (energy weapons, the flare). Their own colour wins:
# a weapon with an "element" never consumes the bought rounds (weapons.gd), so showing their colour
# would promise an effect that never happens. Static, because the co-op avatar needs the same
# answer without a Weapons instance (net_session.weapon_fired).
static func flash_mode(id: String, bought: String) -> String:
	var own := str(weapon_def(id).get("flash_mode", ""))
	return own if not own.is_empty() else bought

# ---------------------------------------------------------------- host only: effect on the target

func on_hit(w, id: String, z: Zombie, direction: Vector3, peer: int) -> void:
	if z == null or not z.alive: return
	var element := str(weapon_def(id).get("element", ""))
	var s := spec(id)
	match str(s.get("kind", "")):
		"chill":
			var frozen := z.rare_status.contains("frost")
			if frozen:
				# Brittle: a frozen body takes more from the same burst.
				var bonus := float(s.get("brittle_mul", 1.3)) - 1.0
				if bonus > 0.0: z.damage(float(w.state[id].def.damage) * w.effective_damage_mul() * bonus, direction)
			chill(z, float(s.get("per_hit", 0.15)) * (float(s.get("titan_scale", 0.4)) if Zombie.is_boss_kind(z.net_kind) else 1.0), peer, id)
		_:
			if not element.is_empty(): ignite(z, element, float(s.get("burn_time", 3.0)), peer, id)

# Where a shot ends up, whether or not it hit an actor: the graviton's blast goes off here.
func on_impact(w, id: String, point: Vector3, peer: int) -> void:
	if str(kind(id)) != "blast": return
	detonate(w, id, point, peer)

func detonate(w, id: String, point: Vector3, peer: int) -> void:
	if NetSession.is_client():
		blast_visuals(game if game else w.get_tree().current_scene, point)
		return
	var s := spec(id)
	var radius := float(s.get("radius", 6.0))
	# Deliberately NOT scaled by effective_damage_mul: at the damage ceiling (training x1.60, fly
	# agaric x2.0, ember x1.15 = x3.68) a single cell would otherwise do close to 5700 damage.
	var damage: float = float(s.get("damage", 400.0))
	var edge := float(s.get("edge", 0.25))
	var scene: Node = game if game else w.get_tree().current_scene
	if scene == null: return
	if scene.hunting: scene.hunting.blast(point, radius, damage, peer)
	var titan_bonus := float(weapon_def(id).get("titan_multiplier", 1.0))
	for node in w.zombies_root.get_children():
		var z := node as Zombie
		if z == null or not z.alive: continue
		var distance := z.global_position.distance_to(point)
		if distance >= radius: continue
		if not _visible_from(w, point, z.global_position + Vector3.UP): continue
		var falloff := 1.0 - (1.0 - edge) * (distance / radius)
		z.last_headshot = false
		z.killer_weapon = id
		z.killer_peer = peer
		z.damage(damage * falloff * (titan_bonus if Zombie.is_boss_kind(z.net_kind) else 1.0), (z.global_position - point).normalized())
	# The shooter is not immune to their own gravity well.
	var shooter = w.player
	if is_instance_valid(shooter) and shooter.alive:
		var own: float = shooter.global_position.distance_to(point)
		var own_radius := radius * float(s.get("self_share", 0.7))   # the grenade rule: 70 % of the blast
		if own < own_radius and _visible_from(w, point, shooter.global_position + Vector3.UP):
			shooter.damage(float(s.get("self_damage", 60.0)) * (1.0 - own / own_radius), point)
	if NetSession.enabled and NetSession.is_host(): NetSession.blast(point)
	else: blast_visuals(scene, point)

# Optics and sound of the blast, on every peer. Grenade owns this look already.
static func blast_visuals(scene: Node, point: Vector3) -> void:
	if scene == null: return
	Grenade.explosion_visuals(scene, point)
	Sfx.play_at(scene, "graviton_impact", point, -4.0)
	# The same shove in the view that a grenade gives, for whoever is close enough to feel it.
	var viewer = scene.player if "player" in scene else null
	if is_instance_valid(viewer) and viewer.global_position.distance_to(point) < 14.0:
		viewer.wobble = maxf(viewer.wobble, 0.55)

func _visible_from(w, from: Vector3, to: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = w.get_parent().get_world_3d().direct_space_state
	# Layer 1 is the world, layer 8 barricades and towers: the same cover a grenade respects.
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8)
	return space.intersect_ray(query).is_empty()

# ---------------------------------------------------------------- status effects (host only)

# Set a body on fire through the existing rare-round status, then stretch the burn: a flare sticks
# in the wound far longer than an incendiary bullet does.
func ignite(z: Zombie, element: String, seconds: float, peer: int, weapon: String) -> void:
	var market = _market()
	if market == null or element.is_empty(): return
	market.hit(z, element, peer, weapon)
	if not market.statuses.has(z): return
	var status: Dictionary = market.statuses[z]
	if element == "fire":
		status["burn"] = maxf(float(status.get("burn", 0.0)), seconds)
	else:
		status["frost"] = maxf(float(status.get("frost", 0.0)), seconds)

# Frost that builds up: every hit chills a little, the body visibly slows down, and only a full
# meter freezes it solid through the normal frost status (label, shader, particles, snapshot).
func chill(z: Zombie, amount: float, peer: int, weapon: String) -> void:
	var market = _market()
	if market == null: return
	var value: float = float(_chill.get(z, 0.0)) + amount
	if value >= 1.0:
		var s := spec(weapon)
		_chill[z] = float(s.get("after_freeze", 0.45))
		ignite(z, "frost", float(s.get("freeze_time", 3.0)), peer, weapon)
		Sfx.play_at(game if game else z, "cryo_freeze", z.global_position + Vector3.UP, -8.0)
		return
	_chill[z] = value
	# Do not fight the real frost status for the same multiplier.
	if not z.rare_status.contains("frost"):
		z.frost_mul = lerpf(1.0, float(spec(weapon).get("chill_slow", 0.78)), value)

func _market():
	var scene: Node = game if game else get_parent()
	if scene == null or not ("progression" in scene) or scene.progression == null: return null
	return scene.progression.rare_market

# ---------------------------------------------------------------- flares

func _launch_flare(w, id: String, muzzle_world: Vector3, direction: Vector3) -> void:
	if w.server_proxy and NetSession.is_client(): return
	var flare := Flare.new()
	flare.specials = self
	flare.weapon = id
	flare.owner_peer = w.player.peer_id if is_instance_valid(w.player) else 1
	flare.authoritative = not NetSession.is_client()
	flare.config = spec(id)
	var scene: Node = game if game else w.get_tree().current_scene
	scene.add_child(flare)
	flare.launch(muzzle_world, direction)

# A burning flare lying on the ground: the only light in this game a player can place at will.
func plant_flare(point: Vector3, seconds := 8.0, range_m := 12.0, announce := false, shooter := 0) -> void:
	var scene: Node = game if game else get_parent()
	if scene == null: return
	# The shooter already placed this light locally when they predicted the shot.
	if announce and NetSession.enabled and NetSession.is_host(): NetSession.flare(point, shooter)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.52, 0.18)
	light.omni_range = range_m
	light.light_energy = 6.0
	light.shadow_enabled = false
	light.position = point + Vector3.UP * 0.25
	scene.add_child(light)
	var sparks := preload("res://scripts/elemental_effects.gd").particles("fire", 0.25, 0.5)
	sparks.position = point + Vector3.UP * 0.12
	scene.add_child(sparks)
	sparks.emitting = true
	light.set_meta("age", 0.0)
	light.set_meta("life", seconds)
	light.set_meta("sparks", sparks)
	_flares.append(light)
	while _flares.size() > MAX_FLARES:
		var oldest: Node3D = _flares.pop_front()
		if is_instance_valid(oldest):
			var old_sparks = oldest.get_meta("sparks", null)
			if is_instance_valid(old_sparks): old_sparks.queue_free()
			oldest.queue_free()

# ---------------------------------------------------------------- per frame

# Called from weapons._tick_ammo, so a stowed weapon cools down too.
func tick(w, delta: float) -> void:
	for id: String in w.state:
		var s := spec(id)
		if s.is_empty(): continue
		var st: Dictionary = w.state[id]
		match str(s.get("kind", "")):
			"heat":
				if id != w.current and float(st.get("reloading", 0.0)) > 0.0:
					st["reloading"] = maxf(0.0, float(st["reloading"]) - delta)
				if bool(st.get("vent", false)) and float(st.get("reloading", 0.0)) <= 0.0:
					# The bar has run out, so the weapon is cool by definition: the player may fire.
					st["vent"] = false
					st["heat"] = minf(float(st.get("heat", 0.0)), float(s.get("cold", 0.15)))
				st["idle"] = float(st.get("idle", 9.0)) + delta
				if float(st["idle"]) >= float(s.get("idle", 0.6)):
					st["heat"] = maxf(0.0, float(st.get("heat", 0.0)) - float(s.get("cool", 0.22)) * delta)
					# An idle cell recharges from the pack: the rifle never needs a magazine change.
					if float(st["reloading"]) <= 0.0 and int(st["ammo"]) < int(st["def"]["mag"]) and int(st["reserve"]) > 0:
						st["regen"] = float(st.get("regen", 0.0)) + float(s.get("regen", 0.55)) * delta
						while float(st["regen"]) >= 1.0 and int(st["ammo"]) < int(st["def"]["mag"]) and int(st["reserve"]) > 0:
							st["regen"] = float(st["regen"]) - 1.0
							st["ammo"] = int(st["ammo"]) + 1
							st["reserve"] = int(st["reserve"]) - 1
							if not w.server_proxy: w.update_hud()
			"spin":
				# Measured in seconds, and driven by the shots themselves: the host runs a teammate's
				# weapon as a proxy where no key is held, so asking Input here would leave them stuck
				# at a third of the rate of fire forever.
				var idle: float = float(st.get("spin_idle", 9.0)) + delta
				st["spin_idle"] = idle
				if idle <= float(s.get("hold", 0.25)):
					st["spin"] = minf(1.0, float(st.get("spin", 0.0)) + delta / maxf(0.05, float(s.get("up", 0.85))))
				else:
					st["spin"] = maxf(0.0, float(st.get("spin", 0.0)) - delta / maxf(0.05, float(s.get("down", 0.9))))
			"cycle":
				var left := float(st.get("cycle_t", -1.0))
				if left > 0.0:
					left -= delta
					st["cycle_t"] = left
					if left <= 0.0 and not w.server_proxy and id == w.current:
						Sfx.play(w, str(s.get("sfx", "lever_cycle")), -12.0)
	if not w.server_proxy: _motor(w, delta)

# The rotary motor as one looping voice - Sfx.play would cut itself off at eighteen rounds a second.
func _motor(w, delta: float) -> void:
	var id: String = w.current
	var spinning: bool = kind(id) == "spin"
	var spin: float = float(w.state[id].get("spin", 0.0)) if spinning else 0.0
	if _loop == null:
		if not spinning or spin <= 0.01: return
		_loop = AudioStreamPlayer.new()
		var stream := Sfx.get_stream("minigun_loop")
		if stream is AudioStreamWAV:
			stream = (stream as AudioStreamWAV).duplicate()
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		_loop.stream = stream
		_loop.volume_db = -60.0
		add_child(_loop)
	# Starting and stopping are their own sounds; the loop only carries the steady whine between.
	var s := spec(id) if spinning else {}
	if spinning and spin > 0.02 and _loop_gain <= 0.02 and not _spinning_up:
		_spinning_up = true
		Sfx.play(w, str(s.get("start_sfx", "minigun_spinup")), -12.0)
	if _spinning_up and spin <= 0.01:
		_spinning_up = false
		Sfx.play(w, str(s.get("stop_sfx", "minigun_spindown")), -14.0)
	_loop_gain = move_toward(_loop_gain, spin, delta * (3.5 if spin > _loop_gain else 1.6))
	if _loop_gain <= 0.01:
		if _loop.playing: _loop.stop()
		return
	if not _loop.playing: _loop.play()
	_loop.volume_db = -16.0 + linear_to_db(maxf(0.02, _loop_gain))
	_loop.pitch_scale = 0.72 + 0.4 * _loop_gain

func _physics_process(delta: float) -> void:
	# The chill meter melts away, and spent flares burn out. Host and solo only - a client is told
	# about frost through the zombie snapshot.
	if not NetSession.is_client():
		for z in _chill.keys():
			if not is_instance_valid(z) or not z.alive:
				_chill.erase(z)
				continue
			var value := maxf(0.0, float(_chill[z]) - delta * 0.35)
			if value <= 0.0:
				_chill.erase(z)
				if not z.rare_status.contains("frost"): z.frost_mul = 1.0
				continue
			_chill[z] = value
			if not z.rare_status.contains("frost"): z.frost_mul = lerpf(1.0, 0.78, value)
	for light in _flares.duplicate():
		if not is_instance_valid(light):
			_flares.erase(light)
			continue
		var age := float(light.get_meta("age", 0.0)) + delta
		var life := float(light.get_meta("life", 8.0))
		light.set_meta("age", age)
		# Steady while it burns, guttering out over the last two seconds.
		var fade := clampf((life - age) / 2.0, 0.0, 1.0)
		(light as OmniLight3D).light_energy = (5.5 + sin(age * 11.0) * 0.6) * fade
		if age >= life:
			var sparks = light.get_meta("sparks", null)
			if is_instance_valid(sparks): sparks.queue_free()
			_flares.erase(light)
			light.queue_free()

# ---------------------------------------------------------------- HUD and movement

# The second gauge under the reload bar. Empty text means the weapon has nothing to show.
func hud_state(w, id: String) -> Dictionary:
	var s := spec(id)
	var st: Dictionary = w.state.get(id, {})
	match str(s.get("kind", "")):
		"heat":
			var heat := float(st.get("heat", 0.0))
			var venting := bool(st.get("vent", false))
			var cells := "%d Zellen" % int(st.get("ammo", 0))
			return {"text": "ENTLÜFTET …" if venting else "Hitze · " + cells, "value": 1.0 if venting else heat,
				"colour": Color(1.0, 0.45, 0.15) if venting or heat > 0.7 else Color(0.35, 0.85, 1.0)}
		"spin":
			var spin: float = float(st.get("spin", 0.0))
			if spin <= 0.01: return {}
			return {"text": "Läufe %d %%" % roundi(spin * 100.0), "value": spin, "colour": Color(1.0, 0.78, 0.3)}
		"blast":
			var loaded := int(st.get("ammo", 0))
			var spare := int(st.get("reserve", 0))
			return {"text": "Energiezellen %d + %d" % [loaded, spare], "value": float(loaded + spare) / maxf(1.0, float(int(st["def"]["mag"]) + w.reserve_limit(id))),
				"colour": Color(0.72, 0.45, 1.0)}
	return {}

# The minigun is heavy: carrying it is slow, firing it roots you almost in place.
func movement_multiplier(w) -> float:
	var d: Dictionary = weapon_def(w.current)
	if not d.has("move_mul"): return 1.0
	var spinning: bool = float(w.state[w.current].get("spin", 0.0)) > 0.25
	return float(d.get("move_mul_spun", d.move_mul)) if spinning else float(d.move_mul)

# ---------------------------------------------------------------- network

# Heat and spin ride along in the ammunition snapshot; without them a client could pretend its
# barrel never got hot, and a teammate's minigun would look like it fires at full rate instantly.
# Only the two weapons that really carry a value, and only while it is not zero: six weapons with
# a "special" block would otherwise pad every snapshot with a dozen zeroes.
static func net_state(w, id: String) -> Array:
	var st: Dictionary = w.state.get(id, {})
	match kind(id):
		"heat":
			var heat := float(st.get("heat", 0.0))
			return [snappedf(heat, 0.01), 0.0] if heat > 0.0 or bool(st.get("vent", false)) else []
		"spin":
			var spin := float(st.get("spin", 0.0))
			return [0.0, snappedf(spin, 0.01)] if spin > 0.0 else []
	return []

func apply_net_state(w, id: String, values: Array) -> void:
	if values.size() < 2 or not w.state.has(id): return
	match kind(id):
		"heat": w.state[id]["heat"] = float(values[0])
		"spin": w.state[id]["spin"] = float(values[1])

func on_switch(w, from_id: String, to_id: String) -> void:
	# One instance serves the local weapon and every proxy the host simulates: only the local
	# player's real weapon change may silence the motor.
	if w.server_proxy or from_id == to_id: return
	if _loop and _loop.playing:
		_loop.stop()
		_loop_gain = 0.0
	_spinning_up = false

# ---------------------------------------------------------------- flare projectile

static var _star: SphereMesh

# One glowing star shared by every flare. A StandardMaterial3D made per shot was the flare pistol's
# hitch: by the next trigger pull the last star had burnt out, Godot had freed the shader generated
# for it and compiled it again - 30 to 40 ms and a handful of pipelines on every single shot.
static func star_mesh() -> SphereMesh:
	if _star == null:
		_star = SphereMesh.new()
		_star.radius = 0.055
		_star.height = 0.11
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.75, 0.35)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.6, 0.2)
		material.emission_energy_multiplier = 6.0
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_star.material = material
	return _star

# A slow burning star, not a bullet: it arcs, it lights the ground it passes and it sets fire to
# whatever it touches. Swept ray per step so it can never tunnel through a zombie.
class Flare extends Node3D:
	var specials: WeaponSpecials
	var weapon := "flare_pistol"
	var owner_peer := 1
	var authoritative := true
	var config := {}
	var velocity := Vector3.ZERO
	var age := 0.0
	var light: OmniLight3D
	var _done := false

	func launch(from: Vector3, direction: Vector3) -> void:
		global_position = from
		velocity = direction.normalized() * float(config.get("speed", 46.0)) + Vector3.UP * 1.5
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.omni_range = float(config.get("light_range", 12.0))
		light.light_energy = 5.0
		light.shadow_enabled = false
		add_child(light)
		var mesh := MeshInstance3D.new()
		mesh.mesh = WeaponSpecials.star_mesh()
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		var trail = preload("res://scripts/elemental_effects.gd").particles("fire", 0.1, 0.3)
		add_child(trail)
		trail.emitting = true

	func _physics_process(delta: float) -> void:
		if _done: return
		age += delta
		velocity.y -= 9.0 * delta
		var step := velocity * delta
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, Zombie.SHOT_MASK | 1)
		query.collide_with_areas = true   # the hit boxes are areas, invisible to a default ray
		query.hit_from_inside = true
		if is_instance_valid(specials) and is_instance_valid(specials.game) and "player" in specials.game:
			query.exclude = [specials.game.player.get_rid()]
		var hit := space.intersect_ray(query)
		if hit:
			_impact(hit.get("position", global_position), Zombie.from_hit(hit))
			return
		global_position += step
		light.light_energy = 5.0 + sin(age * 25.0) * 0.8
		if age > 6.0: _impact(global_position, null)

	func _impact(point: Vector3, z: Zombie) -> void:
		_done = true
		if authoritative and is_instance_valid(specials):
			# The shot itself already hit and ignited this body (weapons.gd deals the weapon's own
			# damage and its "element"); the star only adds something when it is configured to.
			if z != null and z.alive and float(config.get("impact", 0.0)) > 0.0:
				z.last_headshot = false
				z.killer_weapon = weapon
				z.killer_peer = owner_peer
				z.damage(float(config.get("impact", 45.0)), velocity.normalized())
				specials.ignite(z, "fire", float(config.get("burn_time", 4.0)), owner_peer, weapon)
			# A splash of fire around the impact so a near miss still hurts the pack.
			var radius := float(config.get("radius", 3.5))
			var splash := float(config.get("splash", 20.0))
			var splash_ignites := bool(config.get("splash_ignites", false))
			var root: Node3D = specials.game.zombies_root if "zombies_root" in specials.game else null
			if root:
				for node in root.get_children():
					var other := node as Zombie
					if other == null or not other.alive or other == z: continue
					var distance := other.global_position.distance_to(point)
					if distance > radius: continue
					other.last_headshot = false
					other.killer_weapon = weapon
					other.killer_peer = owner_peer
					other.damage(splash * (1.0 - distance / radius), (other.global_position - point).normalized())
					if splash_ignites:
						specials.ignite(other, "fire", float(config.get("burn_time", 4.0)) * 0.6, owner_peer, weapon)
		if is_instance_valid(specials):
			specials.plant_flare(point, float(config.get("flare_life", 8.0)), float(config.get("light_range", 12.0)), authoritative, owner_peer)
		queue_free()

# Host-owned wheels: 10 R per spin, delayed payout, replicated animation and a weighted prize table.
# The 24 painted sectors represent categories; cash, plants, drinks and every traded weapon are prizes.
class_name FortuneWheels
extends Node3D

const COST := 10
const REACH := 1.9
const SPIN_SECONDS := Vector2(5.8, 7.6)
const TURNS := Vector2i(3, 5)
const WEAPON_TOP := 0.013
const WEAPON_EXPONENT := 1.4
const WEAPON_BASE_PRICE := 180.0
const WEAPON_DUPLICATE_MAGS := 3
const AMMO_MAGS := 2
const MEDKIT_HEAL := 60.0
const NEAR_MISS := 0.18      # share of the blanks that stop on a segment beside the jackpot
const TIERS := ["weapon_common", "weapon_rare", "weapon_epic", "weapon_legendary"]
const TIER_PRICE := [500, 900, 2000]   # shop price limits between the tiers
# Everything but the weapons and the blank; "nothing" takes what is left (about 34 %).
const CHANCES := {"mushroom": 0.16, "flower": 0.075, "potion": 0.045, "ammo": 0.13, "free_spin": 0.08, "cash25": 0.03, "cash100": 0.015, "cash500": 0.004, "cash1000": 0.001, "grenade": 0.04, "medkit": 0.04}
# Clockwise from the top as painted; the jackpot (23) sits between a blank and the 1000 R segment.
const SEGMENTS := ["cash1000", "nothing", "flower", "ammo", "cash500", "weapon_common", "mushroom", "free_spin",
	"nothing", "grenade", "potion", "weapon_rare", "nothing", "ammo", "cash25", "flower",
	"weapon_epic", "cash100", "medkit", "mushroom", "free_spin", "potion", "nothing", "weapon_legendary"]
# Painted look per kind: colour (vintage fairground paint), icon from assets/ui/items, text (translated).
# "gold" = gold leaf (metallic).
const LOOK := {
	"nothing": {"color": Color(0.53, 0.1, 0.09), "text": "NOTHING", "icon": ""},
	"mushroom": {"color": Color(0.9, 0.84, 0.69), "text": "", "icon": "steinpilz"},
	"flower": {"color": Color(0.38, 0.49, 0.3), "text": "", "icon": "golden_yarrow"},
	"potion": {"color": Color(0.43, 0.27, 0.52), "text": "", "icon": "brew_rose"},
	"cash500": {"color": Color(0.82, 0.63, 0.26), "text": "500 R", "icon": ""},
	"cash1000": {"color": Color(0.95, 0.74, 0.3), "text": "1000 R", "icon": "", "gold": true},
	"ammo": {"color": Color(0.26, 0.33, 0.2), "text": "AMMO", "icon": "ammo"},
	"free_spin": {"color": Color(0.14, 0.43, 0.42), "text": "FREE SPIN", "icon": ""},
	"cash25": {"color": Color(0.8, 0.56, 0.15), "text": "25 R", "icon": ""},
	"cash100": {"color": Color(0.83, 0.36, 0.1), "text": "100 R", "icon": ""},
	"grenade": {"color": Color(0.2, 0.22, 0.16), "text": "", "icon": "grenade"},
	"medkit": {"color": Color(0.93, 0.91, 0.86), "text": "", "icon": "medicine"},
	"weapon_common": {"color": Color(0.2, 0.47, 0.25), "text": "WEAPON", "icon": "shotgun"},
	"weapon_rare": {"color": Color(0.16, 0.32, 0.62), "text": "RARE", "icon": "ak47"},
	"weapon_epic": {"color": Color(0.4, 0.2, 0.56), "text": "EPIC", "icon": "cryo_smg"},
	"weapon_legendary": {"color": Color(0.95, 0.72, 0.25), "text": "LEGENDARY", "icon": "minigun", "gold": true},
}

var main: Node
var wheels: Array[FortuneWheel] = []
var pending: Array = []       # per wheel: {} or {"peer", "result", "left"} (host / solo)
var rng := RandomNumberGenerator.new()
var serial := 0
var spins := 0                # statistics / tests
var last_result: Dictionary = {}
var last_message := ""
var sign_bulbs: Array[MeshInstance3D] = []
var _bulb_on: StandardMaterial3D
var _bulb_off: StandardMaterial3D
var _chase_t := 0.0

# ------------------------------------------------------------------ table
static func weapon_pool() -> Array:
	var ids: Array = []
	for id in Progression.GOODS:
		if Weapons.DEFS.has(id): ids.append(id)
	return ids

static func weapon_chance(id: String) -> float:
	return WEAPON_TOP * pow(WEAPON_BASE_PRICE / float(Progression.GOODS[id].price), WEAPON_EXPONENT)

static func tier_of(id: String) -> String:
	var price := int(Progression.GOODS[id].price)
	for i in TIER_PRICE.size():
		if price < TIER_PRICE[i]: return TIERS[i]
	return TIERS[TIERS.size() - 1]

# Every outcome with its chance: "weapon:<id>" per weapon, the other kinds, "nothing" = the rest.
static func table() -> Dictionary:
	var odds := {}
	var used := 0.0
	for id in weapon_pool():
		odds["weapon:" + id] = weapon_chance(id)
		used += odds["weapon:" + id]
	for kind in CHANCES:
		odds[kind] = float(CHANCES[kind])
		used += float(CHANCES[kind])
	odds["nothing"] = maxf(0.0, 1.0 - used)
	return odds

static func roll(random: RandomNumberGenerator) -> Dictionary:
	var odds := table()
	var r := random.randf()
	for key: String in odds:
		r -= float(odds[key])
		if r < 0.0:
			if key.begins_with("weapon:"):
				var id := key.trim_prefix("weapon:")
				return {"kind": tier_of(id), "weapon": id}
			return {"kind": key}
	return {"kind": "nothing"}

# Which painted segment the wheel stops on for a result, and where inside it (0..1 in the order the
# segments pass the flapper). A blank sometimes stops just past or just short of the jackpot.
func landing(kind: String) -> Vector2:
	var jackpot := SEGMENTS.find("weapon_legendary")
	if kind == "nothing" and rng.randf() < NEAR_MISS:
		var before := posmod(jackpot - 1, SEGMENTS.size())
		if SEGMENTS[before] == "nothing": return Vector2(before, rng.randf_range(0.9, 0.97))
	var options: Array[int] = []
	for i in SEGMENTS.size():
		if SEGMENTS[i] == kind: options.append(i)
	if options.is_empty(): options.append(SEGMENTS.find("nothing"))
	return Vector2(options[rng.randi_range(0, options.size() - 1)], rng.randf_range(0.18, 0.82))

# ------------------------------------------------------------------ world
func setup(owner_main: Node, shed: Node3D, hx: float, hz: float) -> void:
	main = owner_main
	name = "FortuneWheels"
	# the disc turns and the bulbs switch: RenderOptimizer must not fold any of it into a static batch
	add_to_group("render_dynamic")
	rng.randomize()
	shed.add_child(self)
	# against the north gable wall, facing into the shed (the door is in the east face near the south end)
	for x: float in [-1.55, 1.55]:
		var wheel := FortuneWheel.new()
		add_child(wheel)
		wheel.position = Vector3(x, 0.0, -hz + 0.72)
		wheel.build(self, wheels.size())
		wheels.append(wheel)
		pending.append({})
	_build_booth(hz)
	_build_sign(hz)
	_settle.call_deferred()

# The shed's floor is the terrain / slab under it; drop everything onto what the ray hits.
func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var top := global_transform * Vector3(0, 3.0, 0)
	var q := PhysicsRayQueryParameters3D.create(top, top - Vector3(0, 6, 0), 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty(): position.y = (get_parent() as Node3D).to_local(hit.position).y

func _build_booth(hz: float) -> void:
	var booth: Node3D = main._prop(self, "fortune_prize_counter", 1.5, "x", Vector3(0, 0, -hz + 0.45), 0.0) if main.has_method("_prop") else null
	if booth == null:
		var counter := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.5, 1.0, 0.6)
		counter.mesh = box
		counter.material_override = Foliage.pbr("planks", 0.8, Color(0.4, 0.3, 0.2))
		counter.position = Vector3(0, 0.5, -hz + 0.45)
		add_child(counter)
	# a few prizes on the booth's shelf: a mushroom basket look, a grenade, a medkit - just icons as cards
	var shelf_y := 1.0
	var items := ["steinpilz", "grenade", "medicine", "ammo"]
	for i in items.size():
		var card := Sprite3D.new()
		card.texture = ItemIcons.texture(items[i])
		card.pixel_size = 0.2 / maxf(1.0, float(card.texture.get_width()))
		card.shaded = true
		card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		card.position = Vector3(-0.45 + i * 0.3, shelf_y + 0.12, -hz + 0.42)
		card.rotation.y = randf_range(-0.2, 0.2)
		add_child(card)

func _build_sign(hz: float) -> void:
	var board := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.6, 0.72, 0.06)
	board.mesh = box
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.2, 0.05, 0.05)
	wood.roughness = 0.55
	board.material_override = wood
	board.position = Vector3(0, 2.72, -hz + 0.1)
	add_child(board)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.78, 0.6, 0.3)
	trim.metallic = 1.0
	trim.roughness = 0.35
	for y: float in [-0.39, 0.39]:
		var bar := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(4.7, 0.05, 0.08)
		bar.mesh = b
		bar.material_override = trim
		bar.position = board.position + Vector3(0, y, 0.01)
		add_child(bar)
	var title := Label3D.new()
	title.text = "WHEEL OF FORTUNE"
	title.font_size = 96
	title.pixel_size = 0.0034
	title.outline_size = 10
	title.modulate = Color(1.0, 0.86, 0.45)
	title.outline_modulate = Color(0.25, 0.05, 0.0)
	title.shaded = true
	title.position = board.position + Vector3(0, 0.08, 0.035)
	add_child(title)
	var price := Label3D.new()
	price.text = Lang.t("%d R · WEAPONS · PLANTS · POTIONS · CASH", [COST])
	price.font_size = 40
	price.pixel_size = 0.0034
	price.outline_size = 6
	price.modulate = Color(0.98, 0.93, 0.82)
	price.outline_modulate = Color(0.1, 0.02, 0.0)
	price.shaded = true
	price.position = board.position + Vector3(0, -0.2, 0.035)
	add_child(price)
	# marquee bulbs around the board, chasing while a wheel turns
	_bulb_on = StandardMaterial3D.new()
	_bulb_on.albedo_color = Color(1.0, 0.85, 0.55)
	_bulb_on.emission_enabled = true
	_bulb_on.emission = Color(1.0, 0.72, 0.35)
	_bulb_on.emission_energy_multiplier = 4.0
	_bulb_off = StandardMaterial3D.new()
	_bulb_off.albedo_color = Color(0.7, 0.62, 0.5)
	_bulb_off.emission_enabled = true
	_bulb_off.emission = Color(1.0, 0.6, 0.3)
	_bulb_off.emission_energy_multiplier = 0.35
	_bulb_off.roughness = 0.2
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.028
	bulb_mesh.height = 0.056
	bulb_mesh.radial_segments = 10
	bulb_mesh.rings = 6
	var points: Array[Vector3] = []
	for k in 17: points.append(Vector3(-2.2 + k * 0.275, 0.3, 0.05))
	for k in 17: points.append(Vector3(2.2 - k * 0.275, -0.3, 0.05))
	for p in points:
		var bulb := MeshInstance3D.new()
		bulb.mesh = bulb_mesh
		bulb.material_override = _bulb_on
		bulb.position = board.position + p
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bulb)
		sign_bulbs.append(bulb)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.72, 0.4)
	glow.light_energy = 0.6
	glow.omni_range = 3.2
	glow.position = board.position + Vector3(0, -0.2, 0.5)
	add_child(glow)

func _process(delta: float) -> void:
	var any := false
	for wheel in wheels: any = any or wheel.spinning or wheel.flash > 0.0
	_chase_t += delta * (9.0 if any else 1.2)
	var step := int(_chase_t)
	for i in sign_bulbs.size():
		sign_bulbs[i].material_override = _bulb_on if (i + step) % 3 != 0 else _bulb_off
	if NetSession.is_client(): return
	for i in pending.size():
		if pending[i].is_empty(): continue
		pending[i].left -= delta
		if pending[i].left > 0.0: continue
		var done: Dictionary = pending[i]
		pending[i] = {}
		var p: Player = _actor(int(done.peer))
		var text := grant(p, done.result, i) if p else ""
		if p and not text.is_empty(): _tell(p, text)

func _actor(peer: int) -> Player:
	if main.player and main.player.peer_id == peer: return main.player
	if NetSession.enabled and NetSession.world: return NetSession.world.actor(peer)
	return main.player if not NetSession.enabled else null

func _tell(p: Player, text: String) -> void:
	last_message = text
	if p == main.player: main.hud.message(text, 4.5)
	elif NetSession.is_host(): NetSession.feedback(p.peer_id, "message", [text, 4.5])

# ------------------------------------------------------------------ interaction
func nearest(p: Player) -> int:
	var best := -1
	var best_d := REACH
	for i in wheels.size():
		var d := Vector2(p.global_position.x, p.global_position.z).distance_to(_flat(wheels[i].stand_point()))
		if d < best_d:
			best_d = d
			best = i
	return best

static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

func near(p: Player, index: int) -> bool:
	return index >= 0 and index < wheels.size() and Vector2(p.global_position.x, p.global_position.z).distance_to(_flat(wheels[index].stand_point())) <= REACH

func prompt(p: Player) -> String:
	if not p.alive or p.downed or p.controlling_drone or p.mounted_tower: return ""
	var i := nearest(p)
	if i < 0: return ""
	if wheels[i].spinning or not pending[i].is_empty(): return "The wheel is turning …"
	if p.score < COST: return Lang.t("Wheel of fortune · %d R per spin · not enough Rem Dollars", [COST])
	return Lang.t("[E] Spin the wheel of fortune · %d R\nWeapons, plants, potions, ammo and up to 1000 Rem Dollars", [COST])

func request_spin(p: Player) -> void:
	var i := nearest(p)
	if i < 0: return
	if NetSession.enabled: NetSession.command("fortune_spin", [i])
	else:
		var text := spin(p, i)
		if not text.is_empty(): main.hud.message(text, 3.0)

# Host / solo: pay and start a spin. An empty answer means the wheel turns; the prize follows when it stops.
func spin(p: Player, index: int) -> String:
	if NetSession.is_client(): return "The host spins the wheel."
	if index < 0 or index >= wheels.size(): return "There is no wheel here."
	if not p.alive or p.downed: return "You cannot play right now."
	if not near(p, index): return "Step up to the wheel to spin it."
	if wheels[index].spinning or not pending[index].is_empty(): return "The wheel is still turning."
	if p.score < COST: return Lang.t("Not enough Rem Dollars: %d R per spin.", [COST])
	p.add_score(-COST)
	var result := roll(rng)
	var land := landing(result.kind)
	serial += 1
	var seconds := rng.randf_range(SPIN_SECONDS.x, SPIN_SECONDS.y)
	wheels[index].start(serial, int(land.x), land.y, seconds, rng.randi_range(TURNS.x, TURNS.y), _reveal_of(result))
	pending[index] = {"peer": p.peer_id, "result": result, "left": seconds}
	spins += 1
	last_result = result
	return ""

# What the wheel shows above itself when it stops (icon id, text, tier) - for every peer.
static func _reveal_of(result: Dictionary) -> Array:
	var kind: String = result.kind
	if result.has("weapon"): return [result.weapon, Weapons.DEFS[result.weapon].name, kind]
	return ["cash" if kind.begins_with("cash") else LOOK[kind].icon, LOOK[kind].text, kind]

# Host / solo: pay out one result. Returns the text for the winner.
func grant(p: Player, result: Dictionary, wheel := -1) -> String:
	var w: Weapons = main.progression.weapon_for(p)
	var kind: String = result.kind
	match kind:
		"flower":
			var kinds: Array = main.brewing.Recipes.FLOWERS.keys()
			var flower: String = kinds[rng.randi_range(0, kinds.size() - 1)]
			for i in 3: main.brewing.add_flower(p.peer_id, flower)
			Sfx.event(main, p.peer_id, "pickup")
			return Lang.t("Won: 3 × %s · it is in your inventory.", [main.brewing.Recipes.FLOWERS[flower].name])
		"potion":
			var drinks: Dictionary = main.brewing.stock(p.peer_id).drinks
			var available: Array = []
			for id in main.brewing.Recipes.DRINKS:
				if int(drinks.get(id, 0)) < main.brewing.Recipes.DRINK_LIMIT: available.append(id)
			if available.is_empty(): return _refund(p, "Potion bag full")
			var id: String = available[rng.randi_range(0, available.size() - 1)]
			drinks[id] = int(drinks.get(id, 0)) + 1
			Sfx.event(main, p.peer_id, "pickup")
			return Lang.t("Won: %s · it is in your inventory.", [main.brewing.Recipes.DRINKS[id].name])
		"nothing":
			return "Nothing this time. The wheel creaks to a halt."
		"mushroom":
			var mushroom := Inventory.Mushrooms.choose(rng)
			var stock: Dictionary = main.progression.mushroom_stock(p)
			stock[mushroom] = int(stock.get(mushroom, 0)) + 1
			Sfx.event(main, p.peer_id, "mushroom_pickup")
			return Lang.t("Won: %s · it is in your inventory.", [Inventory.MUSHROOMS[mushroom].name])
		"ammo":
			var given := _give_ammo(w, w.ammo_weapon(), AMMO_MAGS)
			if given.is_empty(): return _refund(p, "All ammo pouches are full")
			Sfx.event(main, p.peer_id, "pickup")
			return Lang.t("Won: ammo · +%d rounds for the %s", [given[1], Weapons.DEFS[given[0]].name])
		"free_spin":
			p.add_score(COST)
			return Lang.t("Free spin! Your %d R are back.", [COST])
		"cash25", "cash100", "cash500", "cash1000":
			var amount := int(kind.trim_prefix("cash"))
			p.add_score(amount)
			Sfx.event(main, p.peer_id, "purchase")
			return Lang.t("Won: %d Rem Dollars!", [amount])
		"grenade":
			if w.grenades >= w.grenades_max: return _refund(p, "Grenade pouch full")
			w.grenades += 1
			w.update_hud()
			Sfx.event(main, p.peer_id, "pickup")
			return "Won: a grenade."
		"medkit":
			if p.hp >= p.max_hp: return _refund(p, "Health already full")
			p.hp = minf(p.max_hp, p.hp + MEDKIT_HEAL)
			p.hud.set_health(p.hp)
			Sfx.event(main, p.peer_id, "consume")
			return Lang.t("Won: a medkit · +%d health", [int(MEDKIT_HEAL)])
	if not result.has("weapon"): return "Nothing this time. The wheel creaks to a halt."
	var id: String = result.weapon
	var weapon_name: String = Weapons.DEFS[id].name
	if w.unlocked.get(id, false):
		var given := _give_ammo(w, id, WEAPON_DUPLICATE_MAGS)
		if given.is_empty(): return _refund(p, Lang.t("You already own the %s and your ammo is full", [weapon_name]))
		Sfx.event(main, p.peer_id, "pickup")
		return Lang.t("%s! You already own it: +%d rounds for the %s instead.", [weapon_name, given[1], Weapons.DEFS[given[0]].name])
	w.unlock(id)
	w.state[id].ammo = w.state[id].def.mag
	w.state[id].reserve = int(Weapons.DEFS[id].mag) * 3
	if main.achievements: main.achievements.event("weapons")
	Sfx.event(main, p.peer_id, "weapon_pickup")
	if kind in ["weapon_epic", "weapon_legendary"]: _announce(p, id)
	if Weapons.is_melee(id): return Lang.t("JACKPOT! You won the %s · select it in the inventory or with the mouse wheel", [weapon_name])
	return Lang.t("JACKPOT! You won the %s · magazine + 3 spare magazines", [weapon_name])

# Ammo for a weapon, or for the first owned firearm that still has room. Returns [weapon, rounds] or [].
func _give_ammo(w: Weapons, preferred: String, mags: int) -> Array:
	var candidates: Array = [preferred]
	for id in Weapons.ORDER:
		if not candidates.has(id): candidates.append(id)
	for id: String in candidates:
		if Weapons.is_melee(id) or not w.unlocked.get(id, false) or not w.has_ammo_space(id): continue
		var before := int(w.state[id].reserve)
		w.add_ammo(id, int(Weapons.DEFS[id].mag) * mags)
		return [id, int(w.state[id].reserve) - before]
	return []

func _refund(p: Player, reason: String) -> String:
	p.add_score(COST)
	return Lang.t("%s · your %d R are back.", [reason, COST])

# A rare gun is news for the whole camp.
func _announce(p: Player, id: String) -> void:
	if not NetSession.enabled: return
	var who: String = NetSession.roster.get(p.peer_id, "?")
	for peer in NetSession.roster:
		if int(peer) == p.peer_id: continue
		var text := Lang.t("%s won the %s at the wheel of fortune!", [Lang.raw(who), Weapons.DEFS[id].name])
		if main.player and int(peer) == main.player.peer_id: main.hud.message(text, 4.0)
		else: NetSession.feedback(int(peer), "message", [text, 4.0])

# ------------------------------------------------------------------ co-op
func snapshot() -> Array:
	var out: Array = []
	for wheel in wheels: out.append(wheel.snapshot())
	return out

func apply_snapshot(states: Array) -> void:
	for i in mini(states.size(), wheels.size()):
		if states[i] is Array: wheels[i].apply_snapshot(states[i])

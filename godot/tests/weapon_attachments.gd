extends SceneTree
# Every weapon mod model has to sit where a gunsmith would put it: a muzzle device threaded onto
# the bore with no seam and no gap, a barrel in line with it, a magazine in the well, the bolt on
# the receiver - and mounting any of them must never move the grips, the sight line or the weapon
# bounds the whole view model is built from.
#
# Headless: Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=weapon_attachments --no-intro --no-music
# Pictures: Godot.exe --path godot --script res://tests/run.gd -- --suite=weapon_attachments --render-mods --no-intro --no-music
#           -> artifacts/weapon-mods/<weapon>-<mod>.png

const Mounts = preload("res://scripts/weapon_attachments.gd")

var game: Node
var checks := 0
var failures := 0
var capture := false
var started_at := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 240000:
		push_error("ATTACHMENTS_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	capture = "--render-mods" in OS.get_cmdline_user_args()
	if capture:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1600, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.set_process_unhandled_input(false)
	game.weapons.set_process(false)
	game.day_night.set_time_hours(11)
	game.player.global_position = Map.ground_pos(-1, 13) + Vector3.UP * 0.3
	game.player.rotation.y = 0
	game.player.head.rotation.x = -0.05
	var w: Weapons = game.weapons

	# Every mod that carries a model must have its GLB and its measured geometry on disk.
	for id in Weapons.Mods.DEFS:
		if not Mounts.MOUNTS.has(id): continue
		var model: String = Mounts.MOUNTS[id].model
		check(ResourceLoader.exists("res://assets/models/%s.glb" % model), id + " ships its model " + model)
		check(WeaponMountData.PARTS.has(model), id + " has measured geometry for " + model)
	check(ResourceLoader.exists("res://assets/models/mod_mag_tube.glb"), "Tube fed weapons ship a magazine tube")

	for wid in Weapons.ORDER:
		if Weapons.is_melee(wid): continue
		w.unlock(wid)
		w.set_weapon(wid)
		w._process(0.05)
		var s: Dictionary = w.state[wid]
		var mods: WeaponAttachments = s.get("mods")
		check(mods != null, wid + " builds an attachment mount")
		if mods == null: continue
		var hands: ViewmodelHands = s.hands
		var bounds: AABB = s.bounds
		var trigger := hands.trigger_grip
		var support := hands.support_grip
		var aim: Vector3 = s.aim_position
		# muzzle_transform() answers in view model camera space; the mounts measure in the holder.
		var bare_tip := _tip_local(w, s)
		for id in Weapons.Mods.DEFS:
			if not Mounts.MOUNTS.has(id): continue
			if not Weapons.Mods.compatible(id, wid, Weapons.DEFS[wid]): continue
			var spec: Dictionary = Mounts.MOUNTS[id]
			var slot: String = Weapons.Mods.DEFS[id].slot
			w.equip_mod(wid, slot, id)
			var node: Node3D = mods.part_node(id)
			var label := "%s + %s" % [wid, id]
			var expected_visual: bool = spec.mount != "magazine" or Mounts.MAGAZINE.get(Weapons.DEFS[wid].model, "") != ""
			if not expected_visual:
				check(node == null or not node.visible, label + " shows nothing where a magazine would be wrong")
				w.equip_mod(wid, slot, "")
				continue
			check(node != null and node.visible, label + " mounts a model")
			if node == null:
				w.equip_mod(wid, slot, "")
				continue
			var front := mods.part_point(id, "front")
			var rear := mods.part_point(id, "rear")
			var radius := mods.part_radius(id)
			var length := front.distance_to(rear)
			check(radius > 0.004 and radius < 0.05, "%s keeps a believable calibre (r=%.4f m)" % [label, radius])
			# A drum is measured across its face, so its "length" is the thickness of the disc.
			var thin: bool = WeaponMountData.PARTS[Mounts.MOUNTS[id].model].shape == "disc"
			check(length > (0.006 if thin else 0.02) and length < 0.45, "%s keeps a believable length (%.3f m)" % [label, length])
			check(_inside(node, bounds, 0.9), label + " does not float away from the weapon")
			match spec.mount:
				"muzzle", "barrel":
					var axis := mods.part_axis(id)
					check(axis.dot(Vector3.FORWARD) > 0.995, "%s runs down the bore (%.4f)" % [label, axis.dot(Vector3.FORWARD)])
					check(front.z < rear.z, label + " points away from the shooter")
					# Threaded on: the rear sinks into the barrel, so there is overlap, never a gap.
					var overlap := rear.z - bare_tip.z
					check(overlap > -0.004 and overlap < length * 0.7, "%s sits flush on the muzzle (overlap %.4f m)" % [label, overlap])
					# A muzzle device threads onto the barrel; a replacement barrel legitimately
					# slides back over the old one, but must not reach the middle of the gun.
					var limit: float = bounds.position.z + (0.06 if spec.mount == "muzzle" else bounds.size.z * 0.5)
					check(rear.z < limit, label + " never grows back into the receiver")
					check(front.z < support.z, label + " stays clear of the support hand")
					var tip := _tip_local(w, s)
					check(tip.distance_to(front) < 0.012, label + " moves the muzzle flash to its own front")
					check(tip.z < bare_tip.z - 0.01, label + " pushes the muzzle forward, never backward")
				"magazine":
					if Mounts.MAGAZINE.get(Weapons.DEFS[wid].model, "") == "tube":
						# A tube magazine lies under the barrel instead of hanging out of a well.
						check(_centre(node).y < bare_tip.y, label + " runs under the barrel")
						check(absf(mods.part_axis(id).dot(Vector3.FORWARD)) > 0.99, label + " lies along the barrel")
					else:
						check(front.y > rear.y, label + " hangs feed lips up")
						check(rear.y < bounds.position.y + 0.02, label + " reaches below the weapon")
						check(absf(_centre(node).x - bounds.get_center().x) < 0.05, label + " stays in line with the magazine well")
				"bolt":
					check(_centre(node).x > bounds.get_center().x, label + " sits on the shooter's side of the receiver")
					check(_centre(node).z > bounds.position.z + 0.02, label + " stays back on the receiver, not out front")
			await shot("%s-%s" % [wid, id], node, spec.mount == "bolt")
			await shot("%s-%s-ganz" % [wid, id], null, spec.mount == "bolt")
			w.equip_mod(wid, slot, "")
			check(not node.visible, label + " disappears again when the mod is removed")
		check(hands.trigger_grip == trigger and hands.support_grip == support, wid + " keeps both grips exactly where they were")
		check(s.bounds == bounds and s.aim_position == aim, wid + " keeps its bounds and sight line")
		check(_tip_local(w, s).is_equal_approx(bare_tip), wid + " returns to its bare muzzle once the mods are off")

	# A full loadout at once: barrel plus can have to chain, not collide.
	w.set_weapon("marksman")
	w.equip_mod("marksman", "Barrel", "match_barrel")
	w.equip_mod("marksman", "Muzzle", "suppressor")
	w.equip_mod("marksman", "Magazine", "extended")
	w.equip_mod("marksman", "Bolt", "quick_action")
	var stack: WeaponAttachments = w.state.marksman.mods
	var barrel_front := stack.part_point("match_barrel", "front")
	var can_rear := stack.part_point("suppressor", "rear")
	check(can_rear.z - barrel_front.z > -0.004 and can_rear.z - barrel_front.z < 0.12, "Suppressor threads onto the match barrel, not onto the bare bore")
	check(stack.mounted().size() == 4, "All four slots show at once")
	check(_tip_local(w, w.state.marksman).distance_to(stack.part_point("suppressor", "front")) < 0.012, "The stacked muzzle sits at the front of the can")
	await shot("marksman-full", null, false)
	game.progression.rare_market.data(game.player.peer_id).ammo.frost = 20
	game.progression.rare_market.data(game.player.peer_id).mode = "frost"
	w.cur().cooldown = 0.0
	w.try_fire()
	var tracer = get_nodes_in_group("elemental_tracer").back()
	# The tracer re-anchors itself every frame, so let it settle before measuring, exactly like
	# tests/muzzle_alignment.gd does - otherwise a windowed run compares across a viewport resize.
	for i in 3:
		w._process(1.0 / 120.0)
		tracer._process(1.0 / 120.0)
	check(tracer != null and tracer.start.distance_to(w.visual_muzzle_world()) < 0.001, "A tracer starts at the suppressor, not inside the barrel")
	for node in get_nodes_in_group("elemental_tracer"): node.queue_free()

	# The host drives a client's visuals through the snapshot, so that path has to mount too.
	var snapshot_loadout := {"pistol": {"Muzzle": "ghost"}}
	w.apply_mod_snapshot({"pistol:ghost": true}, snapshot_loadout)
	check(w.state.pistol.mods.part_node("ghost") != null and w.state.pistol.mods.part_node("ghost").visible, "A co-op snapshot mounts the mod on the client")
	w.apply_mod_snapshot({}, {})
	check(not w.state.pistol.mods.part_node("ghost").visible, "Clearing the snapshot takes it off again")

	print("ATTACHMENTS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _tip_local(w: Weapons, s: Dictionary) -> Vector3:
	return (s.node as Node3D).transform.affine_inverse() * w.muzzle_transform().origin


func _bounds_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var current: Node3D = mesh
		while current != node and current != null:
			t = current.transform * t
			current = current.get_parent() as Node3D
		var b: AABB = node.transform * (t * mesh.get_aabb())
		box = b if first else box.merge(b)
		first = false
	return box

func _centre(node: Node3D) -> Vector3:
	return _bounds_of(node).get_center()

func _inside(node: Node3D, bounds: AABB, reach: float) -> bool:
	var grown := bounds.grow(reach)
	return grown.has_point(_centre(node))

func shot(label: String, part: Node3D, mirror := false) -> void:
	if not capture: return
	# Inspection pose: the weapon turned broadside and the hands out of the way. From the normal
	# first person angle the shooter's own glove hides half of what has to be judged.
	var holder: Node3D = game.weapons.cur().node
	var hands: ViewmodelHands = game.weapons.cur().hands
	var pose := holder.transform
	hands.visible = false
	# The charging handle sits on the shooter's side, so that mod is inspected from the other side.
	holder.transform = Transform3D(Basis(Vector3.UP, PI * (-0.5 if mirror else 0.5)), Vector3(0.0, -0.01, -0.62))
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("artifacts/weapon-mods")
	DirAccess.make_dir_recursive_absolute(folder)
	# The view model renders into its own SubViewport with a transparent background, so the gun
	# comes out of it alone - no HUD, no forest - which is what a fit has to be judged on.
	var w: Weapons = game.weapons
	var image := w.viewmodel.viewport.get_texture().get_image()
	image.get_region(_weapon_rect(image.get_size(), part)).save_png(folder.path_join(label + ".png"))
	holder.transform = pose
	hands.visible = true

# Frames the picture on the joint that has to be judged: the mounted part plus enough of the
# weapon around it to see whether it meets the gun cleanly. Without a part, the whole view model.
func _weapon_rect(size: Vector2i, part: Node3D) -> Rect2i:
	var w: Weapons = game.weapons
	var camera: Camera3D = w.viewmodel.camera
	var holder: Node3D = part if part else w.cur().node
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first: return Rect2i(Vector2i.ZERO, size)
	var area := Rect2(camera.unproject_position(box.position), Vector2.ZERO)
	for i in 8: area = area.expand(camera.unproject_position(box.get_endpoint(i)))
	var scale := Vector2(size) / Vector2(w.viewmodel.viewport.size)
	area = Rect2(area.position * scale, area.size * scale)
	area = area.grow(maxf(area.size.x, area.size.y) * (0.65 if part else 0.05))
	return Rect2i(area.intersection(Rect2(Vector2.ZERO, Vector2(size))))

extends SceneTree

const NEW_MODELS := ["owl_real", "tower_standard", "sandbag", "forest_key", "cash_bundle", "hut_door_leaf", "pond_trough", "mushroom_pfifferling", "mushroom_morchel", "mushroom_maronenroehrling", "mushroom_parasol", "mushroom_reizker", "mushroom_tintenpilz", "mushroom_violetter_roetelritterling", "mushroom_krause_glucke"]
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)

func run() -> void:
	for id in NEW_MODELS:
		var model := WorldModels.create(id)
		check(model != null, id + " imports as a scene")
		if not model: continue
		var bounds := Barricade._bounds(model)
		check(bounds.has_volume() and bounds.size.is_finite() and bounds.size.length() < 8.0, id + " has finite metre-scale geometry")
		var textured := true
		var vertices := 0
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
				textured = textured and material != null and material.albedo_texture != null and material.normal_enabled and material.normal_texture != null
				vertices += mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
		check(textured and vertices > 100, id + " retains textured PBR surfaces and normal maps")
		model.free()
	var world := Node3D.new()
	root.add_child(world)
	for kind in Inventory.Mushrooms.DEFS:
		var mushroom := Inventory.Mushrooms.model(kind)
		world.add_child(mushroom)
		check(mushroom.has_meta("model_id"), kind + " uses its imported species model")
	var key := ForestKey.new()
	key.key_id = "waldhuette"
	world.add_child(key)
	check(key.pickup_visual.get_child_count() == 1 and key.pickup_visual.get_child(0).get_meta("model_id", "") == "forest_key", "Key remains inside its removable pickup visual")
	for kind in ["cash", "grenade"]:
		var pickup := Pickup.new()
		pickup.setup(kind)
		world.add_child(pickup)
		check(not pickup._mesh.find_children("*", "MeshInstance3D", true, false).is_empty(), kind + " drop has imported geometry")
		pickup.set_process(false)
		pickup.set_physics_process(false)
	for width in [1.2, 2.6]:
		var door := Door.new()
		door.setup(width, 2.1, "Test", StandardMaterial3D.new())
		world.add_child(door)
		for leaf in door.leaves:
			var hinge: Node3D = leaf[0]
			var bounds := Barricade._bounds(hinge)
			check(absf(bounds.size.x - 0.10) < 0.005 and absf(bounds.size.z - (width / door.leaves.size() - 0.015)) < 0.005, "Imported door fits its moving collision slab")
			hinge.rotation.y = 1.0
			check(hinge.get_child(0).is_in_group("render_dynamic"), "Opening door keeps its model attached to its hinge")
	var tower := DefenceTower.new()
	tower.replica = true
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(tower)
	check(tower.gun.has_node("WeaponModel"), "Standard tower uses the generated twin-barrel model")
	var bags := tower.get_children().filter(func(node): return node.get_meta("model_id", "") == "sandbag")
	check(bags.size() == 6, "Tower has six cloth sandbags")
	var bird = load("res://scripts/field_bird.gd").new()
	bird.owl = true
	bird.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(bird)
	check(bird.skeleton != null and bird.wing_bones.size() == 4 and not bird.wing_bones.has(-1), "Owl imports four valid wing joints")
	bird.flap_power = 1.0
	bird.flap_phase = 0.25
	bird._advance_flap(0.0)
	bird._pose_raven()
	var first: Quaternion = bird.skeleton.get_bone_pose_rotation(bird.wing_bones[0])
	bird.flap_phase = 0.75
	bird._advance_flap(0.0)
	bird._pose_raven()
	check(first.angle_to(bird.skeleton.get_bone_pose_rotation(bird.wing_bones[0])) > 0.05, "Owl actually animates its imported mesh during flight")
	RenderOptimizer.optimize(world)
	check(is_instance_valid(key.pickup_visual.get_child(0)) and not key.pickup_visual.find_children("*", "MeshInstance3D", true, false).is_empty(), "Batching preserves removable key geometry")
	check(tower.gun.has_node("WeaponModel"), "Batching preserves rotating turret geometry")
	world.free()
	print("MISSING_MODELS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

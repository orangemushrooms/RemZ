class_name WorldNpc
extends Node3D

var npc_id := ""
var game: Node
var body: StaticBody3D
var figure: Node3D
var caption: Label3D
var quest_marker: Label3D
var anim: AnimationPlayer

func setup(id: String, main: Node) -> void:
	npc_id = id
	game = main
	add_to_group("render_dynamic")
	var spec: Dictionary = Progression.NPCS[id]
	position = Map.ground_pos(spec.pos.x, spec.pos.y)
	figure = Node3D.new()
	add_child(figure)
	var path := "res://assets/models/%s.glb" % spec.model
	if ResourceLoader.exists(path):
		var model: Node3D = load(path).instantiate()
		figure.add_child(model)
		if id in ["ranger", "wanderer"]:
			# Keep the working rig and textures; use private materials for Mara's woodland palette.
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				for surface in mesh.mesh.get_surface_count():
					var original := mesh.get_active_material(surface)
					if original is StandardMaterial3D:
						var material: StandardMaterial3D = original.duplicate()
						material.albedo_color *= Color(0.72, 0.84, 0.61)
						mesh.set_surface_override_material(surface, material)
		# Rigging already exports metres at spec.height. Bind-pose mesh AABBs do not
		# describe the deformed character and must not be used for rescaling.
		model.position = Vector3.ZERO
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			anim = players[0]
			for clip in anim.get_animation_list():
				if "idle" in clip.to_lower():
					anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
					anim.play(clip)
					break
	body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	body.add_to_group("navsource")
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	collider.shape = capsule
	collider.position.y = 0.85
	body.add_child(collider)
	caption = Label3D.new()
	caption.text = spec.name + "\n" + spec.role
	caption.position.y = float(spec.height) + 0.3
	caption.font_size = 27
	caption.pixel_size = 0.004
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.modulate = Color(0.95, 0.78, 0.46)
	caption.visibility_range_end = 12
	add_child(caption)
	quest_marker = Label3D.new()
	quest_marker.name = "QuestReady"
	quest_marker.text = "?"
	quest_marker.position.y = float(spec.height) + 0.85
	quest_marker.font_size = 64
	quest_marker.pixel_size = 0.006
	quest_marker.outline_size = 10
	quest_marker.modulate = Progression.QUEST_MARKER_COLOR
	quest_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	quest_marker.no_depth_test = true
	quest_marker.visibility_range_end = 35.0
	quest_marker.visible = false
	add_child(quest_marker)
	if id == "wanderer":
		_install_walk()
		var lantern := OmniLight3D.new()
		lantern.position = Vector3(0.4, 1.0, 0.15)
		lantern.light_color = Color(0.65, 0.3, 1.0)
		lantern.light_energy = 1.5
		lantern.omni_range = 5
		figure.add_child(lantern)
		var glow := DefenceTower.material(Color(0.6, 0.2, 0.9))
		glow.emission_enabled = true
		glow.emission = Color(0.65, 0.2, 1.0)
		DefenceTower.cylinder(figure, 0.09, 0.23, lantern.position, glow)
		_prop(figure, "ammo_crate", Vector3(0, 0.85, -0.26), 0.48)
		return
	if id == "ranger":
		# The existing campfire and benches are her meeting place, without a merchant counter.
		figure.rotation.y = PI * 0.5
		return
	# A small shop counter, folded canvas canopy and warm lamp anchor the merchant in the world.
	var wood := Foliage.pbr("planks", 0.8, Color(0.43, 0.35, 0.23))
	var steel := DefenceTower.material(Color(0.12, 0.14, 0.13), 0.65)
	var props := Node3D.new()
	add_child(props)
	_prop(props, "workbench", Vector3(0, 0, 1.05), 0.8)
	_prop(props, "ammo_crate", Vector3(-0.55, 0.82, 1.03), 0.25)
	_prop(props, "ammo_crate", Vector3(1.25, 0, 0.2), 0.48)
	var light := OmniLight3D.new()
	light.position = Vector3(0.72, 0.96, 1.1)
	light.light_color = Color(1, 0.6, 0.26)
	light.light_energy = 0.55
	light.omni_range = 4
	add_child(light)
	var lamp := DefenceTower.material(Color(0.95, 0.55, 0.18))
	lamp.emission_enabled = true
	lamp.emission = Color(0.9, 0.45, 0.12)
	DefenceTower.cylinder(props, 0.065, 0.2, light.position, lamp)
	for y in [-0.13, 0.13]: DefenceTower.cylinder(props, 0.085, 0.035, light.position + Vector3.UP * y, steel)
	for x in [-0.075, 0.075]: DefenceTower.box(props, Vector3(0.012, 0.26, 0.012), light.position + Vector3.RIGHT * x, steel)
	if id == "secret":
		var cloth := DefenceTower.material(Color(0.085, 0.105, 0.075))
		for x in [-1.35, 1.35]:
			DefenceTower.box(props, Vector3(0.09, 2.65, 0.09), Vector3(x, 1.325, -0.65), wood)
		var canopy := DefenceTower.box(props, Vector3(3.0, 0.035, 2.5), Vector3(0, 2.65, 0.1), cloth)
		canopy.rotation.x = -0.12

func _install_walk() -> void:
	# Retarget the existing survivor's walk onto this merchant's own bind pose.
	# Rotation-only tracks keep the navigation actor in charge of translation.
	if not anim: return
	var skeleton: Skeleton3D = figure.find_children("*", "Skeleton3D", true, false)[0]
	var donor := (load("res://assets/models/player_survivor_v2.glb") as PackedScene).instantiate()
	var source: AnimationPlayer = donor.find_children("*", "AnimationPlayer", true, false)[0]
	var source_skeleton: Skeleton3D = donor.find_children("*", "Skeleton3D", true, false)[0]
	var original := source.get_animation("walk")
	var walk := Animation.new()
	walk.length = original.length
	walk.loop_mode = Animation.LOOP_LINEAR
	var root_node := anim.get_node(anim.root_node)
	for track in original.get_track_count():
		if original.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
		var track_path := original.track_get_path(track)
		if track_path.get_subname_count() == 0: continue
		var bone := str(track_path.get_subname(0))
		var target_index := skeleton.find_bone(bone)
		var source_index := source_skeleton.find_bone(bone)
		if target_index < 0 or source_index < 0: continue
		var correction := skeleton.get_bone_rest(target_index).basis.get_rotation_quaternion() * source_skeleton.get_bone_rest(source_index).basis.get_rotation_quaternion().inverse()
		var target := walk.add_track(Animation.TYPE_ROTATION_3D)
		walk.track_set_path(target, NodePath(str(root_node.get_path_to(skeleton)) + ":" + bone))
		for key in original.track_get_key_count(track):
			walk.rotation_track_insert_key(target, original.track_get_key_time(track, key), correction * Quaternion(original.track_get_key_value(track, key)))
	var library: AnimationLibrary = anim.get_animation_library("").duplicate()
	anim.remove_animation_library("")
	anim.add_animation_library("", library)
	library.add_animation("walk", walk)
	donor.free()

func _prop(parent: Node3D, asset: String, point: Vector3, height: float) -> void:
	var model: Node3D = load("res://assets/models/%s.glb" % asset).instantiate()
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.add_child(model)
	Weapons._fit_height(model, height)
	var bounds := ViewmodelHands.weapon_bounds(holder)
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	holder.position = point

func _process(delta: float) -> void:
	if npc_id == "wanderer": return
	if not game or not is_instance_valid(game.player): return
	var offset: Vector3 = game.player.global_position - global_position
	if offset.length_squared() < 100 and offset.length_squared() > 0.05:
		figure.rotation.y = lerp_angle(figure.rotation.y, atan2(offset.x, offset.z), minf(delta * 2, 1))

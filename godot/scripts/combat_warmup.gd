# Render the actual first-use variants behind the loading screen. Holding the
# source scenes/meshes in their owning caches also avoids later disk reloads.
extends RefCounted

static func populate(viewport: SubViewport, game: Node3D) -> Node3D:
	var root := Node3D.new()
	viewport.add_child(root)
	preload("res://scripts/tower_audio.gd").prewarm()
	for i in DefenceTower.TYPES.size():
		var tower := DefenceTower.new()
		tower.kind = DefenceTower.TYPES[i]
		tower.game = game
		tower.replica = true
		root.add_child(tower)
		tower.set_physics_process(false)
		tower.remove_from_group("defence_towers")
		tower.scale = Vector3.ONE * 0.3
		tower.position = Vector3(-3 + i * 1.5, 1.5, -1)
		tower.fx.fire(4.0)
		tower.flash.visible = true
		if tower._lightning: tower._lightning.fire(PackedVector3Array([tower.muzzle.global_position, tower.muzzle.global_position + Vector3(0, 1, -2)]))
	for i in 3:
		var drop := Pickup.new()
		drop.setup(["ammo", "grenade", "medkit"][i])
		root.add_child(drop)
		drop.position = Vector3(-1 + i, 2, 1)
		drop.set_process(false)
	var effects = preload("res://scripts/elemental_effects.gd")
	for mode in ["fire", "frost"]:
		var particles: CPUParticles3D = effects.particles(mode, 0.4, 1.7)
		root.add_child(particles)
		particles.position = Vector3(0, 2, 0)
		particles.emitting = true
		effects.shot(root, Vector3(-1, 2, 0), Vector3(1, 2, -1), mode, true)
	# The flare pistol's star; WeaponSpecials holds the mesh and its material for good.
	var star := MeshInstance3D.new()
	star.mesh = WeaponSpecials.star_mesh()
	root.add_child(star)
	star.position = Vector3(1, 2, 0)
	preload("res://scripts/tower_effects.gd").explosion(root, Vector3(0, 1, -2))
	Grenade.explosion_visuals(root, Vector3(0, 1, -2))
	for kind in ["fw_ruby", "fw_gold", "fw_cracker"]:
		var effect = Fireworks.make_effect(kind)
		# A late snapshot prepares the burst without playing ignition audio.
		effect.configure(kind, Vector3(0, -32, 0), Vector3(0, 2, 0), 17, 4.05 if kind != "fw_cracker" else 2.85)
		root.add_child(effect)
		effect.sparks.emitting = true
		effect.trail.emitting = true
	var zombie := Zombie.new()
	zombie.setup("shambler", game.player, [], 1.0, Callable())
	zombie.replica = true
	root.add_child(zombie)
	zombie.position = Vector3(2, 0, 0)
	zombie.rare_status = "fire+frost"
	zombie.update_rare_visual()
	zombie.set_physics_process(false)
	zombie.remove_from_group("shot_targets")
	# A raw skin does not prepare the full giant actor, warning geometry and
	# scaled rig. Prepare every variant without arrival cues or gameplay updates.
	for kind in ["titan", "titan_hunter", "titan_siege", "titan_ash"]:
		var titan := Titan.new()
		titan.setup(kind, game.player, [], 1.0, Callable())
		titan.replica = true
		root.add_child(titan)
		titan.set_process(false)
		titan.set_physics_process(false)
		titan.remove_from_group("shot_targets")
		titan.scale = Vector3.ONE * 0.08
		titan.position = Vector3(-2, 0, 0)
		titan.warning.global_position = Vector3(0, 0.1, 0)
		titan.warning.show()
	# Prepare the blood-decal pipeline without awarding a kill or creating loot.
	var blood := Decal.new()
	blood.texture_albedo = game.weapons._splat_tex
	blood.size = Vector3(2, 0.5, 2)
	root.add_child(blood)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8, 8)
	DefenceTower.piece(root, floor_mesh, Vector3.ZERO, DefenceTower.material(Color(0.3, 0.3, 0.3)))
	var retained: Array[Resource] = []
	for node in root.find_children("*", "Node3D", true, false):
		if node is MeshInstance3D or node is CPUParticles3D:
			if node.mesh: retained.append(node.mesh)
			if node.material_override: retained.append(node.material_override)
		elif node is GPUParticles3D:
			if node.process_material: retained.append(node.process_material)
			if node.draw_pass_1: retained.append(node.draw_pass_1)
	root.set_meta("warmup_resources", retained)
	return root

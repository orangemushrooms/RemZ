extends Node3D
## Existing Meshy plants in static spatial batches; nearby wildlife uses Forest AI.
const CELL := 48.0
const FLOWERS = preload("res://scripts/brew_recipes.gd").FLOWERS
const MUSHROOMS := ["mushroom_cluster","mushroom_fly","mushroom_pfifferling","mushroom_maronenroehrling","mushroom_parasol"]
var game: Node3D
var deer: Array[Deer] = []
var plants: Array[Dictionary] = []
var batches: Array[MultiMeshInstance3D] = []
var counts := {"flowers":0,"mushrooms":0,"deer":0,"stags":0}
var _templates := {}
var _groups := {}
var _clock := 0.0
const PICK_CELL := 8.0
var _pick_cells := {}
var _plant_batches := {}
var _picked := {}

func clear_ground(p: Vector2, woodland := false) -> bool:
	if not Map.BOUNDS.grow(-8).has_point(p) or game.near_building(p): return false
	var cover := Map.cover(p.x,p.y)
	var crops: Color = game.cornfield.sample(p)
	if cover.b>0.06 or crops.r>0.2 or crops.g>0.2 or crops.b>0.1: return false
	if Map.ground_normal(p.x,p.y).y<0.8: return false
	return cover.r>0.65 if woodland else cover.g>0.78

func build(scene: Node3D) -> void:
	game = scene
	var rng := RandomNumberGenerator.new()
	rng.seed = 940528
	var bounds := Map.BOUNDS.grow(-10)
	var kinds := FLOWERS.values()
	for attempt in 5000:
		var center := bounds.position+Vector2(rng.randf(),rng.randf())*bounds.size
		var woodland := Map.cover(center.x,center.y).r>0.65
		if not clear_ground(center,woodland): continue
		var spec: Dictionary = kinds[rng.randi_range(0,kinds.size()-1)]
		var id: String = MUSHROOMS[rng.randi_range(0,MUSHROOMS.size()-1)] if woodland else spec.model
		var height := 0.25 if woodland else float(spec.height)*0.7
		for plant in rng.randi_range(3,7):
			var p := center+Vector2(rng.randf_range(-3,3),rng.randf_range(-3,3))
			if not clear_ground(p,woodland): continue
			var size := rng.randf_range(0.7,1.2)
			var at := Map.ground_pos(p.x,p.y)
			if id=="field_flower_6": at.y -= 0.12*size
			var xf := Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size),at)
			var instance := _add_plant(id,height,xf,woodland)
			counts["mushrooms" if woodland else "flowers"] += 1
			var cell := Vector2i(floori(p.x/PICK_CELL),floori(p.y/PICK_CELL))
			if not _pick_cells.has(cell): _pick_cells[cell] = []
			_pick_cells[cell].append(plants.size())
			plants.append({"species":id,"at":p,"woodland":woodland,"group":instance.group,"instance":instance.index,"height":at.y})
	_flush()
	# Small herds on open meadow near hedgerows, never inside a house or crop row.
	for entry in [[Vector2(72,42),"stag"],[Vector2(82,50),"deer"],[Vector2(91,46),"deer"],[Vector2(-155,95),"deer"],[Vector2(-166,102),"deer"],[Vector2(240,-52),"stag"],[Vector2(250,-45),"deer"],[Vector2(260,-57),"deer"],[Vector2(-180,65),"stag"],[Vector2(-188,74),"deer"],[Vector2(270,130),"stag"],[Vector2(280,135),"deer"],[Vector2(195,-110),"deer"],[Vector2(182,-120),"deer"]]:
		var p := _meadow_near(entry[0],rng)
		var animal := Deer.new()
		animal.setup(game.player,entry[1],load("res://assets/models/%s_animated.glb" % entry[1]),7400+deer.size())
		animal.position = Map.ground_pos(p.x,p.y)+Vector3.UP*0.15
		animal.rotation.y = rng.randf()*TAU
		add_child(animal)
		deer.append(animal)
		counts["stags" if entry[1]=="stag" else "deer"] += 1
	# Spread the existing birds around paths and woodland edges instead of one grid.
	var spots := [Vector2(-90,8),Vector2(-104,36),Vector2(38,-16),Vector2(-60,45),Vector2(-120,95),Vector2(145,94),Vector2(184,220),Vector2(255,145),Vector2(-205,-55),Vector2(215,-55),Vector2(60,178),Vector2(-50,-120),Vector2(72,8),Vector2(220,-18)]
	for i in game.birds.size():
		var bird: Node3D = game.birds[i]
		var p := _meadow_near(spots[i%spots.size()]+Vector2(11,-8)*float(i/spots.size()),rng)
		bird.home = Map.ground_pos(p.x,p.y)+Vector3.UP*(5 if bird.owl else 0.2)
		bird.position = bird.home
		if not bird.owl and i%3==0: bird.flying = 8.0
	_update_distance()
	print("PLANES_NATURE ",counts," batches=",batches.size())

func _meadow_near(center: Vector2, rng: RandomNumberGenerator) -> Vector2:
	for attempt in 600:
		var radius := 4.0+attempt*0.2
		var p := center+Vector2(rng.randf_range(-radius,radius),rng.randf_range(-radius,radius))
		if clear_ground(p): return p
	return Map.PLAYER_START

func _template(id: String, height: float, woodland: bool) -> Array:
	if _templates.has(id): return _templates[id]
	var root: Node3D = load("res://assets/planes/%s.glb" % id).instantiate()
	var bounds := Barricade._bounds(root)
	var factor := height/maxf(bounds.size.y,0.001)
	root.scale *= factor
	root.position = -Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
	var parts: Array = []
	if root:
		_collect(root,Transform3D.IDENTITY,parts,woodland)
		root.free()
	_templates[id] = parts
	return parts

func _collect(node: Node, parent_xf: Transform3D, parts: Array, woodland: bool) -> void:
	var xf: Transform3D = parent_xf*node.transform if node is Node3D else parent_xf
	if node is MeshInstance3D and node.mesh:
		var mesh: ArrayMesh = node.mesh.duplicate()
		for surface in mesh.get_surface_count():
			var source: Material = node.get_active_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D = source.duplicate()
				material.emission_enabled = false
				material.roughness = 0.95
				material.metallic = 0.0
				material.rim_enabled = false
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false
				if not woodland: material.albedo_color *= Color(0.62,0.68,0.55)
				mesh.surface_set_material(surface,material)
		parts.append({"mesh":mesh,"xf":xf})
	for child in node.get_children(): _collect(child,xf,parts,woodland)

func _add_plant(id: String, height: float, xf: Transform3D, woodland: bool) -> Dictionary:
	var cell := Vector2i(floori(xf.origin.x/CELL),floori(xf.origin.z/CELL))
	var key := "%s:%d:%d" % [id,cell.x,cell.y]
	if not _groups.has(key):
		_groups[key] = {"parts":_template(id,height,woodland),"origin":Vector3(cell.x*CELL,0,cell.y*CELL),"instances":[],"woodland":woodland}
	var group: Dictionary = _groups[key]
	xf.origin -= group.origin
	group.instances.append(xf)
	return {"group":key,"index":group.instances.size()-1}

func _flush() -> void:
	for key in _groups:
		var group: Dictionary = _groups[key]
		_plant_batches[key] = []
		for part: Dictionary in group.parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part.mesh
			mm.instance_count = group.instances.size()
			for i in mm.instance_count: mm.set_instance_transform(i,group.instances[i]*part.xf)
			var batch := MultiMeshInstance3D.new()
			batch.multimesh = mm
			_plant_batches[key].append(mm)
			batch.position = group.origin
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batch.visibility_range_end = 38 if group.woodland else 58
			add_child(batch)
			batches.append(batch)
	_groups.clear()

func nearest_plant(at: Vector3) -> int:
	var cell := Vector2i(floori(at.x/PICK_CELL),floori(at.z/PICK_CELL))
	var nearest := -1
	var distance := 2.5*2.5
	for z in range(cell.y-1,cell.y+2):
		for x in range(cell.x-1,cell.x+2):
			for index: int in _pick_cells.get(Vector2i(x,z),[]):
				if _picked.has(index): continue
				var plant: Dictionary = plants[index]
				var d := at.distance_squared_to(Vector3(plant.at.x,plant.height,plant.at.y))
				if d<distance:
					distance = d; nearest = index
	return nearest

func harvest(index: int, collector: Player = null) -> String:
	if not collector: collector = game.player
	if index<0 or index>=plants.size() or _picked.has(index): return ""
	if not game.survival_active or game.over or not collector.active or not collector.alive or collector.downed: return ""
	var plant: Dictionary = plants[index]
	if collector.position.distance_to(Vector3(plant.at.x,plant.height,plant.at.y))>2.5: return ""
	hide_harvested(index)
	return "mushrooms" if plant.woodland else "flowers"

func hide_harvested(index: int) -> void:
	if index<0 or index>=plants.size() or _picked.has(index): return
	var plant: Dictionary = plants[index]
	var original: Array[Transform3D] = []
	for mm: MultiMesh in _plant_batches[plant.group]:
		var xf := mm.get_instance_transform(plant.instance)
		original.append(xf)
		xf.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
		mm.set_instance_transform(plant.instance,xf)
	_picked[index] = original

func reset_harvest() -> void:
	for index in _picked:
		var plant: Dictionary = plants[index]
		var meshes: Array = _plant_batches[plant.group]
		for part in meshes.size():
			meshes[part].set_instance_transform(plant.instance,_picked[index][part])
	_picked.clear()

func _process(delta: float) -> void:
	_clock -= delta
	if _clock<=0:
		_clock = 0.5
		_update_distance()

func _update_distance() -> void:
	if not game.player: return
	for animal: Node3D in deer+game.birds:
		if animal.get_meta("hunted_dead",false): continue
		var near := animal.global_position.distance_squared_to(game.player.global_position)<180.0*180.0
		if NetSession.is_host() and NetSession.world and not near:
			for actor: Player in NetSession.world.actors.values():
				if actor.alive and animal.global_position.distance_squared_to(actor.global_position)<180.0*180.0:
					near = true
					break
		animal.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED
		if animal is Deer or not animal.owl: animal.visible = near
		elif not near: animal.hide()

func ingredient(index: int) -> String:
	if index<0 or index>=plants.size(): return ""
	var model: String = plants[index].species
	for id in FLOWERS:
		if FLOWERS[id].model==model: return id
	return {"mushroom_cluster":"steinpilz","mushroom_fly":"fliegenpilz","mushroom_pfifferling":"pfifferling","mushroom_maronenroehrling":"maronenroehrling","mushroom_parasol":"parasol"}.get(model,"steinpilz")

func ingredient_name(index: int) -> String:
	var id := ingredient(index)
	return str(FLOWERS[id].name if FLOWERS.has(id) else Inventory.MUSHROOMS[id].name)

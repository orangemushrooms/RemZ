extends Node3D
## One shared outline for movement, navigation, spawning and cartography.
const OUTLINE := [Vector2(-335,320),Vector2(-335,100),Vector2(-320,80),Vector2(-320,-90),Vector2(-170,-170),
	Vector2(-90,-190),Vector2(60,-200),Vector2(110,-310),Vector2(170,-300),
	Vector2(300,-290),Vector2(370,-235),Vector2(395,-205),Vector2(440,-182),
	Vector2(515,-182),Vector2(515,280),Vector2(200,290),Vector2(-60,320)]
const MAIN_ROAD_START := Vector2(-228.5,176.0)
const MAIN_ROAD_END := Vector2(-122.0,334.0)

static func southwest_road(p: Vector2, half_width := 7.2) -> bool:
	if p.x < -240.0 or p.x > -110.0 or p.y < 165.0 or p.y > 335.0: return false
	var segment := MAIN_ROAD_END-MAIN_ROAD_START
	var along := clampf((p-MAIN_ROAD_START).dot(segment)/segment.length_squared(),0.0,1.0)
	return p.distance_squared_to(MAIN_ROAD_START+segment*along)<half_width*half_width

static func fence_piece_allowed(a: Vector2, b: Vector2) -> bool:
	return not southwest_road(a,8.5) and not southwest_road(b,8.5) and not southwest_road((a+b)*0.5,8.5)

static func contains(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p,PackedVector2Array(OUTLINE))

static func closest(p: Vector2) -> Vector2:
	var result: Vector2 = OUTLINE[0]
	var distance := INF
	for i in OUTLINE.size():
		var q := Geometry2D.get_closest_point_to_segment(p,OUTLINE[i],OUTLINE[(i+1)%OUTLINE.size()])
		if q.distance_squared_to(p)<distance:
			distance = q.distance_squared_to(p)
			result = q
	return result

static func confine(actor: Node3D) -> void:
	var p := Vector2(actor.position.x,actor.position.z)
	if contains(p): return
	var q := closest(p)
	var outward := (p-q).normalized()
	actor.position.x = q.x-outward.x*0.02
	actor.position.z = q.y-outward.y*0.02
	var horizontal := Vector2(actor.velocity.x,actor.velocity.z)
	horizontal -= outward*maxf(0.0,horizontal.dot(outward))
	actor.velocity.x = horizontal.x
	actor.velocity.z = horizontal.y

func build() -> void:
	name = "FieldBoundary"
	var posts: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	for i in OUTLINE.size():
		var a: Vector2 = OUTLINE[i]
		var b: Vector2 = OUTLINE[(i+1)%OUTLINE.size()]
		var steps := ceili(a.distance_to(b)/4.0)
		for j in steps:
			var p := a.lerp(b,float(j)/steps)
			var next := a.lerp(b,float(j+1)/steps)
			if not fence_piece_allowed(p,next): continue
			var start := Map.ground_pos(p.x,p.y)
			var end := Map.ground_pos(next.x,next.y)
			posts.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.09,1.15,0.09)),start+Vector3.UP*0.53))
			for height in [0.35,0.68,1.02]:
				var direction := end-start
				var basis := Basis.looking_at(direction.normalized(),Vector3.UP).scaled(Vector3(0.008,0.008,direction.length()))
				rails.append(Transform3D(basis,(start+end)*0.5+Vector3.UP*height))
	_batch(posts,Color(0.27,0.19,0.12))
	_batch(rails,Color(0.37,0.34,0.26))

func _batch(transforms: Array[Transform3D], colour: Color) -> void:
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	if colour.r<0.3:
		material.albedo_texture = load("res://assets/textures/ph_bark_oak_albedo.jpg")
	mesh.material = material
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for i in transforms.size(): batch.set_instance_transform(i,transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = batch
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

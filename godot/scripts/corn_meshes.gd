extends RefCounted
# Original low-poly meshes built in metres; shared by MultiMesh batches.
static var surface: SurfaceTool
static func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for v in [a,b,c]:
		surface.set_color(color)
		surface.add_vertex(v)
static func tube(a: Vector3, b: Vector3, radius: float, color: Color, sides: int = 5) -> void:
	var up := (b-a).normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	if right.length_squared() < 0.1: right = Vector3.RIGHT
	var forward := up.cross(right)
	for i in sides:
		var u := (right*cos(i*TAU/sides)+forward*sin(i*TAU/sides))*radius
		var v := (right*cos((i+1)*TAU/sides)+forward*sin((i+1)*TAU/sides))*radius
		triangle(a+u,b+u,b+v,color)
		triangle(a+u,b+v,a+v,color)
		triangle(b,b+v,b+u,color.lightened(0.1))
static func ellipsoid(at: Vector3, size: Vector3, color: Color) -> void:
	for y in 5:
		for x in 8:
			var pts: Array[Vector3] = []
			for uv: Vector2 in [Vector2(x,y),Vector2(x+1,y),Vector2(x+1,y+1),Vector2(x,y+1)]:
				var lat := uv.y*PI/5.0
				var lon := uv.x*TAU/8.0
				pts.append(at + Vector3(sin(lat)*cos(lon),cos(lat),sin(lat)*sin(lon))*size)
			triangle(pts[0],pts[1],pts[2],color)
			triangle(pts[0],pts[2],pts[3],color)
static func make(kind: String) -> ArrayMesh:
	surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "corn_far":
		var green := Color(0.34,0.43,0.1)
		triangle(Vector3(-0.025,0,0),Vector3(0.025,0,0),Vector3(0,2.55,0),green)
		for i in 6:
			var angle := i*2.4
			var direction := Vector3(cos(angle),0,sin(angle))
			var side := Vector3(-sin(angle),0,cos(angle))*0.12
			var start := Vector3(0,0.4+i*0.31,0)
			var middle := start+direction*0.35+Vector3.UP*0.22
			var tip := start+direction*0.66
			triangle(start,middle+side,tip,green.lightened(0.05))
			triangle(start,tip,middle-side,green)
	elif kind.begins_with("corn"):
		var green := Color(0.3,0.43,0.08) if kind == "corn_a" else Color(0.48,0.48,0.12)
		tube(Vector3.ZERO,Vector3(0.04,2.55,0),0.025,green,4)
		for i in 8:
			var yaw := i*2.4
			var direction := Vector3(cos(yaw),0,sin(yaw))
			var side := Vector3(-sin(yaw),0,cos(yaw))*0.1
			var start := Vector3(0,0.35+i*0.245,0)
			var middle := start+direction*0.38+Vector3.UP*0.22
			var tip := start+direction*(0.62 if i<6 else 0.42)-Vector3.UP*0.12
			triangle(start,middle+side,middle,green.lightened(0.1))
			triangle(start,middle,middle-side,green)
			triangle(middle+side,tip,middle,green.lightened(0.1))
			triangle(middle,tip,middle-side,green)
		tube(Vector3(0.08,1.12,0),Vector3(0.12,1.5,0),0.065,Color(0.8,0.61,0.17),6)
		for i in 5:
			var angle := i*TAU/5
			tube(Vector3(0.04,2.4,0),Vector3(cos(angle)*0.16,2.7,sin(angle)*0.16),0.014,Color(0.71,0.57,0.26),3)
	elif kind == "scarecrow":
		tube(Vector3.ZERO,Vector3(0,2.5,0),0.065,Color(0.27,0.16,0.07))
		tube(Vector3(-1,1.7,0),Vector3(1,1.7,0),0.045,Color(0.31,0.2,0.1))
		ellipsoid(Vector3(0,1.5,0),Vector3(0.27,0.46,0.16),Color(0.32,0.18,0.1))
		for side in [-1,1]:
			tube(Vector3(side*0.18,1.8,0),Vector3(side*0.82,1.65,0),0.13,Color(0.38,0.24,0.12))
			for j in 5:
				tube(Vector3(side*0.75,1.65,0),Vector3(side*(0.98+j*0.025),1.52+j*0.045,0),0.012,Color(0.75,0.61,0.3),3)
		# Torn coat tails and contrasting cloth patches.
		for side in [-1,1]:
			triangle(Vector3(side*0.24,1.6,-0.17),Vector3(side*0.34,0.83,-0.12),Vector3(0,1.05,-0.18),Color(0.27,0.16,0.08))
			triangle(Vector3(side*0.24,1.6,0.17),Vector3(0,1.05,0.18),Vector3(side*0.3,0.96,0.12),Color(0.25,0.13,0.065))
		tube(Vector3(-0.12,1.32,-0.17),Vector3(0.03,1.42,-0.17),0.05,Color(0.43,0.35,0.2),4)
		ellipsoid(Vector3(0,2.13,0),Vector3(0.22,0.25,0.19),Color(0.67,0.53,0.3))
		tube(Vector3(0,2.34,0),Vector3(0,2.39,0),0.38,Color(0.19,0.13,0.08),8)
		tube(Vector3(0,2.39,0),Vector3(0,2.64,0),0.2,Color(0.23,0.17,0.1),8)
		for x in [-0.085,0.085]: ellipsoid(Vector3(x,2.16,-0.175),Vector3(0.033,0.045,0.025),Color(0.06,0.04,0.015))
		tube(Vector3(-0.08,2.03,-0.18),Vector3(0.08,2.03,-0.18),0.012,Color(0.09,0.05,0.02),3)
	elif kind.ends_with("wing"):
		var color := Color(0.09,0.1,0.12) if kind.begins_with("raven") else Color(0.4,0.3,0.18)
		triangle(Vector3.ZERO,Vector3(0.65,0,0.1),Vector3(0.12,0,0.3),color)
		for i in 5:
			triangle(Vector3(0.15+i*0.1,0,0.08),Vector3(0.25+i*0.1,0,0.13),Vector3(0.23+i*0.09,0,0.4-i*0.03),color.lightened(i*0.02))
	else:
		var owl := kind == "owl_body"
		var color := Color(0.39,0.29,0.17) if owl else Color(0.055,0.065,0.08)
		ellipsoid(Vector3(0,0.15,0),Vector3(0.17,0.25,0.23),color)
		ellipsoid(Vector3(0,0.4,-0.15),Vector3(0.18 if owl else 0.12,0.16,0.14),color.lightened(0.1))
		if owl:
			ellipsoid(Vector3(0,0.39,-0.265),Vector3(0.14,0.12,0.025),Color(0.77,0.68,0.48))
		for x in [-0.065,0.065]:
			ellipsoid(Vector3(x,0.42,-0.285),Vector3(0.026,0.027,0.018),Color(0.95,0.65,0.12) if owl else Color(0.1,0.1,0.1))
		triangle(Vector3(-0.045,0.35,-0.25),Vector3(0.045,0.35,-0.25),Vector3(0,0.29,-0.42),Color(0.21,0.17,0.09))
		for x in [-0.065,0.065]:
			tube(Vector3(x,0.06,0),Vector3(x,-0.1,-0.02),0.012,Color(0.16,0.12,0.07),4)
			for j in [-1,0,1]: tube(Vector3(x,-0.1,-0.02),Vector3(x+j*0.03,-0.11,-0.1),0.008,Color(0.16,0.12,0.07),3)
		triangle(Vector3(-0.1,0.08,0.15),Vector3(0.1,0.08,0.15),Vector3(0,0,0.48),color)
	surface.generate_normals()
	var mesh := surface.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.95
	mesh.surface_set_material(0,mat)
	return mesh

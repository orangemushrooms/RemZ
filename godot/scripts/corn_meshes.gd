extends RefCounted
# Original procedural meshes built in metres; shared by MultiMesh batches.
static var surface: SurfaceTool
static var is_corn := false
static func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for v in [a,b,c]:
		if is_corn: surface.set_uv2(Vector2.ZERO)
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
# Curved ribbon leaves have a raised midrib, tapered tips and drooping ends.
static func leaf(start: Vector3, yaw: float, length: float, width: float, rise: float, droop: float, color: Color, segments: int) -> void:
	var direction := Vector3(cos(yaw),0,sin(yaw))
	var side := Vector3(-sin(yaw),0,cos(yaw))
	for i in segments:
		var vertices: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for step in [i,i+1]:
			var t := float(step)/segments
			var center := start+direction*length*t+Vector3.UP*(rise*sin(t*PI*0.8)-droop*t*t)
			var breadth := width*pow(sin(PI*t),0.75)*0.5+0.001
			for edge in [-1,0,1]:
				vertices.append(center+side*breadth*edge+Vector3.UP*(0.022*sin(t*PI)*(1-abs(edge))))
				uvs.append(Vector2(t,(edge+1)*0.5))
		for index in [0,3,4,0,4,1,1,4,5,1,5,2]:
			surface.set_uv(uvs[index])
			surface.set_uv2(Vector2(1,0))
			surface.set_color(color.darkened(uvs[index].x*0.12))
			surface.add_vertex(vertices[index])

static func corn(far: bool, ripe: bool) -> void:
	var green := Color(0.30,0.40,0.17) if ripe else Color(0.24,0.38,0.16)
	var height := 2.32 if ripe else 2.48
	if far:
		triangle(Vector3(-0.012,0,0),Vector3(0.012,0,0),Vector3(0.04,height,0),green)
		for i in 7:
			var t := i/6.0
			leaf(Vector3(0,0.25+t*1.9,0),i*3.02,0.88-0.38*t,0.10,0.23+0.15*t,0.45*(1.0-t)+0.10,green,2)
		for j in 3:
			var tip := Vector3(cos(j*2.4)*0.13,height+0.20,sin(j*2.4)*0.13)
			triangle(Vector3(0.04,height-0.1,0),tip,tip+Vector3(0.003,0,0.003),Color(0.51,0.46,0.30))
		return
	var sections := 10
	for i in sections:
		var lo := float(i)/sections
		var hi := float(i+1)/sections
		tube(Vector3(0.045*lo*lo,height*lo,0),Vector3(0.045*hi*hi,height*hi,0),lerpf(0.018,0.007,lo),green.lightened(0.035),3 if far else 6)
	for i in (7 if far else 10):
		var t := float(i)/(6 if far else 9)
		var yaw := i*3.02+(0.5 if ripe else 0.0)
		var y := 0.20+t*1.95
		var length := (0.88-0.38*t)*(0.94 if ripe else 1.0)
		var tone := green.lerp(Color(0.48,0.40,0.22),0.65 if i<2 else (0.16 if ripe else 0.0))
		leaf(Vector3(0.02,y,0),yaw,length,0.105 if i<6 else 0.075,0.23+0.15*t,0.45*(1.0-t)+0.10,tone,3 if far else 8)
	if not far:
		# A tapered green husk encloses the ear; only brown silk is exposed.
		var ear := Vector3(0.095,1.18,0.015)
		ellipsoid(ear,Vector3(0.048,0.19,0.045),green.lightened(0.07))
		for j in 3:
			leaf(ear-Vector3.UP*0.15,j*2.1,0.16,0.06,0.24,0.05,green.lightened(0.035*j),5)
		for j in 5:
			tube(ear+Vector3(j*0.005,0.17,0),ear+Vector3(0.025+j*0.008,0.22-j*0.009,0.015),0.0015,Color(0.29,0.19,0.095),3)
	var straw := Color(0.51,0.46,0.30)
	tube(Vector3(0.045,height-0.13,0),Vector3(0.05,height+0.25,0),0.0035,straw,3)
	for j in (4 if far else 9):
		var angle := j*2.4
		var start := Vector3(0.045,height-0.1+j*0.015,0)
		var tip := start+Vector3(cos(angle)*0.13,0.19,sin(angle)*0.13)
		tube(start,tip,0.0025,straw,3)
		if not far:
			for k in 3:
				var at := start.lerp(tip,0.3+k*0.2)
				tube(at,at+Vector3(0.025,0.04,0.012),0.0017,straw.lightened(0.06),3)

static func make(kind: String) -> ArrayMesh:
	surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	is_corn = kind.begins_with("corn")
	if is_corn:
		surface.set_smooth_group(0)
		surface.set_uv(Vector2.ZERO)
		surface.set_uv2(Vector2.ZERO)
	if kind.begins_with("corn"):
		corn(kind == "corn_far", kind == "corn_b")
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

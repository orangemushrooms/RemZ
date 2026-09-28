extends "res://scripts/village_buildings.gd"
## Exact OSM wall polygons. Adjacent footprints must not become overlapping
## rotated bounding boxes; roofs are single surfaces without stacked slabs.
var footprints: Array[PackedVector2Array] = []
var target_panels: Array[Transform3D] = []

func build() -> Node3D:
	var result := super.build()
	result.set_meta("exact_footprints",footprints.size())
	result.set_meta("target_panels",target_panels)
	return result

func _build_house(data: Dictionary, id: int) -> void:
	var points := PackedVector2Array()
	for p in data.poly:
		var at := Vector2(p[0],p[1])
		if points.is_empty() or points[-1].distance_to(at)>0.02: points.append(at)
	if points.size()>2 and points[0].distance_to(points[-1])<0.02: points.remove_at(points.size()-1)
	if points.size()<3: return
	# OSM ways use both windings. Facade +z must always face OUT of the house.
	if Geometry2D.is_polygon_clockwise(points): points.reverse()
	var direction := Vector2.RIGHT
	var length := 0.0
	var center := Vector2.ZERO
	for i in points.size():
		center += points[i]/points.size()
		var edge := points[(i+1)%points.size()]-points[i]
		if edge.length_squared()>length: direction = edge.normalized(); length = edge.length_squared()
	# Duplicate source outlines are uncommon, but must not produce coplanar roofs.
	for old: PackedVector2Array in footprints:
		if old.size()!=points.size() or old[0].distance_to(points[0])>0.02: continue
		if old==points: return
	footprints.append(points)
	_frame = Transform3D(Basis(Vector3.UP,-direction.angle()),Map.ground_pos(center.x,center.y))
	if data.get("kind","")=="shooting_targets":
		var towards := Vector2(data.facing[0],data.facing[1])-center
		if Vector2(_frame.basis.z.x,_frame.basis.z.z).dot(towards)<0:
			_frame.basis = _frame.basis.rotated(Vector3.UP,PI)
	_cell = Vector2i(floori(center.x/CELL_SIZE),floori(center.y/CELL_SIZE))
	_rng.seed = 81013+id*7919
	_building_count += 1
	var polygon := PackedVector2Array()
	var half_width := 0.0
	var low_x := INF
	var high_x := -INF
	var base := -1.0
	for p in points:
		var local := _frame.affine_inverse()*Map.ground_pos(p.x,p.y)
		polygon.append(Vector2(local.x,local.z))
		low_x = minf(low_x,local.x)
		high_x = maxf(high_x,local.x)
		half_width = maxf(half_width,absf(local.z))
		base = minf(base,local.y-0.3)
	if data.get("kind","")=="shooting_targets":
		_build_target_stand(data,low_x,high_x,half_width,base)
		return
	var area := 0.0
	for i in polygon.size(): area += polygon[i].cross(polygon[(i+1)%polygon.size()])*0.5
	var shed := area<60.0
	var barn := not shed and (float(data.h)<5.0 or (area>300 and (high_x-low_x)>half_width*3.2 and id%3==0))
	var farm := not shed and not barn and area>240.0
	var height := (2.7 if shed else 4.8 if barn else clampf(float(data.h),3.1,8.4)) + _rng.randf_range(-0.22,0.22)
	var rise := clampf(half_width*(0.58 if barn or shed else 0.9),1.2,7.5)
	var colour: Color = PLASTER[id%PLASTER.size()]
	var timber := Color(0.33,0.24,0.17)*_rng.randf_range(0.85,1.1)
	var shutter: Color = SHUTTERS[id%SHUTTERS.size()]
	var roof_material := "slate" if barn or shed or id%7==3 else "tiles"
	var roof_colour := (Color(0.62,0.4,0.3) if roof_material=="tiles" else Color(0.42,0.4,0.38))*_rng.randf_range(0.85,1.1)
	var split := low_x+clampf((high_x-low_x)*0.42,8.0,14.0)
	var door_added := false
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		var sections: Array[Vector2] = [a]
		if farm and (a.x-split)*(b.x-split)<0:
			sections.append(a.lerp(b,(split-a.x)/(b.x-a.x)))
		sections.append(b)
		for s in sections.size()-1:
			var start := sections[s]
			var end := sections[s+1]
			var wood_wall := barn or shed or (farm and (start.x+end.x)*0.5>split)
			_wall(start,end,base,height,rise,half_width,"wood" if wood_wall else "plaster",timber if wood_wall else colour)
			var delta := end-start
			if delta.length()<2.8: continue
			var outward := Vector3(delta.y,0,-delta.x).normalized()
			var middle := (start+end)*0.5
			var front := Transform3D(Basis(Vector3.UP,atan2(outward.x,outward.z)),Vector3(middle.x,0,middle.y))
			if wood_wall:
				_gate(front,0,minf(delta.length()*0.44,3.6),minf(height-0.65,3.4),timber)
				for post in maxi(2,int(delta.length()/3.8))+1:
					var x := lerpf(-delta.length()*0.5+0.15,delta.length()*0.5-0.15,float(post)/maxi(2,int(delta.length()/3.8)))
					_box("wood",Vector3(0.16,height-0.5,0.13),front*Vector3(x,(height+0.5)*0.5,0.09),timber*0.6,front.basis)
			else:
				var columns := clampi(int(delta.length()/3.8),1,5)
				for floor_index in (2 if height>4.6 else 1):
					for column in columns:
						var x := (float(column)+0.5)/columns*delta.length()-delta.length()*0.5
						if not door_added and floor_index==0 and column==columns/2:
							_gate(front,x,1.1,2.2,shutter)
							door_added = true
						else: _window(front,x,1.55+floor_index*2.55,shutter,0.9)
		# Fascia follows the polygon, never a bounding box overlapping neighbours.
		var edge := b-a
		var normal := Vector3(edge.y,0,-edge.x).normalized()
		var top_a := Vector3(a.x,_roof_y(a.y,height,rise,half_width),a.y)
		var top_b := Vector3(b.x,_roof_y(b.y,height,rise,half_width),b.y)
		var rim: Array[Vector3] = [top_a]
		if a.y*b.y<0.0:
			var ridge := a.lerp(b,-a.y/(b.y-a.y))
			rim.append(Vector3(ridge.x,height+rise,0))
			if rise>2.1 and absf(normal.x)>0.75 and edge.length()>4 and not barn and not shed:
				var front := Transform3D(Basis(Vector3.UP,atan2(normal.x,normal.z)),Vector3(ridge.x,0,0))
				_window(front,0,height+rise*0.35,shutter,0.6)
		rim.append(top_b)
		for k in rim.size()-1:
			_beam(rim[k],rim[k+1],normal,timber*0.5)
		if absf(edge.y)<0.3 and edge.length()>4:
			var at := Vector3(a.x,0,a.y)+normal*0.13+Vector3(edge.x,0,edge.y).normalized()*0.25
			_box("trim",Vector3(0.10,height-0.45,0.10),at+Vector3.UP*(height+0.45)*0.5,Color(0.3,0.29,0.25))
	for side in [-1.0,1.0]:
		var half := _clip_half(polygon,side)
		var triangles := Geometry2D.triangulate_polygon(half)
		var normal := Vector3(0,1,side*rise/maxf(half_width,0.1)).normalized()
		for i in range(0,triangles.size(),3):
			var vertices: Array = []
			for k in 3:
				var p := half[triangles[i+k]]
				vertices.append(Vector3(p.x,_roof_y(p.y,height,rise,half_width),p.y))
			_triangle(roof_material,vertices,normal,roof_colour)
	if not barn and not shed:
		# The centroid of a roof triangle is inside even a concave footprint.
		var indices := Geometry2D.triangulate_polygon(polygon)
		for i in range(0,indices.size(),3):
			var p := (polygon[indices[i]]+polygon[indices[i+1]]+polygon[indices[i+2]])/3.0
			if farm and p.x>split: continue
			var clear := true
			for j in polygon.size():
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p,polygon[j],polygon[(j+1)%polygon.size()]))<0.8: clear = false
			if not clear: continue
			var y := _roof_y(p.y,height,rise,half_width)
			_box("plaster",Vector3(0.65,1.55,0.7),Vector3(p.x,y+0.3,p.y),colour*0.72)
			_box("trim",Vector3(0.82,0.14,0.87),Vector3(p.x,y+1.1,p.y),Color(0.22,0.21,0.19))
			break

func _build_target_stand(data: Dictionary, low_x: float, high_x: float, depth: float, base: float) -> void:
	# Low concrete trench/stop-butt on the surveyed footprint, facing downhill.
	# Target details are an interpretation of the club photo, not a survey.
	var width := high_x-low_x
	var mid := (low_x+high_x)*0.5
	var concrete := Color(0.62,0.62,0.56)
	var steel := Color(0.17,0.18,0.16)
	var front := maxf(0.25,depth-0.22)
	_box("plaster",Vector3(width,0.55-base,depth*2),Vector3(mid,(base+0.55)*0.5,0),concrete)
	_box("trim",Vector3(width-0.18,1.52,0.16),Vector3(mid,1.31,front-0.18),steel)
	_box("plaster",Vector3(width+0.08,0.15,0.42),Vector3(mid,0.58,depth-0.18),concrete.lightened(0.12))
	for x in [low_x+0.09,high_x-0.09]:
		_box("plaster",Vector3(0.18,1.58,0.38),Vector3(x,1.33,front-0.09),concrete)
	_box("trim",Vector3(width,0.12,0.3),Vector3(mid,2.14,front-0.08),steel)
	for i in int(data.target_count):
		var x := lerpf(low_x+0.95,high_x-0.95,(i+0.5)/float(data.target_count))
		var face := Transform3D(Basis.IDENTITY,Vector3(x,1.34,front))
		_box("trim",Vector3(1.38,1.42,0.09),face.origin,Color(0.12,0.13,0.12))
		_panel(face,Vector2.ZERO,Vector2(1.2,1.24),0.065,"trim",Color(0.91,0.90,0.83))
		var center := Vector3(0,0,0.085)
		for segment in 32:
			var a := TAU*segment/32.0
			var b := TAU*(segment+1)/32.0
			_triangle("trim",[face*center,face*(center+Vector3(cos(a),sin(a),0)*0.33),face*(center+Vector3(cos(b),sin(b),0)*0.33)],Vector3.BACK,Color(0.025,0.03,0.025))
		target_panels.append(_frame*face)

func _wall(a: Vector2, b: Vector2, base: float, height: float, rise: float, width: float, material: String, colour: Color) -> void:
	var edge := b-a
	var normal := Vector3(edge.y,0,-edge.x).normalized()
	var lo_a := Vector3(a.x,base,a.y)
	var lo_b := Vector3(b.x,base,b.y)
	var sill_a := Vector3(a.x,0.5,a.y)
	var sill_b := Vector3(b.x,0.5,b.y)
	_quad("stone",[lo_a,lo_b,sill_b,sill_a],normal,Color(0.48,0.46,0.41))
	var top_a := Vector3(a.x,_roof_y(a.y,height,rise,width),a.y)
	var top_b := Vector3(b.x,_roof_y(b.y,height,rise,width),b.y)
	_quad(material,[sill_a,sill_b,top_b,top_a],normal,colour)
	if a.y*b.y<0:
		var ridge := a.lerp(b,-a.y/(b.y-a.y))
		_triangle(material,[top_a,top_b,Vector3(ridge.x,height+rise,0)],normal,colour)

func _beam(a: Vector3, b: Vector3, normal: Vector3, colour: Color) -> void:
	var along := (b-a).normalized()
	var across := normal.cross(along).normalized()
	_box("wood",Vector3(a.distance_to(b),0.18,0.22),(a+b)*0.5-Vector3.UP*0.06,colour,Basis(along,across,normal))

# Facade cards retain the existing sills/shutters, but discard hidden box faces.
# This pays for the restored architecture without hundreds of thousands of triangles.
func _window(front: Transform3D, x: float, y: float, shutters: Color, scale: float = 1.0) -> void:
	var w := 1.08*scale
	var h := 1.38*scale
	_panel(front,Vector2(x,y),Vector2(w+0.22,h+0.22),0.05,"trim",Color(0.38,0.35,0.29))
	_panel(front,Vector2(x,y),Vector2(w,h),0.12,"glass",Color(0.075,0.105,0.12))
	_panel(front,Vector2(x,y),Vector2(0.065,h),0.18,"trim",Color(0.74,0.71,0.61))
	_panel(front,Vector2(x,y+0.12),Vector2(w,0.065),0.19,"trim",Color(0.74,0.71,0.61))
	_box("stone",Vector3(w+0.35,0.12,0.32),front*Vector3(x,y-h*0.5-0.12,0.12),Color(0.73,0.7,0.62),front.basis)
	for side in [-1.0,1.0]:
		_panel(front,Vector2(x+side*w*0.78,y),Vector2(w*0.43,h+0.06),0.1,"wood",shutters)

func _panel(front: Transform3D, center: Vector2, size: Vector2, depth: float, material: String, colour: Color) -> void:
	var vertices: Array = []
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var p: Vector2 = center+corner*size*0.5
		vertices.append(front*Vector3(p.x,p.y,depth))
	_quad(material,vertices,front.basis.z,colour)

func _quad(material: String, vertices: Array, normal: Vector3, colour: Color) -> void:
	_triangle(material,[vertices[0],vertices[1],vertices[2]],normal,colour)
	_triangle(material,[vertices[0],vertices[2],vertices[3]],normal,colour)

func _triangle(material: String, vertices: Array, normal: Vector3, colour: Color) -> void:
	var surface := _surface(material)
	var origin := Vector3(_cell.x*CELL_SIZE,0,_cell.y*CELL_SIZE)
	if (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0]).dot(normal)>0:
		vertices = [vertices[0],vertices[2],vertices[1]]
	# Tangent-plane UVs: projecting every face onto Z/Y collapsed roof and side textures.
	var u := Vector3.RIGHT if absf(normal.y)>0.5 else Vector3(normal.z,0,-normal.x).normalized()
	var v := normal.cross(u)
	for p: Vector3 in vertices:
		surface.set_uv(Vector2(p.dot(u),p.dot(v)))
		surface.set_color(colour)
		surface.set_normal(_frame.basis*normal)
		surface.add_vertex(_frame*p-origin)

func _roof_y(z: float, height: float, rise: float, width: float) -> float:
	return height+rise*(1.0-absf(z)/maxf(width,0.1))

func _clip_half(polygon: PackedVector2Array, side: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		if a.y*side>=0: result.append(a)
		if a.y*b.y<0: result.append(a.lerp(b,-a.y/(b.y-a.y)))
	return result

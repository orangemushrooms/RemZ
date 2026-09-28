extends "res://scripts/village_buildings.gd"
## Exact OSM wall polygons. Adjacent footprints must not become overlapping
## rotated bounding boxes; roofs are single surfaces without stacked slabs.
var footprints: Array[PackedVector2Array] = []

func build() -> Node3D:
	var result := super.build()
	result.set_meta("exact_footprints",footprints.size())
	return result

func _build_house(data: Dictionary, id: int) -> void:
	var points := PackedVector2Array()
	for p in data.poly:
		var at := Vector2(p[0],p[1])
		if points.is_empty() or points[-1].distance_to(at)>0.02: points.append(at)
	if points.size()>2 and points[0].distance_to(points[-1])<0.02: points.remove_at(points.size()-1)
	if points.size()<3: return
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
	_cell = Vector2i(floori(center.x/CELL_SIZE),floori(center.y/CELL_SIZE))
	_rng.seed = 81013+id*7919
	_building_count += 1
	var polygon := PackedVector2Array()
	var half_width := 0.0
	var base := -1.0
	for p in points:
		var local := _frame.affine_inverse()*Map.ground_pos(p.x,p.y)
		polygon.append(Vector2(local.x,local.z))
		half_width = maxf(half_width,absf(local.z))
		base = minf(base,local.y-0.3)
	var height := clampf(float(data.h),2.8,8.4)
	var rise := clampf(half_width*0.75,1.2,5.5)
	var colour: Color = PLASTER[id%PLASTER.size()]
	var roof_colour := Color(0.45,0.32,0.26) if id%3 else Color(0.32,0.34,0.35)
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		var edge := b-a
		var normal := Vector3(edge.y,0,-edge.x).normalized()
		var low_a := Vector3(a.x,base,a.y)
		var low_b := Vector3(b.x,base,b.y)
		var top_a := Vector3(a.x,_roof_y(a.y,height,rise,half_width),a.y)
		var top_b := Vector3(b.x,_roof_y(b.y,height,rise,half_width),b.y)
		_triangle("plaster",[low_a,low_b,top_b],normal,colour)
		_triangle("plaster",[low_a,top_b,top_a],normal,colour)
		# Add the ridge point to a gable edge crossing z=0.
		if a.y*b.y<0.0:
			var ridge := a.lerp(b,-a.y/(b.y-a.y))
			_triangle("plaster",[top_a,top_b,Vector3(ridge.x,height+rise,0)],normal,colour)
		if edge.length()<3.0: continue
		var middle := (a+b)*0.5
		var front := Transform3D(Basis(Vector3.UP,atan2(normal.x,normal.z)),Vector3(middle.x,0,middle.y))
		var columns := clampi(int(edge.length()/3.8),1,4)
		for floor_index in (2 if height>4.6 else 1):
			for column in columns:
				var x := (float(column)+0.5)/columns*edge.length()-edge.length()*0.5
				_window(front,x,1.5+floor_index*2.6,SHUTTERS[id%SHUTTERS.size()])
	for side in [-1.0,1.0]:
		var half := _clip_half(polygon,side)
		var triangles := Geometry2D.triangulate_polygon(half)
		var normal := Vector3(0,1,side*rise/maxf(half_width,0.1)).normalized()
		for i in range(0,triangles.size(),3):
			var vertices: Array = []
			for k in 3:
				var p := half[triangles[i+k]]
				vertices.append(Vector3(p.x,_roof_y(p.y,height,rise,half_width),p.y))
			_triangle("tiles",vertices,normal,roof_colour)

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

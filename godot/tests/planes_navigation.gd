extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Map.use_region("planes")
	Map._ensure()
	var game := Node3D.new()
	root.add_child(game)
	current_scene = game
	var region: NavigationRegion3D = await load("res://scripts/planes_navigation.gd").prepare(game)
	var map := region.get_navigation_map()
	var origin := Map.ground_pos(-111.8,18.9)
	var target := NavigationServer3D.map_get_closest_point(map,origin)
	var connected := 0
	for i in 24:
		var p := origin+Vector3(cos(i*TAU/24),0,sin(i*TAU/24))*40
		p.y = Map.ground_height(p.x,p.z)
		var at := NavigationServer3D.map_get_closest_point(map,p)
		var path := NavigationServer3D.map_get_path(map,at,target,true)
		if not path.is_empty() and path[-1].distance_to(target)<1.5: connected+=1
		print("NAV_SAMPLE ",i," deviation=",at.distance_to(p)," path=",path.size())
	print("NAV_CHECK connected=",connected)
	quit(0 if connected==24 else 1)

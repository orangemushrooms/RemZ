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
	var uphill := Map.ground_pos(310,-225)
	var uphill_at := NavigationServer3D.map_get_closest_point(map,uphill)
	var uphill_path := NavigationServer3D.map_get_path(map,target,uphill_at,true)
	var uphill_ok := uphill_at.distance_to(uphill)<3 and not uphill_path.is_empty() and uphill_path[-1].distance_to(uphill_at)<1.5
	print("NAV_UPHILL connected=",uphill_ok)
	print("PLANES_NAVIGATION_DONE checks=25 failures=%d" % (24-connected+(0 if uphill_ok else 1)))
	quit(0 if connected==24 and uphill_ok else 1)

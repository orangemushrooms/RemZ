extends SceneTree
var selection: MapSelection
func _initialize() -> void: call_deferred("run")
func shot(file: String) -> void:
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/campaign/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + file + ".png")
func run() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	selection = MapSelection.new()
	selection.campaign = Campaign.new()
	layer.add_child(selection)
	await shot("selection-en")
	selection.atlas._hover("core")
	await create_timer(0.5).timeout
	await shot("selection-locked")
	selection.atlas._hover("")
	Lang.set_language("de")
	await shot("selection-de")
	root.size = Vector2i(1280,720)
	await shot("selection-720p")
	root.size = Vector2i(2560,1080)
	await shot("selection-ultrawide")
	root.size = Vector2i(1600,900)
	selection.campaign.record_wave(25, "Normal")
	selection.refresh()
	await shot("selection-secured")
	var clock_before := selection.atlas.clock
	await create_timer(1.0).timeout
	await shot("selection-motion")
	print("CAMPAIGN_VISUAL_DONE checks=1 failures=", 0 if selection.atlas.clock > clock_before else 1)
	quit()

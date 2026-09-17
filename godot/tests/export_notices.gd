extends SceneTree

func _initialize() -> void:
	var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("builds/windows")
	DirAccess.make_dir_recursive_absolute(folder)
	var output := FileAccess.open(folder.path_join("GODOT-LICENSES.txt"), FileAccess.WRITE)
	if not output:
		push_error("Unable to write engine license notices")
		quit(1)
		return
	output.store_string("Godot Engine\n\n" + Engine.get_license_text() + "\n\n")
	for part: Dictionary in Engine.get_copyright_info():
		output.store_string(str(part) + "\n")
	for name: String in Engine.get_license_info():
		output.store_string("\n" + name + "\n" + Engine.get_license_info()[name] + "\n")
	print("LICENSE_NOTICES_DONE")
	quit()

@tool
extends EditorExportPlugin
## Ensures JSON map files are included in web/other exports at correct paths.
## Godot's dependency scanner doesn't find files loaded via FileAccess.open(path)
## with string paths. add_file() guarantees they're at res://resources/maps/...

const MAPS_DIR: String = "res://resources/maps"


func _get_name() -> String:
	return "Cosmos Export"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return true


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	_add_json_files_in_dir(MAPS_DIR)


func _add_json_files_in_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_warning("Cosmos Export: Cannot open directory: %s" % dir_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				_add_json_files_in_dir(full_path)
		elif file_name.to_lower().ends_with(".json"):
			_add_json_file(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _add_json_file(json_path: String) -> void:
	if not FileAccess.file_exists(json_path):
		return
	var file: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		push_warning("Cosmos Export: Failed to read: %s" % json_path)
		return
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	add_file(json_path, data, false)

extends Node
## Debug log utility for Cursor debug mode.
## Writes NDJSON lines to .cursor/debug.log for runtime inspection.

const LOG_PATH: String = "/Users/sterlinglong/NonCloud/PAZA/Projects/cosmos-root/.cursor/debug.log"


func _ready() -> void:
	#region agent log
	var project_root: String = ProjectSettings.globalize_path("res://")
	write_inner("debug_log.gd:_ready", "DebugLog autoload ready", {"project_root": project_root})
	var user_path: String = OS.get_user_data_dir().path_join("debug_cursor.log")
	var user_file: FileAccess = FileAccess.open(user_path, FileAccess.WRITE)
	if user_file:
		user_file.store_line(JSON.stringify({"message": "DebugLog ready", "project_root": project_root}))
		user_file.close()
	print("[DebugLog] Autoload ready. Logs: ", LOG_PATH, " and user://debug_cursor.log = ", user_path)
	#endregion


static func write(location: String, message: String, data: Dictionary = {}) -> void:
	write_inner(location, message, data)


static func write_inner(location: String, message: String, data: Dictionary) -> void:
	var payload: Dictionary = {
		"timestamp": int(Time.get_ticks_msec()),
		"location": location,
		"message": message,
		"data": data
	}
	var line: String = JSON.stringify(payload)
	var abs_path: String = LOG_PATH
	var dir: String = abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var user_path: String = OS.get_user_data_dir().path_join("debug_cursor.log")
	for path in [abs_path, user_path]:
		var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open(path, FileAccess.WRITE)
		if f:
			if f.get_length() > 0:
				f.seek_end()
			f.store_line(line)
			f.close()

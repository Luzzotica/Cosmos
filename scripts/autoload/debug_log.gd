class_name DebugLog
extends Node
## Static debug logging for Cursor debug mode and runtime investigation.
## Writes NDJSON to .cursor/debug.log. Use: DebugLog.write(location, message, data)

## Write a log entry (NDJSON format). Static for use without autoload.
## location: e.g. "script.gd:func_name"
## message: short human-readable message
## data: optional dict (add hypothesisId, runId for agent runs)
static func write(location: String, message: String, data: Dictionary = {}) -> void:
	var payload: Dictionary = data.duplicate()
	payload["timestamp"] = Time.get_ticks_msec()
	payload["location"] = location
	payload["message"] = message
	# Write to workspace .cursor (parent of project dir) for Cursor debug mode
	var proj_dir: String = ProjectSettings.globalize_path("res://").get_base_dir()
	var workspace_dir: String = proj_dir.get_base_dir()
	var dir_path: String = workspace_dir.path_join(".cursor")
	var path: String = dir_path.path_join("debug.log")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(payload))
		f.close()

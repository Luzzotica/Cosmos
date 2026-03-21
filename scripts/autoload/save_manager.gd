extends Node
## Persistent save system for level unlocks and story flags.
## Supports multiple save slots at user://saves/slot_N.json.

const SLOT_COUNT: int = 3
const SAVES_DIR: String = "user://saves"
const LEGACY_SAVE_PATH: String = "user://cosmos_save.json"
const MANIFEST_PATH: String = "res://resources/maps/story_campaign_manifest.json"

var levels_beaten: Dictionary = {}  # map_id -> { outcome, extraction, timestamp }
var story_flags: Dictionary = {}  # arbitrary string keys for choices, endings, etc.
var highest_unlocked_index: int = 0  # index in ordered_map_ids
var current_slot: int = 1  # 1-based

var _ordered_map_ids: Array = []
var _manifest_loaded: bool = false


func _ready() -> void:
	_load_manifest()
	_migrate_legacy_save_if_needed()
	load_save()


func _get_slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVES_DIR, slot]


func _ensure_saves_dir() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir and not dir.dir_exists("saves"):
		DirAccess.make_dir_recursive_absolute(SAVES_DIR)


func _migrate_legacy_save_if_needed() -> void:
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	_ensure_saves_dir()
	var slot1_path: String = _get_slot_path(1)
	if FileAccess.file_exists(slot1_path):
		return  # Already migrated
	var file: FileAccess = FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var json_text: String = file.get_as_text()
	file.close()
	var dest: FileAccess = FileAccess.open(slot1_path, FileAccess.WRITE)
	if not dest:
		return
	dest.store_string(json_text)
	dest.close()
	DirAccess.remove_absolute(LEGACY_SAVE_PATH)


func _load_manifest() -> void:
	var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if not file:
		push_warning("SaveManager: Could not load manifest.")
		return
	var json_text: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	if parser.parse(json_text) != OK:
		push_warning("SaveManager: Failed to parse manifest.")
		return
	var data: Variant = parser.data
	if data is Dictionary:
		_ordered_map_ids = data.get("ordered_map_ids", [])
		_manifest_loaded = true


func save() -> bool:
	_ensure_saves_dir()
	var path: String = _get_slot_path(current_slot)
	var data: Dictionary = {
		"levels_beaten": levels_beaten,
		"story_flags": story_flags,
		"highest_unlocked_index": highest_unlocked_index
	}
	var json_text: String = JSON.stringify(data)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: Failed to open save file for writing: " + path)
		return false
	file.store_string(json_text)
	file.close()
	return true


func load_save() -> bool:
	var path: String = _get_slot_path(current_slot)
	if not FileAccess.file_exists(path):
		levels_beaten = {}
		story_flags = {}
		highest_unlocked_index = 0
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SaveManager: Failed to open save file for reading: " + path)
		return false
	var json_text: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	if parser.parse(json_text) != OK:
		push_error("SaveManager: Failed to parse save file.")
		return false
	var data: Variant = parser.data
	if not (data is Dictionary):
		return false
	levels_beaten = data.get("levels_beaten", {})
	story_flags = data.get("story_flags", {})
	highest_unlocked_index = int(data.get("highest_unlocked_index", 0))
	return true


func set_current_slot(slot: int) -> void:
	if slot < 1 or slot > SLOT_COUNT:
		return
	current_slot = slot
	load_save()


func get_slot_info(slot: int) -> Dictionary:
	if slot < 1 or slot > SLOT_COUNT:
		return {"exists": false, "last_played": 0, "levels_completed": 0, "preview_text": ""}
	var path: String = _get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"exists": false, "last_played": 0, "levels_completed": 0, "preview_text": "Empty"}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {"exists": false, "last_played": 0, "levels_completed": 0, "preview_text": "Empty"}
	var json_text: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	if parser.parse(json_text) != OK:
		return {"exists": false, "last_played": 0, "levels_completed": 0, "preview_text": "Empty"}
	var data: Variant = parser.data
	if not (data is Dictionary):
		return {"exists": false, "last_played": 0, "levels_completed": 0, "preview_text": "Empty"}
	var lb: Dictionary = data.get("levels_beaten", {})
	var completed: int = 0
	var last_ts: int = 0
	for _map_id in lb:
		var entry: Dictionary = lb[_map_id]
		if String(entry.get("outcome", "")) == "victory":
			completed += 1
		var ts: int = int(entry.get("timestamp", 0))
		if ts > last_ts:
			last_ts = ts
	var total: int = _ordered_map_ids.size() if _manifest_loaded else 12
	var preview: String = "Level %d of %d" % [completed, total]
	if last_ts > 0:
		preview += " - " + Time.get_date_string_from_unix_time(last_ts)
	return {"exists": true, "last_played": last_ts, "levels_completed": completed, "preview_text": preview}


func create_new_slot(slot: int) -> void:
	if slot < 1 or slot > SLOT_COUNT:
		return
	levels_beaten = {}
	story_flags = {}
	highest_unlocked_index = 0
	current_slot = slot
	save()


func delete_slot(slot: int) -> void:
	if slot < 1 or slot > SLOT_COUNT:
		return
	var path: String = _get_slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if current_slot == slot:
		levels_beaten = {}
		story_flags = {}
		highest_unlocked_index = 0


func get_flag(key: String) -> Variant:
	return story_flags.get(key, null)


func set_flag(key: String, value: Variant) -> void:
	story_flags[key] = value
	save()


func is_level_unlocked(map_id: String) -> bool:
	if not _manifest_loaded:
		return true  # Fallback: allow all if manifest missing
	var idx: int = _ordered_map_ids.find(map_id)
	if idx < 0:
		return true  # Unknown map: allow
	if idx == 0:
		return true  # Tutorial always unlocked
	if idx <= highest_unlocked_index:
		return true
	# Branch maps (site 10, epilogue) are unlocked when site 9 is beaten
	# Both branches unlock so player can replay either ending
	if _is_site_09_beaten():
		if map_id == "story_site_10_finale" or map_id == "story_epilogue_break_chain":
			return true
	return false


func _is_site_09_beaten() -> bool:
	var entry: Dictionary = levels_beaten.get("story_site_09_choice", {})
	return String(entry.get("outcome", "")) == "victory"


func record_level_complete(map_id: String, outcome: String, extraction: String = "full") -> void:
	if outcome != "victory" and outcome != "defeat":
		return
	var entry: Dictionary = {
		"outcome": outcome,
		"extraction": extraction if extraction in ["full", "partial", "none"] else "full",
		"timestamp": int(Time.get_unix_time_from_system())
	}
	levels_beaten[map_id] = entry
	if outcome == "victory":
		_update_highest_unlocked(map_id)
	save()


func _update_highest_unlocked(completed_map_id: String) -> void:
	var idx: int = _ordered_map_ids.find(completed_map_id)
	if idx < 0:
		return
	# For site 9, unlock both branches so player can replay either ending
	if completed_map_id == "story_site_09_choice":
		var finale_idx: int = _ordered_map_ids.find("story_site_10_finale")
		var epilogue_idx: int = _ordered_map_ids.find("story_epilogue_break_chain")
		if finale_idx >= 0:
			highest_unlocked_index = max(highest_unlocked_index, finale_idx)
		if epilogue_idx >= 0:
			highest_unlocked_index = max(highest_unlocked_index, epilogue_idx)
		return
	# Linear: unlock next
	var next_idx: int = idx + 1
	if next_idx < _ordered_map_ids.size():
		highest_unlocked_index = max(highest_unlocked_index, next_idx)


func is_level_beaten(map_id: String) -> bool:
	var entry: Dictionary = levels_beaten.get(map_id, {})
	return String(entry.get("outcome", "")) == "victory"


func get_level_entry(map_id: String) -> Dictionary:
	return levels_beaten.get(map_id, {})

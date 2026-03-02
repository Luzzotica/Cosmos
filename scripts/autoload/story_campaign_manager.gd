extends Node
class_name StoryCampaignManagerClass
## Maintains story campaign progression and map selection.

const DEFAULT_MANIFEST_PATH: String = "res://resources/maps/story_campaign_manifest.json"

var manifest: Dictionary = {}
var current_index: int = 0
var finale_choice: String = "continue"


func _ready() -> void:
	load_manifest(DEFAULT_MANIFEST_PATH)


func load_manifest(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("Story campaign manifest missing: %s" % path)
		return false
	var json_text: String = file.get_as_text()
	file.close()

	var parser: JSON = JSON.new()
	var parse_err: Error = parser.parse(json_text)
	if parse_err != OK:
		push_error("Failed to parse story campaign manifest: %s" % parser.get_error_message())
		return false

	var data: Variant = parser.data
	if not (data is Dictionary):
		push_error("Story campaign manifest is not an object")
		return false
	manifest = data
	current_index = 0
	finale_choice = "continue"
	return true


func reset_progress() -> void:
	current_index = 0
	finale_choice = "continue"


func set_finale_choice(choice: String) -> void:
	if choice == "continue" or choice == "break_chain":
		finale_choice = choice


func get_current_story_map_path() -> String:
	var ordered: Array = manifest.get("ordered_map_ids", [])
	if current_index < 0 or current_index >= ordered.size():
		return ""
	var map_id: String = String(ordered[current_index])
	return _resolve_map_id(map_id)


func get_current_story_entry() -> Dictionary:
	var ordered: Array = manifest.get("ordered_map_ids", [])
	if current_index < 0 or current_index >= ordered.size():
		return {}
	var map_id: String = String(ordered[current_index])
	return _get_entry_by_id(map_id)


func advance_story() -> void:
	var ordered: Array = manifest.get("ordered_map_ids", [])
	if ordered.is_empty():
		return

	var current_entry: Dictionary = get_current_story_entry()
	var current_id: String = String(current_entry.get("id", ""))
	if current_id == "story_site_09_choice":
		if finale_choice == "break_chain":
			current_index = ordered.find("story_epilogue_break_chain")
			if current_index == -1:
				current_index = ordered.size() - 1
			return
		current_index = ordered.find("story_site_10_finale")
		if current_index == -1:
			current_index = min(current_index + 1, ordered.size() - 1)
		return

	current_index = min(current_index + 1, ordered.size() - 1)


func _resolve_map_id(map_id: String) -> String:
	var entry: Dictionary = _get_entry_by_id(map_id)
	if entry.is_empty():
		return ""
	return String(entry.get("map_path", ""))


func _get_entry_by_id(map_id: String) -> Dictionary:
	var entries: Array = manifest.get("maps", [])
	for entry_variant in entries:
		if entry_variant is Dictionary:
			var entry: Dictionary = entry_variant
			if String(entry.get("id", "")) == map_id:
				return entry
	return {}

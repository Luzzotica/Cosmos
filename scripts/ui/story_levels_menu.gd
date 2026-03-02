extends Control
class_name StoryLevelsMenu

@onready var list: ItemList = $Margin/VBox/LevelList
@onready var play_button: Button = $Margin/VBox/ButtonRow/PlayButton
@onready var back_button: Button = $Margin/VBox/ButtonRow/BackButton
@onready var status_label: Label = $Margin/VBox/StatusLabel

var _entries: Array[Dictionary] = []


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_populate_levels()


func _populate_levels() -> void:
	list.clear()
	_entries.clear()
	var story_manager: Node = get_node_or_null("/root/StoryCampaignManager")
	if story_manager == null:
		status_label.text = "Story campaign manager missing."
		return

	var manifest: Dictionary = story_manager.get("manifest")
	var maps: Array = manifest.get("maps", [])
	for entry_variant in maps:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		_entries.append(entry)
		var title: String = String(entry.get("id", "unnamed"))
		var chapter: String = String(entry.get("chapter", ""))
		list.add_item("%s  (%s)" % [title, chapter])

	if _entries.is_empty():
		status_label.text = "No story levels found in manifest."
	else:
		list.select(0)
		status_label.text = "Select a story level to launch."


func _on_play_pressed() -> void:
	if _entries.is_empty():
		status_label.text = "No level selected."
		return
	var selected: PackedInt32Array = list.get_selected_items()
	if selected.is_empty():
		status_label.text = "Choose a level first."
		return
	var idx: int = selected[0]
	if idx < 0 or idx >= _entries.size():
		status_label.text = "Invalid selection."
		return

	var entry: Dictionary = _entries[idx]
	var map_path: String = String(entry.get("map_path", ""))
	var session: Node = get_node_or_null("/root/GameSession")
	if session and session.has_method("start_story"):
		session.call("start_story", map_path)
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/game/main.tscn")


func _on_back_pressed() -> void:
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/ui/main_menu.tscn")

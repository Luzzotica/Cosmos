extends Node
class_name GameSessionClass
## Stores launch-mode data between menu scenes and gameplay.

enum LaunchMode {
	STORY,
	EDITOR
}

var launch_mode: LaunchMode = LaunchMode.STORY
var selected_story_map_path: String = ""
var selected_story_map_id: String = ""
var selected_editor_map_path: String = ""


func start_story(map_path: String = "", map_id: String = "") -> void:
	launch_mode = LaunchMode.STORY
	selected_story_map_path = map_path
	selected_story_map_id = map_id
	selected_editor_map_path = ""


func start_editor(map_path: String = "") -> void:
	launch_mode = LaunchMode.EDITOR
	selected_editor_map_path = map_path
	selected_story_map_path = ""

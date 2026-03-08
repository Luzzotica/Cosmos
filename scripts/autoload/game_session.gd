extends Node
class_name GameSessionClass
## Stores launch-mode data between menu scenes and gameplay.

enum LaunchMode {
	MAIN_MENU,
	STORY,
	EDITOR
}

var launch_mode: LaunchMode = LaunchMode.MAIN_MENU
var selected_story_map_path: String = ""
var selected_editor_map_path: String = ""


func start_main_menu() -> void:
	launch_mode = LaunchMode.MAIN_MENU
	selected_story_map_path = ""
	selected_editor_map_path = ""


func start_story(map_path: String = "") -> void:
	launch_mode = LaunchMode.STORY
	selected_story_map_path = map_path
	selected_editor_map_path = ""


func start_editor(map_path: String = "") -> void:
	launch_mode = LaunchMode.EDITOR
	selected_editor_map_path = map_path
	selected_story_map_path = ""

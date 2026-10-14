extends Node
class_name GameSessionClass
## Stores launch-mode data between menu scenes and gameplay.

enum LaunchMode {
	STORY,
	EDITOR,
	ENDLESS
}

var launch_mode: LaunchMode = LaunchMode.STORY
var selected_story_map_path: String = ""
var selected_story_map_id: String = ""
var selected_editor_map_path: String = ""
var endless_seed: int = 0
## Last selected endless tier: [code]easy[/code] | [code]normal[/code] | [code]hard[/code] | [code]impossible[/code]
var endless_difficulty_id: String = "normal"


func start_story(map_path: String = "", map_id: String = "") -> void:
	launch_mode = LaunchMode.STORY
	selected_story_map_path = map_path
	selected_story_map_id = map_id
	selected_editor_map_path = ""


func start_editor(map_path: String = "") -> void:
	launch_mode = LaunchMode.EDITOR
	selected_editor_map_path = map_path
	selected_story_map_path = ""
	selected_story_map_id = ""


func start_endless(seed: int = 0, difficulty_id: String = "normal") -> void:
	launch_mode = LaunchMode.ENDLESS
	selected_story_map_path = ""
	selected_story_map_id = ""
	selected_editor_map_path = ""
	endless_difficulty_id = difficulty_id
	if seed == 0:
		endless_seed = randi()
	else:
		endless_seed = seed

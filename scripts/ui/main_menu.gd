extends Control
class_name MainMenu

@onready var story_levels_button: Button = $Center/VBox/StoryLevelsButton
@onready var map_editor_button: Button = $Center/VBox/MapEditorButton
@onready var quit_button: Button = $Center/VBox/QuitButton


func _ready() -> void:
	story_levels_button.pressed.connect(_on_story_levels_pressed)
	map_editor_button.pressed.connect(_on_map_editor_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_story_levels_pressed() -> void:
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/ui/story_levels_menu.tscn")


func _on_map_editor_pressed() -> void:
	var session: Node = get_node_or_null("/root/GameSession")
	if session and session.has_method("start_editor"):
		session.call("start_editor")
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/game/main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()

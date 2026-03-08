extends CanvasLayer
## Main menu overlay (gradient + buttons). Shown when Main runs in main menu mode.

@onready var story_levels_button: Button = $LeftPanel/CenterV/VBox/StoryLevelsButton
@onready var map_editor_button: Button = $LeftPanel/CenterV/VBox/MapEditorButton
@onready var quit_button: Button = $LeftPanel/CenterV/VBox/QuitButton


func _ready() -> void:
	story_levels_button.pressed.connect(_on_story_levels_pressed)
	map_editor_button.pressed.connect(_on_map_editor_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_story_levels_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/story_levels_menu.tscn")


func _on_map_editor_pressed() -> void:
	if GameSession:
		GameSession.start_editor()
	get_tree().change_scene_to_file("res://scenes/game/main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()

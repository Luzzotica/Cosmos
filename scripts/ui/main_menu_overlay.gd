extends CanvasLayer
## Main menu overlay (gradient + buttons). Shown when Main runs in main menu mode.

@onready var story_levels_button: Button = $LeftPanel/CenterV/VBox/StoryLevelsButton
@onready var quit_button: Button = $LeftPanel/CenterV/VBox/QuitButton


func _ready() -> void:
	story_levels_button.pressed.connect(_on_story_levels_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_button.visible = OS.get_name() != "Web"


func _on_story_levels_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()

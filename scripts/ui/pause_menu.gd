extends Control
class_name PauseMenu
## Pause menu shown while the game is paused.

@onready var resume_button: Button = $Panel/VBoxContainer/ResumeButton
@onready var restart_button: Button = $Panel/VBoxContainer/RestartButton
@onready var quit_button: Button = $Panel/VBoxContainer/QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	GameState.pause_changed.connect(_on_pause_changed)
	GameState.game_over.connect(_on_game_over)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			_on_resume_pressed()
			get_viewport().set_input_as_handled()


func _on_pause_changed(paused: bool) -> void:
	if GameState.is_game_over:
		visible = false
		return
	visible = paused
	if paused:
		resume_button.grab_focus()


func _on_game_over() -> void:
	# Game over uses its own overlay and controls.
	visible = false


func _on_resume_pressed() -> void:
	_play_sfx_method("play_ui_confirm")
	GameState.set_paused(false)


func _on_restart_pressed() -> void:
	_play_sfx_method("play_ui_confirm")
	GameState.reset()
	call_deferred("_restart_game")


func _on_quit_pressed() -> void:
	_play_sfx_method("play_ui_confirm")
	GameState.set_paused(false)
	if GameSession:
		GameSession.start_main_menu()
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/game/main.tscn")


func _restart_game() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var err: Error = tree.change_scene_to_file("res://scenes/game/main.tscn")
	if err != OK:
		push_error("Failed to restart from pause menu. Error code: %d" % err)


func _play_sfx_method(method_name: String) -> void:
	var sfx_manager: Node = get_node_or_null("/root/SfxManager")
	if sfx_manager and sfx_manager.has_method(method_name):
		sfx_manager.call(method_name)

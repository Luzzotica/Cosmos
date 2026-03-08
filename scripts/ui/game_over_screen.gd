extends Control
class_name GameOverScreen
## Game Over Screen - Shows when all structures are destroyed

signal restart_requested

@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var message_label: Label = $Panel/VBoxContainer/MessageLabel
@onready var stats_label: Label = $Panel/VBoxContainer/StatsLabel
@onready var restart_button: Button = $Panel/VBoxContainer/RestartButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	restart_button.pressed.connect(_on_restart_pressed)
	restart_button.mouse_entered.connect(_on_restart_hovered)
	GameState.game_over.connect(_on_game_over)
	GameState.victory.connect(_on_victory)


func _on_game_over() -> void:
	if not GameState.is_victory:
		_show_result(false)


func _on_victory() -> void:
	_show_result(true)


func _show_result(is_victory: bool) -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	restart_button.grab_focus()

	var waves_survived: int = GameState.current_wave
	var time_survived: float = GameState.game_time
	var minutes: int = int(time_survived / 60.0)
	var seconds: int = int(time_survived) % 60

	if is_victory:
		title_label.text = "VICTORY"
		message_label.text = "Mission complete!"
		stats_label.text = "Waves Survived: %d\nTime: %02d:%02d\nMinerals: %d\nCompletion: %.1f%% (Tier: %d%%)" % [
			waves_survived,
			minutes,
			seconds,
			GameState.minerals,
			GameState.completion_percent,
			GameState.highest_tier_reached
		]
	else:
		title_label.text = "GAME OVER"
		message_label.text = "All structures have been destroyed!"
		stats_label.text = "Waves Survived: %d\nTime: %02d:%02d\nMinerals Collected: %d" % [
			waves_survived,
			minutes,
			seconds,
			GameState.minerals
		]


func _on_restart_pressed() -> void:
	_play_sfx_method("play_ui_confirm")
	visible = false
	restart_requested.emit()
	
	# Reset game state
	GameState.reset()
	call_deferred("_restart_game")


func _on_restart_hovered() -> void:
	_play_sfx_method("play_ui_hover")


func _play_sfx_method(method_name: String) -> void:
	var sfx_manager: Node = get_node_or_null("/root/SfxManager")
	if sfx_manager and sfx_manager.has_method(method_name):
		sfx_manager.call(method_name)


func _restart_game() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var err: Error = tree.change_scene_to_file("res://scenes/game/main.tscn")
	if err != OK:
		push_error("Failed to restart game scene. Error code: %d" % err)

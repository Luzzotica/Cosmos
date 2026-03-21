extends Control
class_name GameOverScreen
## Game Over Screen - Shows when all structures are destroyed or on victory

signal restart_requested

@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var message_label: Label = $Panel/VBoxContainer/MessageLabel
@onready var stats_label: Label = $Panel/VBoxContainer/StatsLabel
@onready var restart_button: Button = $Panel/VBoxContainer/RestartButton
@onready var next_level_button: Button = $Panel/VBoxContainer/NextLevelButton
@onready var quit_button: Button = $Panel/VBoxContainer/QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	restart_button.pressed.connect(_on_restart_pressed)
	restart_button.mouse_entered.connect(_on_restart_hovered)
	next_level_button.pressed.connect(_on_next_level_pressed)
	next_level_button.mouse_entered.connect(_on_restart_hovered)
	quit_button.pressed.connect(_on_quit_pressed)
	quit_button.mouse_entered.connect(_on_restart_hovered)
	GameState.game_over.connect(_on_game_ended)
	GameState.victory.connect(_on_game_ended)


func _on_game_ended() -> void:
	show_game_over()


func show_game_over() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	if GameState.is_victory:
		title_label.text = "VICTORY"
		message_label.text = "Objectives complete!"
		next_level_button.visible = _is_story_mode()
		if next_level_button.visible:
			next_level_button.grab_focus()
		else:
			restart_button.grab_focus()
	else:
		title_label.text = "GAME OVER"
		message_label.text = "All structures have been destroyed!"
		next_level_button.visible = false
		restart_button.grab_focus()
	
	# Update stats
	var waves_survived: int = GameState.current_wave
	var time_survived: float = GameState.game_time
	var minutes: int = int(time_survived / 60.0)
	var seconds: int = int(time_survived) % 60
	
	stats_label.text = "Waves Survived: %d\nTime: %02d:%02d\nMinerals Collected: %d\nMinerals Mined: %d" % [
		waves_survived,
		minutes,
		seconds,
		GameState.minerals,
		GameState.total_minerals_mined
	]


func _is_story_mode() -> bool:
	var session: Node = get_node_or_null("/root/GameSession")
	if not session:
		return false
	return int(session.get("launch_mode")) == 0  # LaunchMode.STORY


func _on_next_level_pressed() -> void:
	_play_sfx_method("play_ui_confirm")
	visible = false
	var map_id: String = _get_current_map_id()
	if not map_id.is_empty():
		var save_manager: Node = get_node_or_null("/root/SaveManager")
		if save_manager and save_manager.has_method("record_level_complete"):
			save_manager.call("record_level_complete", map_id, "victory", "full")
	var story_manager: Node = get_node_or_null("/root/StoryCampaignManager")
	if story_manager and story_manager.has_method("advance_story"):
		story_manager.call("advance_story")
	var next_path: String = ""
	if story_manager and story_manager.has_method("get_current_story_map_path"):
		next_path = story_manager.call("get_current_story_map_path")
	GameState.reset()
	if not next_path.is_empty():
		var session: Node = get_node_or_null("/root/GameSession")
		if session and session.has_method("start_story"):
			var entry: Dictionary = story_manager.call("get_current_story_entry")
			var map_path: String = String(entry.get("map_path", ""))
			var next_id: String = String(entry.get("id", ""))
			session.call("start_story", map_path, next_id)
		call_deferred("_restart_game")
	else:
		call_deferred("_go_to_map_select")


func _get_current_map_id() -> String:
	var session: Node = get_node_or_null("/root/GameSession")
	if session:
		var val: Variant = session.get("selected_story_map_id")
		return str(val) if val else ""
	return ""


func _on_restart_pressed() -> void:
	_play_sfx_method("play_ui_confirm")
	visible = false
	restart_requested.emit()
	
	# Reset game state
	GameState.reset()
	call_deferred("_restart_game")


func _on_quit_pressed() -> void:
	_play_sfx_method("play_ui_confirm")
	visible = false
	GameState.reset()
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/ui/main_menu.tscn")


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


func _go_to_map_select() -> void:
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/ui/main_menu.tscn")

extends Control
class_name GameOverScreen
## Game Over Screen - Shows when all structures are destroyed

signal restart_requested

@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var message_label: Label = $Panel/VBoxContainer/MessageLabel
@onready var stats_label: Label = $Panel/VBoxContainer/StatsLabel
@onready var restart_button: Button = $Panel/VBoxContainer/RestartButton


func _ready() -> void:
	visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	GameState.game_over.connect(_on_game_over)


func _on_game_over() -> void:
	show_game_over()


func show_game_over() -> void:
	visible = true
	
	# Update stats
	var waves_survived: int = GameState.current_wave
	var time_survived: float = GameState.game_time
	var minutes: int = int(time_survived) / 60
	var seconds: int = int(time_survived) % 60
	
	stats_label.text = "Waves Survived: %d\nTime: %02d:%02d\nMinerals Collected: %d" % [
		waves_survived,
		minutes,
		seconds,
		GameState.minerals
	]


func _on_restart_pressed() -> void:
	visible = false
	restart_requested.emit()
	
	# Reset game state
	GameState.reset()
	
	# Reload the main scene
	get_tree().reload_current_scene()

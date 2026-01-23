extends Control
class_name GameHUD
## Main game HUD - Displays resources, wave info, and building buttons

signal build_button_pressed(building_type: String)

@onready var minerals_label: Label = $Margin/VBox/TopBar/ResourcesPanel/MarginContainer/VBoxContainer/MineralsLabel
@onready var energy_label: Label = $Margin/VBox/TopBar/ResourcesPanel/MarginContainer/VBoxContainer/EnergyLabel
@onready var wave_label: Label = $Margin/VBox/TopBar/WavePanel/MarginContainer/VBoxContainer/WaveLabel
@onready var wave_timer_label: Label = $Margin/VBox/TopBar/WavePanel/MarginContainer/VBoxContainer/WaveTimerLabel
@onready var build_panel: PanelContainer = $Margin/VBox/BottomBar/BuildPanel
@onready var build_buttons_container: HBoxContainer = $Margin/VBox/BottomBar/BuildPanel/MarginContainer/BuildButtons


func _ready() -> void:
	_connect_signals()
	_setup_build_buttons()
	_update_resources()
	_update_wave_info()


func _process(_delta: float) -> void:
	_update_wave_timer()


func _connect_signals() -> void:
	GameState.minerals_changed.connect(_on_minerals_changed)
	GameState.energy_changed.connect(_on_energy_changed)
	GameState.wave_started.connect(_on_wave_started)
	GameState.wave_ended.connect(_on_wave_ended)


func _setup_build_buttons() -> void:
	# Get building types from BuildManager
	var building_types: Array[String] = ["solar_panel", "power_node", "mining_station", "laser_turret"]
	
	for building_type in building_types:
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(180, 80)
		button.text = _format_building_name(building_type)
		button.add_theme_font_size_override("font_size", 28)
		button.pressed.connect(_on_build_button_pressed.bind(building_type))
		build_buttons_container.add_child(button)


func _format_building_name(building_type: String) -> String:
	return building_type.replace("_", " ").capitalize()


func _update_resources() -> void:
	if minerals_label:
		minerals_label.text = "Minerals: %d" % GameState.minerals
	if energy_label:
		var energy_percent: float = (GameState.energy / GameState.energy_capacity) * 100.0 if GameState.energy_capacity > 0 else 0.0
		energy_label.text = "Energy: %.0f / %.0f (%.0f%%)" % [GameState.energy, GameState.energy_capacity, energy_percent]


func _update_wave_info() -> void:
	if wave_label:
		if GameState.is_wave_in_progress:
			wave_label.text = "Wave %d - IN PROGRESS" % (GameState.current_wave + 1)
		else:
			wave_label.text = "Wave %d" % (GameState.current_wave + 1)


func _update_wave_timer() -> void:
	if wave_timer_label:
		if not GameState.is_wave_in_progress:
			wave_timer_label.text = "Next wave in: %.1fs" % GameState.time_until_next_wave
		else:
			wave_timer_label.text = "Wave active!"


func _on_minerals_changed(_amount: int) -> void:
	_update_resources()


func _on_energy_changed(_current: float, _capacity: float) -> void:
	_update_resources()


func _on_wave_started(_wave_number: int) -> void:
	_update_wave_info()


func _on_wave_ended(_wave_number: int) -> void:
	_update_wave_info()


func _on_build_button_pressed(building_type: String) -> void:
	build_button_pressed.emit(building_type)
	BuildManager.start_building(building_type)

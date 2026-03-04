extends Control
class_name GameHUD
## Main game HUD - Displays resources, wave info, and building buttons

signal build_button_pressed(building_type: String)

# Hotkeys for building (Q, E, R, T, Y, U)
const BUILD_HOTKEYS: Array[int] = [KEY_Q, KEY_E, KEY_R, KEY_T, KEY_Y, KEY_U]
const HOTKEY_LABELS: Array[String] = ["Q", "E", "R", "T", "Y", "U"]

@onready var minerals_label: Label = $Margin/VBox/TopBar/ResourcesPanel/MarginContainer/VBoxContainer/MineralsLabel
@onready var energy_label: Label = $Margin/VBox/TopBar/ResourcesPanel/MarginContainer/VBoxContainer/EnergyLabel
@onready var wave_label: Label = $Margin/VBox/TopBar/WavePanel/MarginContainer/VBoxContainer/WaveLabel
@onready var wave_timer_label: Label = $Margin/VBox/TopBar/WavePanel/MarginContainer/VBoxContainer/WaveTimerLabel
@onready var build_panel: PanelContainer = $Margin/VBox/BottomBar/BuildPanel
@onready var build_buttons_container: HBoxContainer = $Margin/VBox/BottomBar/BuildPanel/MarginContainer/BuildButtons
@onready var menu_button: Button = $Margin/VBox/TopBar/MenuButton

var _building_types: Array[String] = []
var _build_buttons: Array[Button] = []


func _ready() -> void:
	_connect_signals()
	_setup_build_buttons()
	_setup_menu_button()
	_update_resources()
	_update_wave_info()


func _unhandled_input(event: InputEvent) -> void:
	# Handle build hotkeys
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			for i in range(mini(BUILD_HOTKEYS.size(), _building_types.size())):
				if key_event.keycode == BUILD_HOTKEYS[i]:
					_on_build_button_pressed(_building_types[i])
					get_viewport().set_input_as_handled()
					break


func _process(_delta: float) -> void:
	_update_wave_timer()
	_update_energy_display()


func _connect_signals() -> void:
	GameState.minerals_changed.connect(_on_minerals_changed)
	GameState.energy_changed.connect(_on_energy_changed)
	GameState.wave_started.connect(_on_wave_started)
	GameState.wave_ended.connect(_on_wave_ended)


func _setup_build_buttons() -> void:
	# Get building types from BuildManager
	_building_types = ["solar_panel", "power_node", "mining_station", "laser_turret"]
	
	for i in range(_building_types.size()):
		var building_type: String = _building_types[i]
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(200, 80)
		
		# Add hotkey label if available
		var hotkey_text: String = ""
		if i < HOTKEY_LABELS.size():
			hotkey_text = " (%s)" % HOTKEY_LABELS[i]
		
		button.text = _format_building_name(building_type) + hotkey_text
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(_on_build_button_pressed.bind(building_type))
		button.mouse_entered.connect(_on_build_button_hovered)
		build_buttons_container.add_child(button)
		_build_buttons.append(button)


func _setup_menu_button() -> void:
	if menu_button:
		menu_button.pressed.connect(_on_menu_button_pressed)
		menu_button.mouse_entered.connect(_on_build_button_hovered)


func _on_menu_button_pressed() -> void:
	if GameState.is_game_over:
		return
	_play_sfx_method("play_ui_confirm")
	GameState.set_paused(true)


func _format_building_name(building_type: String) -> String:
	return building_type.replace("_", " ").capitalize()


func _update_resources() -> void:
	_update_minerals_display()
	_update_energy_display()


func _update_minerals_display() -> void:
	if minerals_label:
		minerals_label.text = "Minerals: %d" % GameState.minerals


func _update_energy_display() -> void:
	if not energy_label:
		return
	
	var current_energy: float = 0.0
	var max_energy: float = 0.0
	if PowerGraphManager:
		current_energy = PowerGraphManager.get_power_current()
		max_energy = PowerGraphManager.get_power_capacity()
	
	var energy_percent: float = (current_energy / max_energy) * 100.0 if max_energy > 0.0 else 0.0
	energy_label.text = "Energy: %.0f / %.0f (%.0f%%)" % [current_energy, max_energy, energy_percent]


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
	_update_minerals_display()


func _on_energy_changed(_current: float, _capacity: float) -> void:
	_update_energy_display()


func _on_wave_started(_wave_number: int) -> void:
	_update_wave_info()


func _on_wave_ended(_wave_number: int) -> void:
	_update_wave_info()


func _on_build_button_pressed(building_type: String) -> void:
	_play_sfx_method("play_ui_confirm")
	build_button_pressed.emit(building_type)
	BuildManager.start_building(building_type)


func _on_build_button_hovered() -> void:
	_play_sfx_method("play_ui_hover")


func _play_sfx_method(method_name: String) -> void:
	var sfx_manager: Node = get_node_or_null("/root/SfxManager")
	if sfx_manager and sfx_manager.has_method(method_name):
		sfx_manager.call(method_name)

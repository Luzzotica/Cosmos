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
@onready var next_wave_button: Button = $Margin/VBox/TopBar/WavePanel/MarginContainer/VBoxContainer/NextWaveButton
@onready var build_panel: PanelContainer = $Margin/VBox/BottomBar/BuildPanel
@onready var build_buttons_container: HBoxContainer = $Margin/VBox/BottomBar/BuildPanel/MarginContainer/BuildButtons
@onready var menu_button: Button = $Margin/VBox/TopBar/MenuButton

var _building_types: Array[String] = []
var _build_buttons: Array[Button] = []


func _ready() -> void:
	_connect_signals()
	if MapLoader:
		MapLoader.map_loaded.connect(_on_map_loaded)
	_rebuild_build_buttons(GameState.get_effective_buildable_types())
	_setup_menu_button()
	_setup_next_wave_button()
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


func _on_map_loaded(_map_data: MapData) -> void:
	_rebuild_build_buttons(GameState.get_effective_buildable_types())


func _rebuild_build_buttons(types: PackedStringArray) -> void:
	for child in build_buttons_container.get_children():
		child.queue_free()
	_building_types.clear()
	_build_buttons.clear()

	for i in range(types.size()):
		var building_type: String = types[i]
		_building_types.append(building_type)
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(200, 80)

		var hotkey_text: String = ""
		if i < HOTKEY_LABELS.size():
			hotkey_text = " (%s)" % HOTKEY_LABELS[i]

		var cost_text: String = _get_cost_text(building_type)
		button.text = _format_building_name(building_type) + hotkey_text + cost_text
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(_on_build_button_pressed.bind(building_type))
		button.mouse_entered.connect(_on_build_button_hovered)
		build_buttons_container.add_child(button)
		_build_buttons.append(button)


func _setup_menu_button() -> void:
	if not menu_button:
		return
	menu_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.32549, 0.0588235, 0.117647, 0.92)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.643137, 0.262745, 0.133333, 0.85)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_right = 3
	sb.corner_radius_bottom_left = 3
	sb.content_margin_left = 12
	sb.content_margin_top = 8
	sb.content_margin_right = 12
	sb.content_margin_bottom = 8
	menu_button.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.643137, 0.262745, 0.133333, 0.95)
	hover.border_color = Color(0.972549, 0.737255, 0.0156863, 1)
	menu_button.add_theme_stylebox_override("hover", hover)
	var pressed := sb.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.5, 0.12, 0.18, 0.96)
	pressed.border_color = Color(0.972549, 0.737255, 0.0156863, 0.9)
	menu_button.add_theme_stylebox_override("pressed", pressed)
	menu_button.pressed.connect(_on_menu_button_pressed)
	menu_button.mouse_entered.connect(_on_build_button_hovered)


func _setup_next_wave_button() -> void:
	if next_wave_button:
		next_wave_button.pressed.connect(_on_next_wave_button_pressed)
		next_wave_button.mouse_entered.connect(_on_build_button_hovered)


func _on_next_wave_button_pressed() -> void:
	if GameState.is_game_over or GameState.is_wave_in_progress or not GameState.wave_timer_enabled:
		return
	_play_sfx_method("play_ui_confirm")
	GameState.start_wave()


func _on_menu_button_pressed() -> void:
	if GameState.is_game_over:
		return
	_play_sfx_method("play_ui_confirm")
	GameState.set_session_state(GameState.SessionState.PAUSED)


func _format_building_name(building_type: String) -> String:
	return building_type.replace("_", " ").capitalize()


func _get_cost_text(building_type: String) -> String:
	if not BuildManager:
		return ""
	var data: Resource = BuildManager.get_building_data(building_type)
	if not data or not "cost" in data:
		return ""
	var cost: int = data.cost
	return "\n%d minerals" % cost


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
		if not GameState.wave_timer_enabled:
			wave_timer_label.text = "Next wave: after briefing"
		elif not GameState.is_wave_in_progress:
			wave_timer_label.text = "Next wave in: %.1fs" % GameState.time_until_next_wave
		else:
			wave_timer_label.text = "Wave active!"
	if next_wave_button:
		next_wave_button.visible = (
			OS.is_debug_build()
			and GameState.wave_timer_enabled
			and not GameState.is_wave_in_progress
			and not GameState.is_game_over
		)


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

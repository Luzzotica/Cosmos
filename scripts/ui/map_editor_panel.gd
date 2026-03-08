extends Control
class_name MapEditorPanel
## Map editor panel with GameHUD-aligned layout. Building | Asteroid | Erase modes.

signal save_requested
signal test_play_requested
signal close_requested
signal export_path_selected(path: String)
signal import_path_selected(path: String)
signal wave_designer_requested
signal structure_type_selected(building_type: String)

const MODE_BUILDING: String = "building"
const MODE_ASTEROID: String = "asteroid"
const MODE_ERASE: String = "erase"

# Hotkeys: buildings (Q E R T Y), modes (B A X), monolith in asteroid mode (Y)
const BUILD_HOTKEYS: Array[int] = [KEY_Q, KEY_E, KEY_R, KEY_T, KEY_Y]
const HOTKEY_LABELS: Array[String] = ["Q", "E", "R", "T", "Y"]

@onready var map_name: LineEdit = $Margin/VBox/TopBar/MapInfoPanel/Margin/VBox/MapName
@onready var biome: LineEdit = $Margin/VBox/TopBar/MapInfoPanel/Margin/VBox/MetaRow/Biome
@onready var difficulty: LineEdit = $Margin/VBox/TopBar/MapInfoPanel/Margin/VBox/MetaRow/Difficulty
@onready var wave_designer_button: Button = $Margin/VBox/TopBar/WaveDesignerButton
@onready var save_button: Button = $Margin/VBox/TopBar/ActionPanel/Margin/HBox/SaveButton
@onready var test_button: Button = $Margin/VBox/TopBar/ActionPanel/Margin/HBox/TestButton
@onready var export_button: Button = $Margin/VBox/TopBar/ActionPanel/Margin/HBox/ExportButton
@onready var import_button: Button = $Margin/VBox/TopBar/ActionPanel/Margin/HBox/ImportButton
@onready var close_button: Button = $Margin/VBox/TopBar/ActionPanel/Margin/HBox/CloseButton
@onready var status_label: Label = $Margin/VBox/TopBar/StatusLabel
@onready var building_mode_button: Button = $Margin/VBox/BottomBar/ModePanel/Margin/ModeVBox/ModeButtons/BuildingModeButton
@onready var asteroid_mode_button: Button = $Margin/VBox/BottomBar/ModePanel/Margin/ModeVBox/ModeButtons/AsteroidModeButton
@onready var erase_mode_button: Button = $Margin/VBox/BottomBar/ModePanel/Margin/ModeVBox/ModeButtons/EraseModeButton
@onready var building_content: HBoxContainer = $Margin/VBox/BottomBar/ModePanel/Margin/ModeVBox/ModeContent/BuildingContent
@onready var asteroid_content: HBoxContainer = $Margin/VBox/BottomBar/ModePanel/Margin/ModeVBox/ModeContent/AsteroidContent
@onready var monolith_button: Button = $Margin/VBox/BottomBar/ModePanel/Margin/ModeVBox/ModeContent/AsteroidContent/MonolithButton
@onready var build_buttons: HBoxContainer = $Margin/VBox/BottomBar/ModePanel/Margin/ModeVBox/ModeContent/BuildingContent/BuildButtons
@onready var map_settings_button: Button = $Margin/VBox/TopBar/MapSettingsButton
@onready var map_settings_popup: PopupPanel = $MapSettingsPopup
@onready var act: LineEdit = $MapSettingsPopup/Margin/VBox/MetaRow/Act
@onready var chapter: LineEdit = $MapSettingsPopup/Margin/VBox/MetaRow/Chapter
@onready var partial_extract: CheckBox = $MapSettingsPopup/Margin/VBox/MetaRow/PartialExtraction
@onready var carryover_minerals: SpinBox = $MapSettingsPopup/Margin/VBox/CarryoverRow/CarryoverMinerals
@onready var carryover_energy: SpinBox = $MapSettingsPopup/Margin/VBox/CarryoverRow/CarryoverEnergy
@onready var export_dialog: FileDialog = $ExportDialog
@onready var import_dialog: FileDialog = $ImportDialog

var _structure_types: PackedStringArray = PackedStringArray()
var _selected_structure_type: String = "solar_panel"
var _build_buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	_setup_mode_buttons()
	_setup_asteroid_content()
	_setup_hotkey_labels()
	save_button.pressed.connect(func() -> void: save_requested.emit())
	test_button.pressed.connect(func() -> void: test_play_requested.emit())
	close_button.pressed.connect(func() -> void: close_requested.emit())
	wave_designer_button.pressed.connect(func() -> void: wave_designer_requested.emit())
	map_settings_button.pressed.connect(func() -> void: map_settings_popup.popup_centered())
	export_button.pressed.connect(func() -> void: export_dialog.popup_centered_ratio(0.6))
	import_button.pressed.connect(func() -> void: import_dialog.popup_centered_ratio(0.6))
	export_dialog.file_selected.connect(func(path: String) -> void: export_path_selected.emit(path))
	import_dialog.file_selected.connect(func(path: String) -> void: import_path_selected.emit(path))


func _setup_mode_buttons() -> void:
	building_mode_button.toggled.connect(_on_building_mode_toggled)
	asteroid_mode_button.toggled.connect(_on_asteroid_mode_toggled)
	erase_mode_button.toggled.connect(_on_erase_mode_toggled)
	# Ensure building mode is default and content is visible
	building_mode_button.button_pressed = true
	_on_building_mode_toggled(true)


func _on_building_mode_toggled(toggled_on: bool) -> void:
	if toggled_on:
		asteroid_mode_button.button_pressed = false
		erase_mode_button.button_pressed = false
		building_content.visible = true
		asteroid_content.visible = false


func _on_asteroid_mode_toggled(toggled_on: bool) -> void:
	if toggled_on:
		building_mode_button.button_pressed = false
		erase_mode_button.button_pressed = false
		building_content.visible = false
		asteroid_content.visible = true


func _on_erase_mode_toggled(toggled_on: bool) -> void:
	if toggled_on:
		building_mode_button.button_pressed = false
		asteroid_mode_button.button_pressed = false
		building_content.visible = false
		asteroid_content.visible = false


func _setup_asteroid_content() -> void:
	if monolith_button:
		monolith_button.pressed.connect(_on_monolith_button_pressed)


func _on_monolith_button_pressed() -> void:
	structure_type_selected.emit("monolith")


func _setup_hotkey_labels() -> void:
	building_mode_button.text = "Buildings (B)"
	asteroid_mode_button.text = "Asteroids (A)"
	erase_mode_button.text = "Erase (X)"


func configure_structure_types(types: PackedStringArray) -> void:
	_structure_types = types
	for btn in _build_buttons:
		btn.queue_free()
	_build_buttons.clear()

	for i in range(types.size()):
		var t: String = types[i]
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(120, 50)
		button.toggle_mode = true
		var hotkey_text: String = " (%s)" % HOTKEY_LABELS[i] if i < HOTKEY_LABELS.size() else ""
		button.text = t.replace("_", " ").capitalize() + hotkey_text
		button.add_theme_font_size_override("font_size", 18)
		if t == _selected_structure_type:
			button.button_pressed = true
		button.pressed.connect(_on_build_button_pressed.bind(t))
		build_buttons.add_child(button)
		_build_buttons.append(button)

	if _structure_types.size() > 0 and _selected_structure_type.is_empty():
		_selected_structure_type = _structure_types[0]
		if _build_buttons.size() > 0:
			_build_buttons[0].button_pressed = true


func _on_build_button_pressed(building_type: String) -> void:
	_selected_structure_type = building_type
	for i in range(_build_buttons.size()):
		_build_buttons[i].button_pressed = (_structure_types[i] == building_type)
	structure_type_selected.emit(building_type)


## Returns current editor mode: "building", "asteroid", or "erase"
func get_editor_mode() -> String:
	if erase_mode_button.button_pressed:
		return MODE_ERASE
	if asteroid_mode_button.button_pressed:
		return MODE_ASTEROID
	return MODE_BUILDING


## Legacy: maps to get_editor_mode for placement logic. "cloud"|"structure"|"erase"
func get_tool_mode() -> String:
	var mode: String = get_editor_mode()
	if mode == MODE_ERASE:
		return "erase"
	if mode == MODE_BUILDING:
		return "structure"
	return "cloud"


func get_structure_type() -> String:
	if _structure_types.is_empty():
		return "solar_panel"
	return _selected_structure_type


func get_map_metadata() -> Dictionary:
	return {
		"name": map_name.text.strip_edges(),
		"biome": biome.text.strip_edges(),
		"difficulty_band": difficulty.text.strip_edges(),
		"act": act.text.strip_edges(),
		"chapter": chapter.text.strip_edges(),
		"allow_partial_extraction": partial_extract.button_pressed,
		"target_carryover_minerals": int(carryover_minerals.value),
		"target_carryover_energy": carryover_energy.value
	}


func set_status(message: String) -> void:
	status_label.text = message


func apply_map_metadata(map_data: MapData) -> void:
	map_name.text = map_data.map_name
	biome.text = map_data.biome
	difficulty.text = map_data.difficulty_band
	act.text = map_data.act
	chapter.text = map_data.chapter
	partial_extract.button_pressed = map_data.allow_partial_extraction
	carryover_minerals.value = map_data.target_carryover_minerals
	carryover_energy.value = map_data.target_carryover_energy

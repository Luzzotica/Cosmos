extends Control
class_name MapEditorPanel
## Lightweight in-game panel used by MapEditorController.

signal save_requested
signal test_play_requested
signal close_requested
signal export_path_selected(path: String)
signal import_path_selected(path: String)

@onready var tool_select: OptionButton = $Panel/Margin/VBox/ToolSelect
@onready var structure_type_select: OptionButton = $Panel/Margin/VBox/StructureTypeSelect
@onready var asteroid_size: SpinBox = $Panel/Margin/VBox/AsteroidSize
@onready var asteroid_minerals: SpinBox = $Panel/Margin/VBox/AsteroidMinerals
@onready var cloud_radius: SpinBox = $Panel/Margin/VBox/CloudRadius
@onready var cloud_count: SpinBox = $Panel/Margin/VBox/CloudCount
@onready var map_name: LineEdit = $Panel/Margin/VBox/MapName
@onready var biome: LineEdit = $Panel/Margin/VBox/Biome
@onready var difficulty: LineEdit = $Panel/Margin/VBox/Difficulty
@onready var act: LineEdit = $Panel/Margin/VBox/Act
@onready var chapter: LineEdit = $Panel/Margin/VBox/Chapter
@onready var partial_extract: CheckBox = $Panel/Margin/VBox/PartialExtraction
@onready var carryover_minerals: SpinBox = $Panel/Margin/VBox/CarryoverMinerals
@onready var carryover_energy: SpinBox = $Panel/Margin/VBox/CarryoverEnergy
@onready var status_label: Label = $Panel/Margin/VBox/StatusLabel
@onready var save_button: Button = $Panel/Margin/VBox/ButtonRow/SaveButton
@onready var test_button: Button = $Panel/Margin/VBox/ButtonRow/TestButton
@onready var close_button: Button = $Panel/Margin/VBox/ButtonRow/CloseButton
@onready var export_button: Button = $Panel/Margin/VBox/FileRow/ExportButton
@onready var import_button: Button = $Panel/Margin/VBox/FileRow/ImportButton
@onready var export_dialog: FileDialog = $ExportDialog
@onready var import_dialog: FileDialog = $ImportDialog

var _tool_values: PackedStringArray = PackedStringArray(["asteroid", "cloud", "structure", "erase"])


func _ready() -> void:
	visible = false
	_populate_tool_options()
	save_button.pressed.connect(func() -> void: save_requested.emit())
	test_button.pressed.connect(func() -> void: test_play_requested.emit())
	close_button.pressed.connect(func() -> void: close_requested.emit())
	export_button.pressed.connect(func() -> void: export_dialog.popup_centered_ratio(0.6))
	import_button.pressed.connect(func() -> void: import_dialog.popup_centered_ratio(0.6))
	export_dialog.file_selected.connect(func(path: String) -> void: export_path_selected.emit(path))
	import_dialog.file_selected.connect(func(path: String) -> void: import_path_selected.emit(path))


func configure_structure_types(types: PackedStringArray) -> void:
	structure_type_select.clear()
	for structure_type in types:
		structure_type_select.add_item(structure_type)
	if structure_type_select.item_count == 0:
		structure_type_select.add_item("solar_panel")


func get_tool_mode() -> String:
	var idx: int = tool_select.selected
	if idx < 0 or idx >= _tool_values.size():
		return "asteroid"
	return _tool_values[idx]


func get_structure_type() -> String:
	if structure_type_select.item_count == 0:
		return "solar_panel"
	return structure_type_select.get_item_text(structure_type_select.selected)


func get_asteroid_size() -> float:
	return asteroid_size.value


func get_asteroid_minerals() -> float:
	return asteroid_minerals.value


func get_cloud_radius() -> float:
	return cloud_radius.value


func get_cloud_count() -> int:
	return int(cloud_count.value)


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


func _populate_tool_options() -> void:
	tool_select.clear()
	tool_select.add_item("Place Asteroid")
	tool_select.add_item("Paint Cloud")
	tool_select.add_item("Place Structure")
	tool_select.add_item("Erase")

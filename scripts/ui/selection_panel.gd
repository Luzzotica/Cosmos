extends PanelContainer
class_name SelectionPanel
## Panel that slides in from the left when an entity is selected

signal panel_shown
signal panel_hidden

const SLIDE_DURATION: float = 0.25
const HIDDEN_X_OFFSET: float = -400.0

const COLOR_PANEL_BG: Color = Color(0.0196078, 0.0784314, 0.152941, 0.95) # #051427
const COLOR_TEXT_MUTED: Color = Color(0.92, 0.95, 1.0, 1.0)
const COLOR_TEXT_PRIMARY: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TAG_ALLY: Color = Color(0.35, 1.0, 0.45, 1.0)
const COLOR_TAG_ENEMY: Color = Color(1.0, 0.28, 0.28, 1.0)
const COLOR_TAG_NEUTRAL: Color = Color(1.0, 0.9, 0.25, 1.0)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var faction_tag_label: Label = $MarginContainer/VBoxContainer/FactionTagLabel
@onready var info_container: VBoxContainer = $MarginContainer/VBoxContainer/InfoContainer
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthBar/HealthLabel

var _is_shown: bool = false
var _slide_tween: Tween = null
var _target_x: float = 0.0
var _style_box: StyleBoxFlat = null
var _last_details: Dictionary = {}


func _ready() -> void:
	# Create unique stylebox for color changes
	_style_box = StyleBoxFlat.new()
	_style_box.bg_color = COLOR_PANEL_BG
	_style_box.border_width_left = 2
	_style_box.border_width_top = 2
	_style_box.border_width_right = 2
	_style_box.border_width_bottom = 2
	_style_box.border_color = Color(0.972549, 0.737255, 0.0156863, 0.75)
	_style_box.corner_radius_top_left = 8
	_style_box.corner_radius_top_right = 8
	_style_box.corner_radius_bottom_left = 8
	_style_box.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", _style_box)
	
	# Ensure the panel and all children don't block mouse input to 3D world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_filter_recursive(self)
	
	# Store target position and hide off-screen
	_target_x = position.x
	position.x = HIDDEN_X_OFFSET
	visible = true
	modulate.a = 0.0
	
	# Connect to selection manager
	SelectionManager.primary_selection_changed.connect(_on_primary_selection_changed)
	SelectionManager.selection_details_changed.connect(_on_selection_details_changed)
	SelectionManager.selection_changed.connect(_on_selection_changed)
	SelectionManager.selection_cleared.connect(_on_selection_cleared)
	GameState.pause_changed.connect(_on_pause_changed)
	GameState.game_over.connect(_on_game_over)


func _set_mouse_filter_recursive(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_filter_recursive(child)


func show_panel() -> void:
	if _is_shown:
		return
	
	_is_shown = true
	
	if _slide_tween:
		_slide_tween.kill()
	
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.set_trans(Tween.TRANS_BACK)
	_slide_tween.tween_property(self, "position:x", _target_x, SLIDE_DURATION)
	_slide_tween.parallel().tween_property(self, "modulate:a", 1.0, SLIDE_DURATION * 0.5)
	_slide_tween.tween_callback(func(): panel_shown.emit())


func hide_panel() -> void:
	if not _is_shown:
		return
	
	_is_shown = false
	
	if _slide_tween:
		_slide_tween.kill()
	
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_IN)
	_slide_tween.set_trans(Tween.TRANS_BACK)
	_slide_tween.tween_property(self, "position:x", HIDDEN_X_OFFSET, SLIDE_DURATION)
	_slide_tween.parallel().tween_property(self, "modulate:a", 0.0, SLIDE_DURATION)
	_slide_tween.tween_callback(func(): panel_hidden.emit())


func _on_selection_changed(entity: Node3D, _entity_type: String) -> void:
	if not is_instance_valid(entity):
		hide_panel()
		return

	# Compatibility event for legacy selections.
	var details: Dictionary = SelectionManager.get_primary_selection_details()
	if details.is_empty():
		details = _legacy_to_normalized(SelectionManager.get_selection_info())
	_update_from_details(details)
	show_panel()


func _on_primary_selection_changed(_selectable: Node, details: Dictionary) -> void:
	_update_from_details(details)
	show_panel()


func _on_selection_details_changed(details: Dictionary) -> void:
	_update_from_details(details)


func _on_selection_cleared() -> void:
	_last_details = {}
	hide_panel()


func _on_pause_changed(paused: bool) -> void:
	if paused:
		hide_panel()


func _on_game_over() -> void:
	hide_panel()


func _update_faction_tag(faction: String) -> void:
	if not faction_tag_label:
		return
	match faction:
		"player", "ally", "friendly":
			faction_tag_label.text = "ALLY"
			faction_tag_label.add_theme_color_override("font_color", COLOR_TAG_ALLY)
		"enemy", "hostile":
			faction_tag_label.text = "ENEMY"
			faction_tag_label.add_theme_color_override("font_color", COLOR_TAG_ENEMY)
		"neutral":
			faction_tag_label.text = "NEUTRAL"
			faction_tag_label.add_theme_color_override("font_color", COLOR_TAG_NEUTRAL)
		_:
			faction_tag_label.text = "ALLY"
			faction_tag_label.add_theme_color_override("font_color", COLOR_TAG_ALLY)


func _update_from_details(details: Dictionary) -> void:
	if details.is_empty():
		return
	if details.hash() == _last_details.hash():
		return
	_last_details = details.duplicate(true)

	_update_faction_tag(str(details.get("faction", "player")).to_lower())

	if title_label:
		title_label.text = str(details.get("name", "Unknown"))

	_update_primary_bar(details)
	_rebuild_info_rows(details)


func _update_primary_bar(details: Dictionary) -> void:
	if not health_bar:
		return

	if details.has("health_current") and details.has("health_max"):
		var hp_current: float = float(details.get("health_current", 0.0))
		var hp_max: float = maxf(float(details.get("health_max", 1.0)), 1.0)
		health_bar.visible = true
		health_bar.value = (hp_current / hp_max) * 100.0
		if health_label:
			health_label.text = "%.0f / %.0f" % [hp_current, hp_max]
		return

	if details.has("resource_current") and details.has("resource_max"):
		var resource_current: float = float(details.get("resource_current", 0.0))
		var resource_max: float = maxf(float(details.get("resource_max", 1.0)), 1.0)
		health_bar.visible = true
		health_bar.value = (resource_current / resource_max) * 100.0
		if health_label:
			health_label.text = "%.0f / %.0f" % [resource_current, resource_max]
		return

	health_bar.visible = false


func _rebuild_info_rows(details: Dictionary) -> void:
	if not info_container:
		return

	for child in info_container.get_children():
		child.queue_free()

	_add_info_row("Category", str(details.get("category", "entity")).capitalize())
	_add_info_row("Faction", str(details.get("faction", "neutral")).capitalize())

	if details.has("stats"):
		for entry in details.stats:
			if entry is Dictionary and entry.has("label") and entry.has("value"):
				_add_info_row(str(entry.label), str(entry.value))


func _legacy_to_normalized(legacy: Dictionary) -> Dictionary:
	if legacy.is_empty():
		return {}

	var normalized: Dictionary = {
		"name": legacy.get("name", "Unknown"),
		"category": legacy.get("type", "entity"),
		"faction": legacy.get("faction", "neutral"),
		"stats": []
	}
	var stats: Array = normalized.get("stats", [])

	if legacy.has("health") and legacy.has("max_health"):
		normalized["health_current"] = legacy.health
		normalized["health_max"] = legacy.max_health
	if legacy.has("remaining_minerals") and legacy.has("total_minerals"):
		normalized["resource_current"] = legacy.remaining_minerals
		normalized["resource_max"] = legacy.total_minerals

	if legacy.has("building_type"):
		stats.append({"label": "Type", "value": legacy.building_type})
	if legacy.has("is_built"):
		stats.append({"label": "Status", "value": "Operational" if legacy.is_built else "Building"})
	if legacy.has("damage"):
		stats.append({"label": "Damage", "value": str(legacy.damage)})
	if legacy.has("speed"):
		stats.append({"label": "Speed", "value": str(legacy.speed)})
	if legacy.has("size"):
		stats.append({"label": "Size", "value": str(legacy.size)})
	normalized["stats"] = stats

	return normalized


func _add_info_row(label_text: String, value_text: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	
	var label: Label = Label.new()
	label.text = label_text + ":"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 1)
	label.custom_minimum_size.x = 140
	row.add_child(label)
	
	var value: Label = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 28)
	value.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	value.add_theme_constant_override("outline_size", 1)
	row.add_child(value)
	
	info_container.add_child(row)

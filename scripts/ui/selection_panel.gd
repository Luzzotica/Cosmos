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
const COLOR_UPGRADE_BG: Color = Color(0.12, 0.06, 0.22, 0.95)
const COLOR_UPGRADE_BORDER: Color = Color(0.55, 0.35, 0.9, 0.8)
const COLOR_UPGRADE_DISABLED: Color = Color(0.5, 0.5, 0.5, 0.6)
const COLOR_UPGRADE_DONE: Color = Color(0.35, 0.8, 0.35, 0.8)

const C_UpgradesScript = preload("res://scripts/ecs/components/c_upgrades.gd")

const COLOR_SELL_BG: Color = Color(0.22, 0.06, 0.06, 0.95)
const COLOR_SELL_BORDER: Color = Color(0.9, 0.25, 0.25, 0.8)

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
var _upgrade_container: VBoxContainer = null
var _sell_container: VBoxContainer = null
var _upgrade_progress_bar: ProgressBar = null
var _selected_entity: Entity = null
var _upgrade_refresh_timer: float = 0.0
var _was_upgrading: bool = false
const UPGRADE_REFRESH_INTERVAL: float = 0.25


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
	
	var vbox: VBoxContainer = $MarginContainer/VBoxContainer
	if vbox:
		_upgrade_container = VBoxContainer.new()
		_upgrade_container.name = "UpgradeContainer"
		_upgrade_container.add_theme_constant_override("separation", 6)
		vbox.add_child(_upgrade_container)

		_sell_container = VBoxContainer.new()
		_sell_container.name = "SellContainer"
		_sell_container.add_theme_constant_override("separation", 6)
		vbox.add_child(_sell_container)

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


func _process(delta: float) -> void:
	if not _is_shown or _selected_entity == null:
		return
	var c_upgrades = _selected_entity.get_component(C_UpgradesScript)
	if c_upgrades == null:
		return
	var currently_upgrading: bool = c_upgrades.is_upgrading
	if not currently_upgrading:
		if _was_upgrading:
			_was_upgrading = false
			_rebuild_upgrade_rows()
		return
	_was_upgrading = true
	_upgrade_refresh_timer -= delta
	if _upgrade_refresh_timer <= 0.0:
		_upgrade_refresh_timer = UPGRADE_REFRESH_INTERVAL
		_rebuild_upgrade_rows()


func _on_selection_cleared() -> void:
	_last_details = {}
	_selected_entity = null
	_was_upgrading = false
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
	var prev_entity: Entity = _selected_entity
	_resolve_selected_entity()
	var entity_changed: bool = _selected_entity != prev_entity
	if not entity_changed and details.hash() == _last_details.hash():
		return
	_last_details = details.duplicate(true)
	_was_upgrading = false

	_update_faction_tag(str(details.get("faction", "player")).to_lower())

	if title_label:
		title_label.text = str(details.get("name", "Unknown"))

	_update_primary_bar(details)
	_rebuild_info_rows(details)
	_rebuild_upgrade_rows()
	_rebuild_sell_button(details)


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


func _resolve_selected_entity() -> void:
	_selected_entity = null
	var body: Node3D = SelectionManager.selected_entity
	if body == null or not is_instance_valid(body):
		return
	var parent: Node = body.get_parent()
	if parent is Entity:
		_selected_entity = parent as Entity


func _rebuild_upgrade_rows() -> void:
	if _upgrade_container == null:
		return
	for child in _upgrade_container.get_children():
		child.queue_free()
	_upgrade_progress_bar = null

	if _selected_entity == null or not is_instance_valid(_selected_entity):
		return
	var c_upgrades = _selected_entity.get_component(C_UpgradesScript)
	if c_upgrades == null:
		return

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	_upgrade_container.add_child(sep)

	var header := Label.new()
	header.text = "UPGRADES"
	header.add_theme_font_size_override("font_size", 26)
	header.add_theme_color_override("font_color", Color(0.7, 0.55, 1.0, 1.0))
	header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	header.add_theme_constant_override("outline_size", 1)
	_upgrade_container.add_child(header)

	if c_upgrades.is_upgrading:
		_build_upgrade_progress_ui(c_upgrades)
		return

	var mgr: Node = _get_upgrade_manager()
	if mgr == null:
		return
	var tree: Resource = mgr.get_tree_for_building(c_upgrades.upgrade_tree_id)
	if tree == null:
		return

	for node_data in tree.nodes:
		if c_upgrades.purchased_upgrades.has(node_data.id):
			_add_purchased_label(node_data)
			continue

	var available: Array = mgr.get_available_upgrades(_selected_entity)
	for node_data in available:
		_add_upgrade_button(node_data)


func _build_upgrade_progress_ui(c_upgrades) -> void:
	var mgr: Node = _get_upgrade_manager()
	var tree: Resource = mgr.get_tree_for_building(c_upgrades.upgrade_tree_id) if mgr else null
	var node_data: Resource = null
	if tree and mgr:
		node_data = mgr.get_node_data(tree, c_upgrades.current_upgrade_id)

	var status_label := Label.new()
	var upgrade_name: String = node_data.display_name if node_data else c_upgrades.current_upgrade_id
	status_label.text = "Upgrading: " + upgrade_name
	status_label.add_theme_font_size_override("font_size", 24)
	status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	status_label.add_theme_constant_override("outline_size", 1)
	_upgrade_container.add_child(status_label)

	_upgrade_progress_bar = ProgressBar.new()
	_upgrade_progress_bar.custom_minimum_size = Vector2(0, 28)
	_upgrade_progress_bar.value = c_upgrades.upgrade_progress * 100.0
	_upgrade_progress_bar.show_percentage = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.7)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	_upgrade_progress_bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.55, 0.35, 0.9, 0.95)
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_bottom_right = 4
	_upgrade_progress_bar.add_theme_stylebox_override("fill", fill_style)
	_upgrade_container.add_child(_upgrade_progress_bar)

	if node_data and c_upgrades.upgrade_power_paid < node_data.power_cost:
		var power_label := Label.new()
		power_label.text = "Charging: %.0f / %.0f power" % [c_upgrades.upgrade_power_paid, node_data.power_cost]
		power_label.add_theme_font_size_override("font_size", 22)
		power_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		power_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		power_label.add_theme_constant_override("outline_size", 1)
		_upgrade_container.add_child(power_label)


func _add_purchased_label(node_data: Resource) -> void:
	var label := Label.new()
	label.text = "✓ " + node_data.display_name
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", COLOR_UPGRADE_DONE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 1)
	_upgrade_container.add_child(label)


func _add_upgrade_button(node_data: Resource) -> void:
	var btn := Button.new()
	btn.text = "%s - %d minerals" % [node_data.display_name, node_data.mineral_cost]
	btn.tooltip_text = node_data.description
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", 22)

	var mgr: Node = _get_upgrade_manager()
	var can_afford: bool = mgr.can_afford(node_data) if mgr else false
	btn.disabled = not can_afford

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = COLOR_UPGRADE_BG if can_afford else Color(0.08, 0.08, 0.12, 0.9)
	btn_style.border_width_left = 1
	btn_style.border_width_top = 1
	btn_style.border_width_right = 1
	btn_style.border_width_bottom = 1
	btn_style.border_color = COLOR_UPGRADE_BORDER if can_afford else COLOR_UPGRADE_DISABLED
	btn_style.corner_radius_top_left = 4
	btn_style.corner_radius_top_right = 4
	btn_style.corner_radius_bottom_left = 4
	btn_style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", btn_style)

	var hover_style := btn_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.18, 0.1, 0.32, 0.95)
	hover_style.border_color = Color(0.75, 0.55, 1.0, 1.0)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := btn_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.3, 0.15, 0.5, 0.95)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var upgrade_id: String = node_data.id
	btn.pressed.connect(_on_upgrade_button_pressed.bind(upgrade_id))
	_upgrade_container.add_child(btn)


func _on_upgrade_button_pressed(upgrade_id: String) -> void:
	if _selected_entity == null or not is_instance_valid(_selected_entity):
		return
	var mgr: Node = _get_upgrade_manager()
	if mgr == null:
		return
	var success: bool = mgr.start_upgrade(_selected_entity, upgrade_id)
	if success:
		_rebuild_upgrade_rows()


func _get_upgrade_manager() -> Node:
	return get_node_or_null("/root/UpgradeManager")


func _rebuild_sell_button(details: Dictionary) -> void:
	if _sell_container == null:
		return
	for child in _sell_container.get_children():
		child.queue_free()

	if _selected_entity == null or not is_instance_valid(_selected_entity):
		return
	var faction: String = str(details.get("faction", "")).to_lower()
	if faction != "player" and faction != "ally" and faction != "friendly":
		return

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	_sell_container.add_child(sep)

	var btn := Button.new()
	btn.text = "Sell Structure"
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", 22)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = COLOR_SELL_BG
	btn_style.border_width_left = 1
	btn_style.border_width_top = 1
	btn_style.border_width_right = 1
	btn_style.border_width_bottom = 1
	btn_style.border_color = COLOR_SELL_BORDER
	btn_style.corner_radius_top_left = 4
	btn_style.corner_radius_top_right = 4
	btn_style.corner_radius_bottom_left = 4
	btn_style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", btn_style)

	var hover_style := btn_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.35, 0.08, 0.08, 0.95)
	hover_style.border_color = Color(1.0, 0.35, 0.35, 1.0)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := btn_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.5, 0.1, 0.1, 0.95)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.pressed.connect(_on_sell_pressed)
	_sell_container.add_child(btn)


func _on_sell_pressed() -> void:
	if _selected_entity == null or not is_instance_valid(_selected_entity):
		return

	var entity: Entity = _selected_entity
	SelectionManager.clear_selection()

	if entity.has_method("_on_health_destroyed"):
		entity._on_health_destroyed()
	else:
		entity.queue_free()

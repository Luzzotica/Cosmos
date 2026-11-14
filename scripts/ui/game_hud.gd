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

# Touch screens: Place / Cancel buttons in the bottom-right corner, bigger
# targets, minimap moved up under the Menu (pause) button.
const TOUCH_BUILD_BUTTON_SIZE: Vector2 = Vector2(150, 96)
const TOUCH_ACTION_BUTTON_SIZE: Vector2 = Vector2(150, 96)
const TOUCH_MINIMAP_SIZE: float = 220.0
const HUD_MARGIN: float = 20.0
var _touch_actions: HBoxContainer = null
var _place_button: Button = null
var _cancel_button: Button = null
@onready var _hud_margin: MarginContainer = $Margin
@onready var _bottom_bar: HBoxContainer = $Margin/VBox/BottomBar
@onready var _minimap: Control = $MinimapPanel


func _ready() -> void:
	_connect_signals()
	if MapLoader:
		MapLoader.map_loaded.connect(_on_map_loaded)
	_rebuild_build_buttons(GameState.get_effective_buildable_types())
	_setup_menu_button()
	_setup_next_wave_button()
	if MobileSupport.is_touch:
		_setup_touch_layout()
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
	if _touch_actions:
		_update_touch_actions()
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
		if i < HOTKEY_LABELS.size() and not MobileSupport.is_touch:
			hotkey_text = " (%s)" % HOTKEY_LABELS[i]

		var cost_text: String = _get_cost_text(building_type)
		button.text = _format_building_name(building_type) + hotkey_text + cost_text
		button.add_theme_font_size_override("font_size", 24)
		if MobileSupport.is_touch:
			button.custom_minimum_size = TOUCH_BUILD_BUTTON_SIZE
			button.add_theme_font_size_override("font_size", 22)
			button.focus_mode = Control.FOCUS_NONE
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


func _setup_touch_layout() -> void:
	var top_bar: HBoxContainer = $Margin/VBox/TopBar
	($Margin/VBox/TopBar/ResourcesPanel as Control).custom_minimum_size = Vector2(380, 0)
	($Margin/VBox/TopBar/WavePanel as Control).custom_minimum_size = Vector2(320, 0)
	for label in [minerals_label, energy_label, wave_label]:
		(label as Label).add_theme_font_size_override("font_size", 30)
	wave_timer_label.add_theme_font_size_override("font_size", 26)
	top_bar.add_theme_constant_override("separation", 12)
	menu_button.custom_minimum_size = Vector2(170, 88)
	menu_button.add_theme_font_size_override("font_size", 32)
	menu_button.text = "Pause"
	menu_button.focus_mode = Control.FOCUS_NONE
	# Build bar hugs the bottom-left; the bottom-right corner holds the actions.
	_bottom_bar.alignment = BoxContainer.ALIGNMENT_BEGIN

	_touch_actions = HBoxContainer.new()
	_touch_actions.name = "TouchActions"
	_touch_actions.add_theme_constant_override("separation", 12)
	_touch_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_touch_actions)
	_cancel_button = _make_touch_button("Cancel", Color(0.32549, 0.0588235, 0.117647, 0.94), Color(0.9, 0.3, 0.3, 0.9))
	_cancel_button.pressed.connect(_on_touch_cancel_pressed)
	_place_button = _make_touch_button("Place", Color(0.04, 0.26, 0.16, 0.94), Color(0.35, 1.0, 0.55, 0.95))
	_place_button.pressed.connect(_on_touch_place_pressed)
	_touch_actions.add_child(_cancel_button)
	_touch_actions.add_child(_place_button)
	_touch_actions.visible = false

	MobileSupport.layout_changed.connect(_apply_touch_safe_area)
	resized.connect(_apply_touch_safe_area)
	menu_button.resized.connect(_apply_touch_safe_area)
	_apply_touch_safe_area()
	call_deferred("_apply_touch_safe_area")


func _make_touch_button(label: String, bg: Color, border: Color) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = TOUCH_ACTION_BUTTON_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 32)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(3)
	sb.border_color = border
	sb.set_corner_radius_all(14)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var pressed := sb.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.lightened(0.25)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	return b


func _apply_touch_safe_area() -> void:
	var l: float = HUD_MARGIN + MobileSupport.safe_left
	var t: float = HUD_MARGIN + MobileSupport.safe_top
	var r: float = HUD_MARGIN + MobileSupport.safe_right
	var btm: float = HUD_MARGIN + MobileSupport.safe_bottom
	_hud_margin.add_theme_constant_override("margin_left", int(l))
	_hud_margin.add_theme_constant_override("margin_top", int(t))
	_hud_margin.add_theme_constant_override("margin_right", int(r))
	_hud_margin.add_theme_constant_override("margin_bottom", int(btm))
	# Minimap: top-right, under the Pause button.
	if _minimap:
		_minimap.anchor_left = 1.0
		_minimap.anchor_right = 1.0
		_minimap.anchor_top = 0.0
		_minimap.anchor_bottom = 0.0
		_minimap.custom_minimum_size = Vector2(TOUCH_MINIMAP_SIZE, TOUCH_MINIMAP_SIZE)
		_minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		var top: float = maxf(t + menu_button.get_combined_minimum_size().y, menu_button.get_global_rect().end.y) + 16.0
		_minimap.offset_right = -r
		_minimap.offset_left = -r - TOUCH_MINIMAP_SIZE
		_minimap.offset_top = top
		_minimap.offset_bottom = top + TOUCH_MINIMAP_SIZE
	if _touch_actions:
		_touch_actions.anchor_left = 1.0
		_touch_actions.anchor_right = 1.0
		_touch_actions.anchor_top = 1.0
		_touch_actions.anchor_bottom = 1.0
		_touch_actions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_touch_actions.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_layout_touch_actions()


func _layout_touch_actions() -> void:
	# Pin the cluster's bottom-right corner inside the safe area; its size
	# follows whichever buttons are showing.
	var r: float = HUD_MARGIN + MobileSupport.safe_right
	var btm: float = HUD_MARGIN + MobileSupport.safe_bottom
	var min_size: Vector2 = _touch_actions.get_combined_minimum_size()
	_touch_actions.offset_right = -r
	_touch_actions.offset_bottom = -btm
	_touch_actions.offset_left = -r - min_size.x
	_touch_actions.offset_top = -btm - min_size.y


func _update_touch_actions() -> void:
	var building: bool = BuildManager.is_in_build_mode
	var has_selection: bool = SelectionManager.selected_selectable != null or SelectionManager.selected_entity != null
	var show: bool = (building or has_selection) and not GameState.is_game_over
	var changed: bool = _touch_actions.visible != show or _place_button.visible != building
	_touch_actions.visible = show
	_place_button.visible = building
	_cancel_button.text = "Cancel" if building else "Deselect"
	# The selection panel needs the height; the build bar returns on Deselect.
	_bottom_bar.visible = building or not has_selection
	if changed:
		_layout_touch_actions()


func _on_touch_place_pressed() -> void:
	if BuildManager.is_in_build_mode:
		BuildManager.confirm_placement()


func _on_touch_cancel_pressed() -> void:
	_play_sfx_method("play_ui_confirm")
	if BuildManager.is_in_build_mode:
		BuildManager.cancel_placement()
	else:
		SelectionManager.clear_selection()


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

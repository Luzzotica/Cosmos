extends Control
class_name StoryMapSelect
## Star-map style level selection. Shows unlocked levels along a journey path.

# Cosmos palette
const COLOR_VOID: Color = Color(0, 0, 0, 1)
const COLOR_DEEP_SPACE: Color = Color(0.02, 0.078, 0.153, 1)
const COLOR_NEBULA: Color = Color(0.325, 0.059, 0.118, 1)
const COLOR_BURNT: Color = Color(0.643, 0.263, 0.133, 1)
const COLOR_SOLAR: Color = Color(0.973, 0.737, 0.016, 1)
const COLOR_LOCKED: Color = Color(0.2, 0.2, 0.25, 0.8)

const NODE_RADIUS: float = 28.0
const PATH_WIDTH: float = 3.0

@onready var map_canvas: Control = $MapCanvas
@onready var path_draw: Control = $MapCanvas/PathDraw
@onready var nodes_container: Control = $MapCanvas/NodesContainer
@onready var title_label: Label = $UILayer/Margin/VBox/TitleLabel
@onready var info_label: Label = $UILayer/Margin/VBox/InfoLabel
@onready var play_button: Button = $UILayer/Margin/VBox/ButtonRow/PlayButton
@onready var back_button: Button = $UILayer/Margin/VBox/ButtonRow/BackButton

var _entries: Array[Dictionary] = []
var _path_points: PackedVector2Array = []
var _selected_entry: Dictionary = {}
var _selected_button: Button = null


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_build_entries()
	call_deferred("_build_map")


func _build_map() -> void:
	_compute_path_points()
	_build_nodes()
	path_draw.queue_redraw()
	_select_first_unlocked()


func _build_entries() -> void:
	_entries.clear()
	var story_manager: Node = get_node_or_null("/root/StoryCampaignManager")
	if story_manager == null:
		return
	var manifest: Dictionary = story_manager.manifest
	var ordered: Array = manifest.get("ordered_map_ids", [])
	var maps: Array = manifest.get("maps", [])
	for map_id in ordered:
		var entry: Dictionary = _get_entry_by_id(maps, map_id)
		if not entry.is_empty():
			_entries.append(entry)


func _get_entry_by_id(maps: Array, map_id: String) -> Dictionary:
	for entry_variant in maps:
		if entry_variant is Dictionary:
			var entry: Dictionary = entry_variant
			if String(entry.get("id", "")) == map_id:
				return entry
	return {}


func _compute_path_points() -> void:
	_path_points.clear()
	if _entries.is_empty():
		return
	var count: int = _entries.size()
	var rect: Rect2 = map_canvas.get_rect()
	var margin: float = 80.0
	var usable_w: float = rect.size.x - margin * 2
	var usable_h: float = rect.size.y - margin * 2
	for i in count:
		var t: float = float(i) / max(1, count - 1) if count > 1 else 0.5
		# Zigzag path: left-to-right with vertical oscillation
		var x: float = margin + t * usable_w
		var wave: float = sin(t * PI) * 0.4 + 0.5
		var y: float = margin + wave * usable_h
		_path_points.append(Vector2(x, y))
	path_draw.set_meta("path_points", _path_points)


func _build_nodes() -> void:
	for child in nodes_container.get_children():
		child.queue_free()
	if _path_points.is_empty():
		return
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	for i in _entries.size():
		if i >= _path_points.size():
			break
		var entry: Dictionary = _entries[i]
		var map_id: String = String(entry.get("id", ""))
		var unlocked: bool = true
		if save_manager and save_manager.has_method("is_level_unlocked"):
			unlocked = save_manager.call("is_level_unlocked", map_id)
		var beaten: bool = false
		if save_manager and save_manager.has_method("is_level_beaten"):
			beaten = save_manager.call("is_level_beaten", map_id)
		var btn: Button = _create_node_button(entry, unlocked, beaten, i)
		btn.pressed.connect(_on_node_pressed.bind(btn, entry))
		btn.mouse_entered.connect(_on_node_hovered.bind(entry))
		var pos: Vector2 = _path_points[i] - Vector2(NODE_RADIUS, NODE_RADIUS)
		btn.position = pos
		btn.custom_minimum_size = Vector2(NODE_RADIUS * 2, NODE_RADIUS * 2)
		btn.size = Vector2(NODE_RADIUS * 2, NODE_RADIUS * 2)
		nodes_container.add_child(btn)


func _create_node_button(entry: Dictionary, unlocked: bool, beaten: bool, index: int) -> Button:
	var btn: Button = Button.new()
	btn.flat = true
	btn.disabled = not unlocked
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_SOLAR if unlocked else COLOR_LOCKED
	if beaten:
		style.bg_color = Color(0.4, 0.7, 0.3, 0.9)
	style.corner_radius_top_left = int(NODE_RADIUS)
	style.corner_radius_top_right = int(NODE_RADIUS)
	style.corner_radius_bottom_left = int(NODE_RADIUS)
	style.corner_radius_bottom_right = int(NODE_RADIUS)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = COLOR_SOLAR if unlocked else Color(0.3, 0.3, 0.35, 1)
	btn.add_theme_stylebox_override("normal", style)
	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = Color(1.0, 0.96, 0.7, 0.95) if unlocked else COLOR_LOCKED
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.text = str(index + 1) if unlocked else "?"
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", COLOR_DEEP_SPACE if unlocked else Color(0.5, 0.5, 0.55, 1))
	btn.set_meta("entry", entry)
	return btn


func _short_label(entry: Dictionary) -> String:
	var chapter: String = String(entry.get("chapter", ""))
	if chapter.begins_with("chapter_"):
		chapter = chapter.trim_prefix("chapter_")
	return chapter


func _select_first_unlocked() -> void:
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		var map_id: String = String(entry.get("id", ""))
		var save_manager: Node = get_node_or_null("/root/SaveManager")
		var unlocked: bool = true
		if save_manager and save_manager.has_method("is_level_unlocked"):
			unlocked = save_manager.call("is_level_unlocked", map_id)
		if unlocked:
			_select_node_by_index(i)
			return


func _select_node_by_index(idx: int) -> void:
	if idx < 0 or idx >= _entries.size():
		return
	_selected_entry = _entries[idx]
	var children: Array = nodes_container.get_children()
	if idx < children.size():
		_selected_button = children[idx] as Button
		if _selected_button:
			_selected_button.grab_focus()
	_update_info()


func _update_info() -> void:
	if _selected_entry.is_empty():
		info_label.text = "Select an extraction site."
		play_button.disabled = true
		return
	var map_id: String = String(_selected_entry.get("id", ""))
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	var unlocked: bool = true
	if save_manager and save_manager.has_method("is_level_unlocked"):
		unlocked = save_manager.call("is_level_unlocked", map_id)
	play_button.disabled = not unlocked
	if unlocked:
		info_label.text = "%s — %s" % [map_id, _short_label(_selected_entry)]
	else:
		info_label.text = "Complete the previous site to unlock."


func _on_node_pressed(btn: Button, entry: Dictionary) -> void:
	_selected_button = btn
	_selected_entry = entry
	_update_info()
	_play_sfx("play_ui_confirm")


func _on_node_hovered(_entry: Dictionary) -> void:
	# Optional: highlight on hover
	pass


func _on_play_pressed() -> void:
	if _selected_entry.is_empty():
		return
	var map_path: String = String(_selected_entry.get("map_path", ""))
	var map_id: String = String(_selected_entry.get("id", ""))
	if map_path.is_empty():
		return
	var session: Node = get_node_or_null("/root/GameSession")
	if session and session.has_method("start_story"):
		session.call("start_story", map_path, map_id)
	var story_manager: Node = get_node_or_null("/root/StoryCampaignManager")
	if story_manager and story_manager.has_method("set_current_by_map_id"):
		story_manager.call("set_current_by_map_id", map_id)
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/game/main.tscn")
	_play_sfx("play_ui_confirm")


func _on_back_pressed() -> void:
	var tree: SceneTree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/ui/main_menu.tscn")
	_play_sfx("play_ui_confirm")


func _play_sfx(method_name: String) -> void:
	var sfx: Node = get_node_or_null("/root/SfxManager")
	if sfx and sfx.has_method(method_name):
		sfx.call(method_name)

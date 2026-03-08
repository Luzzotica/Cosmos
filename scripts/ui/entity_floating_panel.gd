extends Control
class_name EntityFloatingPanel
## Screen-space panel that floats above a selected entity (billboard-style). Editable content by type.

signal delete_requested
signal test_generate_requested(cloud_data: Resource)
signal clear_preview_requested

const OFFSET_ABOVE: Vector3 = Vector3(0, 3, 0)
const MARGIN: int = 20

@onready var panel: PanelContainer = $Panel

var _entity: Node3D = null
var _camera: Camera3D = null
var _content_container: VBoxContainer = null
var _cloud_radius_sb: SpinBox = null
var _cloud_count_sb: SpinBox = null
var _cloud_min_size_sb: SpinBox = null
var _cloud_max_size_sb: SpinBox = null
var _cloud_min_minerals_sb: SpinBox = null
var _cloud_max_minerals_sb: SpinBox = null
var _cloud_seed_sb: SpinBox = null
var _cloud_data: Resource = null
var _structure_label: Label = null


func _ready() -> void:
	visible = false
	_content_container = VBoxContainer.new()
	_content_container.add_theme_constant_override("separation", 6)
	panel.add_child(_content_container)


func _process(_delta: float) -> void:
	if not is_instance_valid(_entity) or not is_instance_valid(_camera):
		visible = false
		return

	var world_pos: Vector3 = _entity.global_position + OFFSET_ABOVE
	var viewport: Viewport = get_viewport()
	if _camera == null:
		_camera = viewport.get_camera_3d()
	if _camera == null:
		return

	var screen_pos: Vector2 = _camera.unproject_position(world_pos)
	var panel_size: Vector2 = panel.size
	var vp_size: Vector2 = viewport.get_visible_rect().size
	# Center panel above entity, clamp to viewport
	var x: float = clampf(screen_pos.x - panel_size.x * 0.5, MARGIN, vp_size.x - panel_size.x - MARGIN)
	var y: float = clampf(screen_pos.y - panel_size.y - 10, MARGIN, vp_size.y - panel_size.y - MARGIN)
	panel.position = Vector2(x, y)
	visible = true


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func set_entity(entity: Node3D, content_type: String, data: Dictionary = {}) -> void:
	_entity = entity
	_clear_content()
	if content_type == "cloud":
		clear_preview_requested.emit()

	match content_type:
		"cloud":
			_build_cloud_content(data)
		"structure":
			_build_structure_content(data)


func _clear_content() -> void:
	for child in _content_container.get_children():
		child.queue_free()
	_cloud_radius_sb = null
	_cloud_count_sb = null
	_cloud_min_size_sb = null
	_cloud_max_size_sb = null
	_cloud_min_minerals_sb = null
	_cloud_max_minerals_sb = null
	_cloud_seed_sb = null
	_cloud_data = null
	_structure_label = null


func _build_cloud_content(data: Dictionary) -> void:
	_cloud_data = data.get("cloud_data", null) as Resource
	if not _cloud_data:
		return

	var title: Label = Label.new()
	title.text = "Asteroid Cloud"
	title.add_theme_font_size_override("font_size", 20)
	_content_container.add_child(title)

	var make_row: Callable = func(label_text: String, _sb_ref: Variant, min_v: float, max_v: float, step_v: float, val: float, changed_cb: Callable) -> SpinBox:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl: Label = Label.new()
		lbl.text = label_text + ":"
		lbl.custom_minimum_size.x = 70
		row.add_child(lbl)
		var sb: SpinBox = SpinBox.new()
		sb.min_value = min_v
		sb.max_value = max_v
		sb.step = step_v
		sb.value = val
		sb.custom_minimum_size.x = 70
		row.add_child(sb)
		_content_container.add_child(row)
		if changed_cb.is_valid():
			sb.value_changed.connect(changed_cb)
		return sb

	_cloud_radius_sb = make_row.call("Radius", null, 5.0, 200.0, 1.0, _cloud_data.radius, _on_cloud_radius_changed)
	_cloud_count_sb = make_row.call("Count", null, 1.0, 100.0, 1.0, float(_cloud_data.count), _on_cloud_count_changed)
	_cloud_min_size_sb = make_row.call("Min size", null, 0.5, 8.0, 0.1, _cloud_data.min_size, _on_cloud_min_size_changed)
	_cloud_max_size_sb = make_row.call("Max size", null, 0.5, 8.0, 0.1, _cloud_data.max_size, _on_cloud_max_size_changed)
	_cloud_min_minerals_sb = make_row.call("Min minerals", null, 1.0, 500.0, 1.0, _cloud_data.min_minerals, _on_cloud_min_minerals_changed)
	_cloud_max_minerals_sb = make_row.call("Max minerals", null, 1.0, 500.0, 1.0, _cloud_data.max_minerals, _on_cloud_max_minerals_changed)
	_cloud_seed_sb = make_row.call("Seed", null, 0.0, 999999.0, 1.0, float(_cloud_data.seed), _on_cloud_seed_changed)

	var avg_minerals: float = (_cloud_data.min_minerals + _cloud_data.max_minerals) * 0.5
	var avg_label: Label = Label.new()
	avg_label.text = "Avg minerals: %.0f" % avg_minerals
	_content_container.add_child(avg_label)

	var test_btn: Button = Button.new()
	test_btn.text = "Test Generate"
	test_btn.pressed.connect(_on_test_generate_pressed)
	_content_container.add_child(test_btn)

	var delete_btn: Button = Button.new()
	delete_btn.text = "Delete"
	delete_btn.pressed.connect(_on_delete_pressed)
	_content_container.add_child(delete_btn)


func _on_cloud_radius_changed(v: float) -> void:
	if _cloud_data:
		_cloud_data.radius = v


func _on_cloud_count_changed(v: float) -> void:
	if _cloud_data:
		_cloud_data.count = int(v)


func _on_cloud_min_size_changed(v: float) -> void:
	if _cloud_data:
		_cloud_data.min_size = v


func _on_cloud_max_size_changed(v: float) -> void:
	if _cloud_data:
		_cloud_data.max_size = v


func _on_cloud_min_minerals_changed(v: float) -> void:
	if _cloud_data:
		_cloud_data.min_minerals = v


func _on_cloud_max_minerals_changed(v: float) -> void:
	if _cloud_data:
		_cloud_data.max_minerals = v


func _on_cloud_seed_changed(v: float) -> void:
	if _cloud_data:
		_cloud_data.seed = int(v)


func _on_test_generate_pressed() -> void:
	if _cloud_data:
		test_generate_requested.emit(_cloud_data)


func _build_structure_content(data: Dictionary) -> void:
	var building_type: String = data.get("building_type", "structure")

	var title: Label = Label.new()
	title.text = "Structure"
	title.add_theme_font_size_override("font_size", 20)
	_content_container.add_child(title)

	_structure_label = Label.new()
	_structure_label.text = building_type.replace("_", " ").capitalize()
	_content_container.add_child(_structure_label)

	var delete_btn: Button = Button.new()
	delete_btn.text = "Delete"
	delete_btn.pressed.connect(_on_delete_pressed)
	_content_container.add_child(delete_btn)


func _on_delete_pressed() -> void:
	delete_requested.emit()


func clear_entity() -> void:
	_entity = null
	visible = false

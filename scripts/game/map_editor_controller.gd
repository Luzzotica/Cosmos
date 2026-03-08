extends Node
class_name MapEditorController
## In-game map editor controller for placing asteroids/structures and saving map drafts.

const MapValidatorClass: Script = preload("res://scripts/data/map_validator.gd")
const StoryMapConstraintsClass: Script = preload("res://scripts/data/story_map_constraints.gd")
const AsteroidCloudPlacementClass: Script = preload("res://scripts/data/asteroid_cloud_placement.gd")
const EntityFloatingPanelScene: PackedScene = preload("res://scenes/ui/entity_floating_panel.tscn")
const CloudMarkerScene: PackedScene = preload("res://scenes/editor/cloud_marker.tscn")
const CloudMarkerScript: Script = preload("res://scripts/editor/cloud_marker.gd")
const WaveDesignerPanelScene: PackedScene = preload("res://scenes/ui/wave_designer_panel.tscn")

const TOGGLE_KEY: Key = KEY_F9
const DRAFT_DIR: String = "user://maps"
const PREVIEW_MAP_PATH: String = "user://maps/editor_preview.json"

@onready var main_game: Node3D = get_parent()
@onready var camera: Camera3D = main_game.get_node_or_null("RTSCamera")
@onready var asteroids_parent: Node3D = main_game.get_node_or_null("Asteroids")
@onready var structures_parent: Node3D = main_game.get_node_or_null("Structures")
@onready var panel = main_game.get_node_or_null("UI/MapEditorPanel")

var _cloud_preview_container: Node3D = null

var editor_enabled: bool = false
var _floating_panel: Node = null
var _wave_designer: Control = null
var _working_initial_delay: float = 30.0
var _working_wave_interval: float = 60.0
var _working_waves: Array = []
var _selected_entity: Node = null


func _ready() -> void:
	if panel:
		panel.configure_structure_types(MapLoader.get_available_structure_types())
		panel.structure_type_selected.connect(_on_structure_type_selected)
		panel.save_requested.connect(_save_current_map_draft)
		panel.test_play_requested.connect(_test_play_current_map)
		panel.close_requested.connect(_toggle_editor.bind(false))
		panel.export_path_selected.connect(_export_map_to_path)
		panel.import_path_selected.connect(_import_map_from_path)
		panel.wave_designer_requested.connect(_open_wave_designer)

	var ui: Node = main_game.get_node_or_null("UI")
	if ui and EntityFloatingPanelScene:
		_floating_panel = EntityFloatingPanelScene.instantiate()
		ui.add_child(_floating_panel)
		_floating_panel.set_camera(camera)
		_floating_panel.delete_requested.connect(_on_floating_panel_delete_requested)
		_floating_panel.test_generate_requested.connect(_on_test_generate_requested)
		_floating_panel.clear_preview_requested.connect(_clear_cloud_preview)

	_cloud_preview_container = Node3D.new()
	_cloud_preview_container.name = "CloudPreviewContainer"
	main_game.add_child.call_deferred(_cloud_preview_container)

	set_process_input(true)
	set_process_unhandled_input(true)


func _input(event: InputEvent) -> void:
	if not editor_enabled:
		return
	# Use _input so we receive clicks even when GUI would otherwise consume them (fixes asteroid placement)
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if BuildManager and BuildManager.is_building():
				return  # Let BuildManager handle structure placement
			_handle_primary_click(mouse_event.position)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == TOGGLE_KEY:
			_toggle_editor(not editor_enabled)
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE and editor_enabled:
			_clear_selection()
			get_viewport().set_input_as_handled()
			return
		if editor_enabled and key_event.pressed and not key_event.echo:
			_handle_editor_hotkeys(key_event.keycode)


func _toggle_editor(enabled: bool) -> void:
	editor_enabled = enabled
	if panel:
		panel.visible = enabled
		panel.set_status("Editor %s" % ("enabled" if enabled else "disabled"))
	if enabled:
		_sync_working_waves_from_map()
	if not enabled:
		_clear_selection()


func set_editor_visible(enabled: bool) -> void:
	_toggle_editor(enabled)


func _handle_editor_hotkeys(keycode: Key) -> void:
	if panel == null:
		return
	# Mode hotkeys: B=Buildings, A=Asteroids, X=Erase
	if keycode == KEY_B:
		if not panel.building_mode_button.button_pressed:
			panel.building_mode_button.button_pressed = true
			panel._on_building_mode_toggled(true)
		get_viewport().set_input_as_handled()
		return
	if keycode == KEY_A:
		if not panel.asteroid_mode_button.button_pressed:
			panel.asteroid_mode_button.button_pressed = true
			panel._on_asteroid_mode_toggled(true)
		get_viewport().set_input_as_handled()
		return
	if keycode == KEY_X:
		if not panel.erase_mode_button.button_pressed:
			panel.erase_mode_button.button_pressed = true
			panel._on_erase_mode_toggled(true)
		get_viewport().set_input_as_handled()
		return
	if panel.get_editor_mode() == panel.MODE_ASTEROID and keycode == KEY_Y:
		panel._on_monolith_button_pressed()
		get_viewport().set_input_as_handled()
		return
	# Building hotkeys: Q E R T Y (when in building mode)
	if panel.get_editor_mode() == panel.MODE_BUILDING:
		var types: PackedStringArray = MapLoader.get_available_structure_types()
		for i in range(mini(panel.BUILD_HOTKEYS.size(), types.size())):
			if keycode == panel.BUILD_HOTKEYS[i]:
				panel._on_build_button_pressed(types[i])
				get_viewport().set_input_as_handled()
				return


func _on_structure_type_selected(building_type: String) -> void:
	# Use BuildManager for in-game placement UX (preview, validation) with instant build
	if BuildManager:
		BuildManager.start_building_editor(building_type)


func _sync_working_waves_from_map() -> void:
	var map: MapData = MapLoader.current_map
	if map:
		_working_initial_delay = map.initial_wave_delay
		_working_wave_interval = map.wave_interval
		_working_waves.clear()
		for w in map.waves:
			_working_waves.append(w)
		if _working_waves.is_empty():
			for i in range(3):
				_working_waves.append(MapLoader.get_wave_data(i))
	else:
		_working_initial_delay = GameState.map_initial_wave_delay
		_working_wave_interval = GameState.map_wave_interval
		_working_waves.clear()
		for i in range(3):
			_working_waves.append(MapLoader.get_wave_data(i))


func _open_wave_designer() -> void:
	var ui: Node = main_game.get_node_or_null("UI")
	if not ui:
		return
	if not _wave_designer and WaveDesignerPanelScene:
		_wave_designer = WaveDesignerPanelScene.instantiate()
		ui.add_child(_wave_designer)
		_wave_designer.visible = false
		_wave_designer.applied.connect(_on_wave_designer_applied)
	if _wave_designer:
		_wave_designer.configure(_working_initial_delay, _working_wave_interval, _working_waves)
		_wave_designer.show()


func _on_wave_designer_applied(delay: float, interval: float, waves: Array) -> void:
	_working_initial_delay = delay
	_working_wave_interval = interval
	_working_waves = waves
	GameState.map_initial_wave_delay = delay
	GameState.map_wave_interval = interval
	if panel:
		panel.set_status("Wave designer applied")


func _handle_primary_click(mouse_pos: Vector2) -> void:
	if panel == null or camera == null:
		return
	# Only skip when over interactive UI (buttons, inputs, dialogs); allow placement/selection in viewport area
	if _is_pointer_over_interactive_ui():
		return

	var hit: Dictionary = _raycast(mouse_pos)
	var tool_mode: String = panel.get_tool_mode()

	# If we hit an editor entity and we're not in erase mode, select it instead of placing
	if tool_mode != "erase" and not hit.is_empty():
		var collider: Variant = hit.get("collider", null)
		var selectable: Node = _resolve_selectable_entity(collider) if collider is Node else null
		if selectable:
			_select_entity(selectable)
			return

	match tool_mode:
		"cloud":
			if hit.is_empty():
				return
			var world_pos: Vector3 = hit.get("position", Vector3.ZERO)
			var cloud_data: Resource = AsteroidCloudPlacementClass.new()
			cloud_data.center = world_pos
			cloud_data.radius = 35.0
			cloud_data.count = 8
			cloud_data.min_size = 2.0
			cloud_data.max_size = 4.0
			cloud_data.min_minerals = 25.0
			cloud_data.max_minerals = 60.0
			cloud_data.seed = int(Time.get_unix_time_from_system())
			var marker: Node3D = CloudMarkerScene.instantiate() as Node3D
			marker.global_position = world_pos
			marker.set("cloud_data", cloud_data)
			asteroids_parent.add_child(marker)
			panel.set_status("Placed asteroid cloud")
		"structure":
			# Placement handled by BuildManager when structure button is clicked - nothing to do here
			pass
		"erase":
			if hit.is_empty():
				_clear_selection()
				return
			var collider: Variant = hit.get("collider", null)
			var target: Node = null
			if collider is Node:
				target = collider as Node
			if target:
				var erasable: Node = _resolve_erasable_node(target)
				if erasable:
					erasable.queue_free()
					_clear_selection()
					panel.set_status("Removed object")


func _raycast(mouse_pos: Vector2) -> Dictionary:
	var origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var direction: Vector3 = camera.project_ray_normal(mouse_pos)
	var to: Vector3 = origin + direction * 4000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit

	# Fallback to ground plane at y=0 for placement if no collider was hit.
	if absf(direction.y) < 0.0001:
		# Nearly horizontal ray: project mouse onto XZ plane at camera's look-at distance
		var look_dist: float = 50.0
		var plane_pt: Vector3 = origin + direction * look_dist
		return {"position": Vector3(plane_pt.x, 0.0, plane_pt.z)}
	var t: float = -origin.y / direction.y
	if t < 0.0:
		# Ray points away from ground: use point in front of camera
		var fallback: Vector3 = origin + direction * 100.0
		return {"position": Vector3(fallback.x, 0.0, fallback.z)}
	return {"position": origin + direction * t}


func _resolve_erasable_node(node: Node) -> Node:
	var cursor: Node = node
	while cursor != null and cursor != main_game:
		if cursor.get_script() == CloudMarkerScript:
			return cursor
		if cursor.get_parent() == structures_parent:
			return cursor
		cursor = cursor.get_parent()
	return null


func _resolve_selectable_entity(node: Node) -> Node:
	return _resolve_erasable_node(node)


func _is_pointer_over_interactive_ui() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	var c: Control = hovered
	while c != null:
		if c is Button or c is LineEdit or c is SpinBox or c is Slider or c is CheckBox or c is OptionButton:
			return true
		c = c.get_parent_control()
	# Also block when inside a popup/window (e.g. FileDialog, MapSettings)
	var node: Node = hovered
	while node != null:
		if node is Window:
			return true
		node = node.get_parent()
	return false


func _select_entity(entity: Node) -> void:
	_selected_entity = entity
	if not _floating_panel:
		return
	if entity.get_script() == CloudMarkerScript:
		var cloud_data: Resource = entity.get("cloud_data")
		_floating_panel.set_entity(entity as Node3D, "cloud", {"node": entity, "cloud_data": cloud_data})
	elif entity.get_parent() == structures_parent:
		var bt: String = _infer_structure_type(entity)
		_floating_panel.set_entity(entity as Node3D, "structure", {"node": entity, "building_type": bt})
	else:
		_floating_panel.set_entity(entity as Node3D, "structure", {"node": entity, "building_type": "unknown"})
	panel.set_status("Selected: %s" % entity.name)


func _clear_selection() -> void:
	_selected_entity = null
	if _floating_panel:
		_floating_panel.clear_entity()
	_clear_cloud_preview()


func _on_test_generate_requested(cloud_data: Resource) -> void:
	if not _cloud_preview_container or not cloud_data:
		return
	if _cloud_preview_container.get_child_count() > 0:
		_clear_cloud_preview()
		if panel:
			panel.set_status("Preview cleared")
	else:
		MapLoader.spawn_cloud_preview(_cloud_preview_container, cloud_data)
		if panel:
			panel.set_status("Test generate: preview shown")


func _clear_cloud_preview() -> void:
	if _cloud_preview_container:
		for child in _cloud_preview_container.get_children():
			child.queue_free()


func _on_floating_panel_delete_requested() -> void:
	if not is_instance_valid(_selected_entity):
		_clear_selection()
		return
	_selected_entity.queue_free()
	_clear_selection()
	panel.set_status("Removed object")


func _build_map_data_from_scene() -> MapData:
	var map_data: MapData = MapData.new()
	map_data.schema_version = MapData.CURRENT_SCHEMA_VERSION
	map_data.map_id = _slugify(panel.get_map_metadata().get("name", "community_map"))
	var meta: Dictionary = panel.get_map_metadata()
	map_data.map_name = meta.get("name", "Community Draft")
	map_data.biome = meta.get("biome", "asteroid_field")
	map_data.difficulty_band = meta.get("difficulty_band", "normal")
	map_data.act = meta.get("act", "")
	map_data.chapter = meta.get("chapter", "")
	map_data.allow_partial_extraction = bool(meta.get("allow_partial_extraction", true))
	map_data.target_carryover_minerals = int(meta.get("target_carryover_minerals", 0))
	map_data.target_carryover_energy = float(meta.get("target_carryover_energy", 0.0))
	map_data.tags = PackedStringArray(["community", "editor_draft"])
	map_data.initial_wave_delay = _working_initial_delay
	map_data.wave_interval = _working_wave_interval
	map_data.waves = _working_waves.duplicate()

	for child in asteroids_parent.get_children():
		if child.get_script() == CloudMarkerScript:
			var cloud_data: Resource = child.get("cloud_data")
			if cloud_data:
				map_data.asteroid_clouds.append(cloud_data)

	for child in structures_parent.get_children():
		if child is Node3D:
			var structure_placement: StructurePlacement = StructurePlacement.new()
			structure_placement.position = (child as Node3D).global_position
			structure_placement.building_type = _infer_structure_type(child)
			map_data.starting_structures.append(structure_placement)

	map_data.starting_resources.override_defaults = true
	map_data.starting_resources.minerals = GameState.minerals
	map_data.starting_resources.energy = GameState.energy
	map_data.starting_resources.energy_capacity = GameState.energy_capacity
	return map_data


func _save_current_map_draft() -> void:
	var map_data: MapData = _build_map_data_from_scene()
	var save_name: String = _slugify(map_data.map_name)
	if save_name.is_empty():
		save_name = "community_draft"
	var path: String = "%s/%s.json" % [DRAFT_DIR, save_name]
	_ensure_user_map_directory()
	if map_data.save_to_json(path):
		panel.set_status("Saved draft: %s" % path)
	else:
		panel.set_status("Failed to save draft")


func _export_map_to_path(path: String) -> void:
	if path.strip_edges().is_empty():
		panel.set_status("Export cancelled.")
		return
	var export_path: String = path
	if not export_path.to_lower().ends_with(".json"):
		export_path += ".json"
	var map_data: MapData = _build_map_data_from_scene()
	if map_data.save_to_json(export_path):
		panel.set_status("Exported map: %s" % export_path)
	else:
		panel.set_status("Failed to export map.")


func _import_map_from_path(path: String) -> void:
	if path.strip_edges().is_empty():
		panel.set_status("Import cancelled.")
		return
	var map_data: MapData = MapData.load_from_json(path)
	if map_data == null:
		panel.set_status("Failed to parse map JSON.")
		return
	var validation: Dictionary = MapValidatorClass.validate_map_data(map_data)
	if not bool(validation.get("is_valid", false)):
		var errors: PackedStringArray = validation.get("errors", PackedStringArray())
		panel.set_status("Import failed: %s" % (errors[0] if errors.size() > 0 else "invalid map"))
		return
	MapLoader.load_map(map_data, true)
	_sync_working_waves_from_map()
	panel.apply_map_metadata(map_data)
	panel.set_status("Imported and loaded map: %s" % path.get_file())


func _test_play_current_map() -> void:
	var map_data: MapData = _build_map_data_from_scene()
	var validation: Dictionary = MapValidatorClass.validate_map_data(map_data)
	if not validation.get("is_valid", false):
		var errors: PackedStringArray = validation.get("errors", PackedStringArray())
		panel.set_status("Map invalid: %s" % (errors[0] if errors.size() > 0 else "unknown error"))
		return
	var story_validation: Dictionary = StoryMapConstraintsClass.validate_story_map(map_data)
	if not story_validation.get("is_valid", false):
		var story_errors: PackedStringArray = story_validation.get("errors", PackedStringArray())
		panel.set_status("Story rules failed: %s" % (story_errors[0] if story_errors.size() > 0 else "unknown error"))
		return
	_ensure_user_map_directory()
	map_data.save_to_json(PREVIEW_MAP_PATH)
	MapLoader.load_map(map_data)
	var story_warnings: PackedStringArray = story_validation.get("warnings", PackedStringArray())
	if story_warnings.size() > 0:
		panel.set_status("Loaded preview with warning: %s" % story_warnings[0])
	else:
		panel.set_status("Loaded preview map")


func _ensure_user_map_directory() -> void:
	var absolute_dir: String = ProjectSettings.globalize_path(DRAFT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)


func _infer_structure_type(node: Node) -> String:
	var name_lower: String = node.name.to_lower()
	if name_lower.contains("solar"):
		return "solar_panel"
	if name_lower.contains("power"):
		return "power_node"
	if name_lower.contains("mining"):
		return "mining_station"
	if name_lower.contains("laser"):
		return "laser_turret"
	if name_lower.contains("monolith"):
		return "monolith"
	return "solar_panel"


func _slugify(value: String) -> String:
	var out: String = value.strip_edges().to_lower()
	out = out.replace(" ", "_")
	out = out.replace("-", "_")
	return out

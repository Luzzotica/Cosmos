extends Node
class_name MapEditorController
## In-game map editor controller for placing asteroids/structures and saving map drafts.

const MapValidatorClass: Script = preload("res://scripts/data/map_validator.gd")
const StoryMapConstraintsClass: Script = preload("res://scripts/data/story_map_constraints.gd")
const AsteroidCloudPlacementClass: Script = preload("res://scripts/data/asteroid_cloud_placement.gd")

const TOGGLE_KEY: Key = KEY_F9
const DRAFT_DIR: String = "user://maps"
const PREVIEW_MAP_PATH: String = "user://maps/editor_preview.json"

var main_game: Node3D
var camera: Camera3D
var asteroids_parent: Node3D
var structures_parent: Node3D
var panel: Control

var editor_enabled: bool = false
var _clouds: Array[Resource] = []


func _ready() -> void:
	main_game = get_parent()
	camera = main_game.get_node_or_null("RTSCamera")
	asteroids_parent = main_game.get_node_or_null("Asteroids")
	structures_parent = main_game.get_node_or_null("Structures")

	# Panel may be our child (when loaded from map_editor.tscn) or already under UI
	panel = get_node_or_null("MapEditorPanel") as Control
	if panel:
		var ui: CanvasLayer = main_game.get_node_or_null("UI")
		if ui:
			panel.reparent(ui)
	if panel == null:
		panel = main_game.get_node_or_null("UI/MapEditorPanel") as Control

	if panel:
		panel.configure_structure_types(MapLoader.get_available_structure_types())
		panel.save_requested.connect(_save_current_map_draft)
		panel.test_play_requested.connect(_test_play_current_map)
		panel.close_requested.connect(_toggle_editor.bind(false))
		panel.export_path_selected.connect(_export_map_to_path)
		panel.import_path_selected.connect(_import_map_from_path)
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == TOGGLE_KEY:
			_toggle_editor(not editor_enabled)
			get_viewport().set_input_as_handled()
			return

	if not editor_enabled:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_handle_primary_click(mouse_event.position)
			get_viewport().set_input_as_handled()


func _toggle_editor(enabled: bool) -> void:
	editor_enabled = enabled
	if panel:
		panel.visible = enabled
		panel.set_status("Editor %s" % ("enabled" if enabled else "disabled"))


func set_editor_visible(enabled: bool) -> void:
	_toggle_editor(enabled)


func _handle_primary_click(mouse_pos: Vector2) -> void:
	if panel == null or camera == null:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return

	var hit: Dictionary = _raycast(mouse_pos)
	var tool_mode: String = panel.get_tool_mode()

	match tool_mode:
		"asteroid":
			if hit.is_empty():
				return
			var world_pos: Vector3 = hit.get("position", Vector3.ZERO)
			MapLoader.spawn_asteroid_for_editor(asteroids_parent, world_pos, panel.get_asteroid_size(), panel.get_asteroid_minerals())
			panel.set_status("Placed asteroid")
		"cloud":
			if hit.is_empty():
				return
			var cloud: Resource = AsteroidCloudPlacementClass.new()
			cloud.center = hit.get("position", Vector3.ZERO)
			cloud.radius = panel.get_cloud_radius()
			cloud.count = panel.get_cloud_count()
			cloud.seed = Time.get_unix_time_from_system()
			MapLoader.spawn_asteroid_cloud_for_editor(asteroids_parent, cloud)
			_clouds.append(cloud)
			panel.set_status("Painted asteroid cloud")
		"structure":
			if hit.is_empty():
				return
			var structure_pos: Vector3 = hit.get("position", Vector3.ZERO)
			MapLoader.spawn_structure_for_editor(structures_parent, panel.get_structure_type(), structure_pos, true)
			panel.set_status("Placed structure")
		"erase":
			if hit.is_empty():
				return
			var collider: Variant = hit.get("collider", null)
			var target: Node = null
			if collider is Node:
				target = collider as Node
			if target:
				var erasable: Node = _resolve_erasable_node(target)
				if erasable:
					erasable.queue_free()
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
		return {}
	var t: float = -origin.y / direction.y
	if t < 0.0:
		return {}
	return {"position": origin + direction * t}


func _resolve_erasable_node(node: Node) -> Node:
	var cursor: Node = node
	while cursor != null and cursor != main_game:
		if cursor is Asteroid:
			return cursor
		if cursor.get_parent() == structures_parent:
			return cursor
		cursor = cursor.get_parent()
	return null


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
	map_data.initial_wave_delay = GameState.map_initial_wave_delay
	map_data.wave_interval = GameState.map_wave_interval

	for child in asteroids_parent.get_children():
		if child is Asteroid:
			var asteroid: Asteroid = child as Asteroid
			var placement: AsteroidPlacement = AsteroidPlacement.new()
			placement.position = asteroid.global_position
			placement.size = asteroid.asteroid_size
			placement.minerals = asteroid.total_minerals
			map_data.asteroids.append(placement)

	for cloud in _clouds:
		map_data.asteroid_clouds.append(cloud)

	for child in structures_parent.get_children():
		if child is Node3D:
			var structure_placement: StructurePlacement = StructurePlacement.new()
			structure_placement.position = (child as Node3D).global_position
			structure_placement.building_type = _infer_structure_type(child)
			structure_placement.is_pre_built = true
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
	MapLoader.load_map(map_data)
	_clouds.clear()
	for cloud in map_data.asteroid_clouds:
		_clouds.append(cloud)
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
	return "solar_panel"


func _slugify(value: String) -> String:
	var out: String = value.strip_edges().to_lower()
	out = out.replace(" ", "_")
	out = out.replace("-", "_")
	return out

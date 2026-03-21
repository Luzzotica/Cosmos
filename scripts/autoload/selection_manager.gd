extends Node
## Singleton that manages RTS-style selection using SelectableComponent.

signal selection_changed(entity: Node3D, entity_type: String)
signal selection_cleared
signal primary_selection_changed(selectable: Node, details: Dictionary)
signal selection_details_changed(details: Dictionary)
signal selection_list_changed(selectables: Array)

enum EntityType {
	NONE,
	STRUCTURE,
	ENEMY,
	ASTEROID
}

var selected_entity: Node3D = null
var selected_type: EntityType = EntityType.NONE
var selected_selectable: Node = null
var selected_entities: Array[Node3D] = []
var selected_selectables: Array = []
var _registered_selectables: Array = []
var _legacy_selected_entity: Node3D = null
var _hovered_selectable: Node = null


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	if not _is_gameplay_active():
		return
	if GameState.is_game_over:
		_set_hovered_selectable(null)
		return
	_update_hover_from_raycast()


func _input(event: InputEvent) -> void:
	if not _is_gameplay_active():
		return
	if GameState.is_game_over:
		return
	if event is InputEventMouseButton:
		var select_mouse: InputEventMouseButton = event as InputEventMouseButton
		if select_mouse.pressed and select_mouse.button_index == MOUSE_BUTTON_LEFT:
			# Don't consume clicks over UI - let buttons, minimap, build bar receive them.
			if _is_mouse_over_blocking_ui():
				return
			if not BuildManager.is_selection_blocked():
				var selectable: Node = _raycast_selectable_at_mouse(select_mouse.position)
				if selectable:
					select_selectable(selectable)
					get_viewport().set_input_as_handled()
					return
				# Explicit empty-world deselect: if click hits no world collider, clear selection.
				if _raycast_collider_at_mouse(select_mouse.position) == null:
					clear_selection()
					get_viewport().set_input_as_handled()
					return

	# Right-click or Escape to deselect
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			clear_selection()
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			clear_selection()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_gameplay_active():
		return
	if GameState.is_game_over:
		return
	# Left-click on empty space to deselect
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# If we're not currently building something, clear selection
			if not BuildManager.is_building():
				clear_selection()


## Select an entity
func select(entity: Node3D) -> void:
	if not is_instance_valid(entity):
		clear_selection()
		return

	var selectable: Node = entity.get_node_or_null("SelectableComponent")
	if selectable:
		select_selectable(selectable)
		return

	# Temporary compatibility path for legacy entities still on old system.
	_select_legacy_entity(entity)


func register_selectable(selectable: Node) -> void:
	if selectable == null or not is_instance_valid(selectable):
		return
	if _registered_selectables.has(selectable):
		return

	_registered_selectables.append(selectable)
	_connect_selectable(selectable)

	if selectable.has_signal("input_event") and not selectable.is_connected("input_event", _on_selectable_input_event):
		selectable.input_event.connect(_on_selectable_input_event.bind(selectable))
	if selectable.has_signal("mouse_entered") and not selectable.is_connected("mouse_entered", _on_selectable_mouse_entered):
		selectable.mouse_entered.connect(_on_selectable_mouse_entered.bind(selectable))
	if selectable.has_signal("mouse_exited") and not selectable.is_connected("mouse_exited", _on_selectable_mouse_exited):
		selectable.mouse_exited.connect(_on_selectable_mouse_exited.bind(selectable))


func unregister_selectable(selectable: Node) -> void:
	if selectable == null:
		return
	_registered_selectables.erase(selectable)
	if selected_selectable == selectable:
		clear_selection()


## Select using a SelectableComponent contract
func select_selectable(selectable: Node) -> void:
	if selectable == null or not is_instance_valid(selectable):
		clear_selection()
		return
	if not selectable.is_selectable:
		return

	_connect_selectable(selectable)
	set_primary_selection(selectable)


func set_primary_selection(selectable: Node) -> void:
	set_selection([selectable] if selectable else [])


func set_selection(selectables: Array) -> void:
	_clear_legacy_selection()

	var normalized: Array = []
	for selectable in selectables:
		if selectable == null or not is_instance_valid(selectable):
			continue
		if not selectable.is_selectable:
			continue
		if normalized.has(selectable):
			continue
		_connect_selectable(selectable)
		normalized.append(selectable)

	var previous: Array = selected_selectables.duplicate()
	for old_selectable in previous:
		if is_instance_valid(old_selectable) and not normalized.has(old_selectable):
			old_selectable.set_selected(false)

	selected_selectables = normalized
	selected_entities.clear()
	for current in selected_selectables:
		if is_instance_valid(current.owner_entity):
			selected_entities.append(current.owner_entity)

	selected_selectable = selected_selectables[0] if selected_selectables.size() > 0 else null
	selected_entity = selected_entities[0] if selected_entities.size() > 0 else null
	selected_type = _get_selected_type()

	for current_selectable in selected_selectables:
		current_selectable.set_selected(true)

	if selected_entity != null:
		var type_str: String = _type_to_string(selected_type)
		selection_changed.emit(selected_entity, type_str)
		var details: Dictionary = get_primary_selection_details()
		primary_selection_changed.emit(selected_selectable, details)
		selection_details_changed.emit(details)
		selection_list_changed.emit(selected_selectables.duplicate())
	else:
		selection_cleared.emit()
		selection_list_changed.emit([])


## Clear current selection
func clear_selection() -> void:
	for selectable in selected_selectables:
		if is_instance_valid(selectable):
			selectable.set_selected(false)
	for entity in selected_entities:
		_notify_deselection(entity)

	_clear_legacy_selection()
	selected_selectables.clear()
	selected_entities.clear()
	selected_selectable = null
	selected_entity = null
	selected_type = EntityType.NONE
	selection_cleared.emit()
	selection_list_changed.emit([])


## Get info about the selected entity
func get_selection_info() -> Dictionary:
	if selected_selectable and is_instance_valid(selected_selectable):
		var details: Dictionary = get_primary_selection_details()
		return _normalize_to_legacy_info(details)

	if _legacy_selected_entity and is_instance_valid(_legacy_selected_entity):
		return _get_legacy_entity_info(_legacy_selected_entity)

	if selected_entity == null or not is_instance_valid(selected_entity):
		return {}
	return _get_legacy_entity_info(selected_entity)


func get_primary_selection_details() -> Dictionary:
	if selected_selectable == null or not is_instance_valid(selected_selectable):
		return {}

	var details: Dictionary = selected_selectable.get_selection_details()
	if details.is_empty():
		details = {}

	if not details.has("name"):
		details["name"] = selected_selectable.get_display_name()
	if not details.has("category"):
		details["category"] = selected_selectable.selection_kind
	if not details.has("faction"):
		details["faction"] = selected_selectable.get_faction()
	if not details.has("stats"):
		details["stats"] = []
	return details


func _get_entity_type(entity: Node3D) -> EntityType:
	if entity is BaseStructure:
		return EntityType.STRUCTURE
	if entity.has_method("get_selection_details") and entity.get_parent() and entity.get_parent().has_method("get_component"):
		return EntityType.STRUCTURE
	if entity is EnemyShipBase:
		return EntityType.ENEMY
	elif entity.has_method("mine_minerals") or (entity.get_parent() and entity.get_parent().has_method("mine_minerals")):
		return EntityType.ASTEROID
	var class_name_str: String = entity.get_class()
	if "Structure" in class_name_str or entity.has_method("is_built"):
		return EntityType.STRUCTURE
	if "Enemy" in class_name_str:
		return EntityType.ENEMY
	if "Asteroid" in class_name_str or entity.has_method("mine_minerals") or (entity.get_parent() and entity.get_parent().has_method("mine_minerals")):
		return EntityType.ASTEROID
	return EntityType.NONE


func _type_to_string(type: EntityType) -> String:
	match type:
		EntityType.STRUCTURE:
			return "structure"
		EntityType.ENEMY:
			return "enemy"
		EntityType.ASTEROID:
			return "asteroid"
		_:
			return "none"


func _get_entity_name(entity: Node3D) -> String:
	if entity is BaseStructure:
		var structure: BaseStructure = entity as BaseStructure
		if structure.building_type != "":
			return structure.building_type.replace("_", " ").capitalize()
	if entity.has_method("get_selection_name") and entity.get_parent() and entity.get_parent().has_method("get_component"):
		return entity.get_selection_name()
	if entity is EnemyShipBase:
		var enemy: EnemyShipBase = entity as EnemyShipBase
		return enemy.get_selection_name()
	if entity.has_method("get_selection_name"):
		return entity.get_selection_name()
	return entity.name.replace("_", " ").capitalize()


func _get_structure_info(entity: Node3D) -> Dictionary:
	var info: Dictionary = {}
	if entity.has_method("get_selection_details") and entity.get_parent() and entity.get_parent().has_method("get_component"):
		var details: Dictionary = entity.get_selection_details()
		if details.has("health_current"):
			info["health"] = details.health_current
		if details.has("health_max"):
			info["max_health"] = details.health_max
		if details.has("health_current") and details.has("health_max") and details.health_max > 0:
			info["health_percent"] = (float(details.health_current) / float(details.health_max)) * 100.0
		if details.has("is_built"):
			info["is_built"] = details.is_built
		if details.has("build_progress"):
			info["build_progress"] = details.build_progress
		if details.has("connection_count"):
			info["connection_count"] = details.connection_count
		if details.has("is_powered"):
			info["is_powered"] = details.is_powered
		if details.has("building_type"):
			info["building_type"] = details.building_type
		return info
	if entity is BaseStructure:
		var structure: BaseStructure = entity as BaseStructure
		
		# Health
		if structure.health_component:
			info["health"] = structure.health_component.health
			info["max_health"] = structure.health_component.max_health
			info["health_percent"] = structure.health_component.get_health_percentage() * 100.0
		
		# Construction status
		if structure.construction_component:
			info["is_built"] = structure.construction_component.is_built
			if not structure.construction_component.is_built:
				info["build_progress"] = structure.construction_component.get_progress() * 100.0
		else:
			info["is_built"] = true
		
		# Power info
		if structure.power_node:
			info["is_powered"] = structure.power_node.is_enabled
			info["connection_count"] = structure.power_node.connected_nodes.size()
		
		# Building type specific info
		info["building_type"] = structure.building_type
	
	return info


func _get_enemy_info(entity: Node3D) -> Dictionary:
	if entity is EnemyShipBase:
		return (entity as EnemyShipBase).get_selection_details()
	return {}


func _get_asteroid_info(entity: Node3D) -> Dictionary:
	var info: Dictionary = {}
	var asteroid: Node = entity if entity.has_method("mine_minerals") else entity.get_parent()
	if asteroid and asteroid.has_method("mine_minerals"):
		info["remaining_minerals"] = asteroid.remaining_minerals
		info["total_minerals"] = asteroid.total_minerals
		info["mineral_percent"] = (asteroid.remaining_minerals / asteroid.total_minerals) * 100.0 if asteroid.total_minerals > 0 else 0.0
		info["is_depleted"] = asteroid.is_depleted
		info["size"] = asteroid.asteroid_size
	return info


func _notify_deselection(entity: Node3D) -> void:
	if is_instance_valid(entity) and entity.has_method("on_deselected"):
		entity.call("on_deselected")


func _on_selected_entity_destroyed() -> void:
	clear_selection()


func _get_selected_type() -> EntityType:
	if selected_selectable == null or not is_instance_valid(selected_selectable):
		return EntityType.NONE

	var category: String = str(selected_selectable.selection_kind).to_lower()
	match category:
		"structure":
			return EntityType.STRUCTURE
		"enemy", "unit":
			return EntityType.ENEMY
		"asteroid", "resource":
			return EntityType.ASTEROID
		_:
			return EntityType.NONE


func _connect_selectable(selectable: Node) -> void:
	if not selectable.is_connected("selection_requested", _on_selectable_selection_requested):
		selectable.selection_requested.connect(_on_selectable_selection_requested)
	if not selectable.is_connected("selectable_destroyed", _on_selectable_destroyed):
		selectable.selectable_destroyed.connect(_on_selectable_destroyed.bind(selectable))
	if not selectable.is_connected("details_changed", _on_selectable_details_changed):
		selectable.details_changed.connect(_on_selectable_details_changed.bind(selectable))


func _on_selectable_selection_requested(selectable: Node) -> void:
	select_selectable(selectable)


func _on_selectable_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int, selectable: Node) -> void:
	if not _is_gameplay_active():
		return
	if selectable == null or not is_instance_valid(selectable):
		return
	if not selectable.is_selectable:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if BuildManager.is_selection_blocked():
				return
			select_selectable(selectable)
			get_viewport().set_input_as_handled()


func _on_selectable_mouse_entered(selectable: Node) -> void:
	if not _is_gameplay_active():
		return
	if selectable == null or not is_instance_valid(selectable):
		return
	if selectable.has_method("handle_mouse_entered"):
		selectable.handle_mouse_entered()


func _on_selectable_mouse_exited(selectable: Node) -> void:
	if not _is_gameplay_active():
		return
	if selectable == null or not is_instance_valid(selectable):
		return
	if selectable.has_method("handle_mouse_exited"):
		selectable.handle_mouse_exited()


func _on_selectable_destroyed(selectable: Node) -> void:
	unregister_selectable(selectable)
	if selected_selectable == selectable:
		clear_selection()


func _on_selectable_details_changed(selectable: Node) -> void:
	if selected_selectable != selectable:
		return
	var details: Dictionary = get_primary_selection_details()
	selection_details_changed.emit(details)


func _update_hover_from_raycast() -> void:
	if BuildManager.is_hover_blocked():
		_set_hovered_selectable(null)
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		_set_hovered_selectable(null)
		return
	var selectable: Node = _raycast_selectable_at_mouse(viewport.get_mouse_position())
	_set_hovered_selectable(selectable)


func _set_hovered_selectable(selectable: Node) -> void:
	if _hovered_selectable == selectable:
		return

	if _hovered_selectable and is_instance_valid(_hovered_selectable):
		_hovered_selectable.set_hovered(false)

	_hovered_selectable = selectable
	if _hovered_selectable and is_instance_valid(_hovered_selectable):
		_hovered_selectable.set_hovered(true)


func _raycast_selectable_at_mouse(mouse_pos: Vector2) -> Node:
	var collider: Node = _raycast_collider_at_mouse(mouse_pos)
	if collider == null:
		return null
	return _resolve_selectable_from_node(collider)


func _is_mouse_over_blocking_ui() -> bool:
	## Returns true if the mouse is over a GUI Control that would consume the click.
	## This prevents SelectionManager from stealing clicks meant for buttons, minimap, etc.
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return false
	var hovered: Control = viewport.gui_get_hovered_control()
	if hovered == null:
		return false
	# Controls with MOUSE_FILTER_STOP consume clicks - don't steal from them
	return hovered.mouse_filter == Control.MOUSE_FILTER_STOP


func _raycast_collider_at_mouse(mouse_pos: Vector2) -> Node:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return null

	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider: Variant = result.get("collider")
	if not (collider is Node):
		return null
	return collider as Node


func _resolve_selectable_from_node(node: Node) -> Node:
	var current: Node = node
	while current != null:
		if current.name == "SelectableComponent" and current.has_method("set_selected"):
			return current
		current = current.get_parent()
	return null


func _select_legacy_entity(entity: Node3D) -> void:
	if entity == _legacy_selected_entity:
		return

	clear_selection()
	_legacy_selected_entity = entity
	selected_entity = entity
	selected_type = _get_entity_type(entity)
	selection_changed.emit(selected_entity, _type_to_string(selected_type))
	primary_selection_changed.emit(null, _get_legacy_entity_info(entity))
	selection_details_changed.emit(_get_legacy_entity_info(entity))

	if entity.has_signal("destroyed") and not entity.is_connected("destroyed", _on_selected_entity_destroyed):
		entity.connect("destroyed", _on_selected_entity_destroyed)


func _clear_legacy_selection() -> void:
	if _legacy_selected_entity != null and is_instance_valid(_legacy_selected_entity):
		_notify_deselection(_legacy_selected_entity)
		if _legacy_selected_entity.has_signal("destroyed") and _legacy_selected_entity.is_connected("destroyed", _on_selected_entity_destroyed):
			_legacy_selected_entity.disconnect("destroyed", _on_selected_entity_destroyed)
	_legacy_selected_entity = null


func _normalize_to_legacy_info(details: Dictionary) -> Dictionary:
	var info: Dictionary = {
		"type": str(details.get("category", "none")).to_lower(),
		"name": str(details.get("name", "Unknown"))
	}

	var faction: String = str(details.get("faction", "neutral")).to_lower()
	info["faction"] = faction

	if details.has("health_current") and details.has("health_max"):
		var health_current: float = float(details.health_current)
		var health_max: float = maxf(float(details.health_max), 1.0)
		info["health"] = health_current
		info["max_health"] = health_max
		info["health_percent"] = (health_current / health_max) * 100.0

	if details.has("resource_current") and details.has("resource_max"):
		var resource_current: float = float(details.resource_current)
		var resource_max: float = maxf(float(details.resource_max), 1.0)
		info["remaining_minerals"] = resource_current
		info["total_minerals"] = resource_max
		info["mineral_percent"] = (resource_current / resource_max) * 100.0

	if details.has("building_type"):
		info["building_type"] = details.building_type
	if details.has("is_built"):
		info["is_built"] = details.is_built
	if details.has("build_progress"):
		info["build_progress"] = details.build_progress
	if details.has("is_powered"):
		info["is_powered"] = details.is_powered
	if details.has("connection_count"):
		info["connection_count"] = details.connection_count
	if details.has("damage"):
		info["damage"] = details.damage
	if details.has("speed"):
		info["speed"] = details.speed
	if details.has("weakness"):
		info["weakness"] = details.weakness
	if details.has("size"):
		info["size"] = details.size
	if details.has("is_depleted"):
		info["is_depleted"] = details.is_depleted
	if details.has("stats"):
		info["stats"] = details.stats

	return info


func _get_legacy_entity_info(entity: Node3D) -> Dictionary:
	var info: Dictionary = {
		"type": _type_to_string(_get_entity_type(entity)),
		"name": _get_entity_name(entity)
	}

	match _get_entity_type(entity):
		EntityType.STRUCTURE:
			info.merge(_get_structure_info(entity))
		EntityType.ENEMY:
			info.merge(_get_enemy_info(entity))
		EntityType.ASTEROID:
			info.merge(_get_asteroid_info(entity))
	return info


func _is_gameplay_active() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	var root: Node = tree.root
	if root == null:
		return false
	return root.get_node_or_null("Main") != null



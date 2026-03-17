extends Node3D
class_name BaseStructure
## Base class for all structures

signal destroyed

@export var building_type: String = ""
@export_group("Build FX Tuning")
@export var build_fx_center_offset: Vector3 = Vector3.ZERO
@export var build_fx_radius_multiplier: float = 1.15
@export_group("Placement Preview")
@export var placement_preview_include_mesh_names: PackedStringArray = PackedStringArray()
@export var placement_preview_exclude_mesh_names: PackedStringArray = PackedStringArray()

var team_component: TeamComponent
var health_component: HealthComponent
var construction_component: ConstructionComponent
var power_node: PowerNode

var is_destroyed: bool = false
var selectable_component: Node

# Build animation
var _original_materials: Array = []  # Material (StandardMaterial3D or ShaderMaterial)
var _mesh_instances: Array[MeshInstance3D] = []
var _build_shader_materials: Array[ShaderMaterial] = []
var _build_finalize_tween: Tween = null
var _build_bounds_center_local: Vector3 = Vector3.ZERO
var _build_bounds_extents_local: Vector3 = Vector3.ONE
var _build_bounds_radius_local: float = 1.0
var _registered_with_render_manager: bool = false
var _is_powered_visual: bool = true
const BUILD_START_SCALE: float = 0.3
const BUILD_TRANSPARENCY: float = 0.5
const BUILD_SHELL_SHADER_PATH: String = "res://shaders/structure_build_shell.gdshader"
const STRUCTURE_HULL_SHADER_PATH: String = "res://shaders/structure_hull.gdshader"
var _build_shell_shader: Shader = null

var _ecs_entity: Node = null

func _ready() -> void:
	selectable_component = get_node_or_null("SelectableComponent")
	_setup_components()
	_connect_signals()
	_setup_build_animation()
	call_deferred("_register_ecs_entity")


func _register_ecs_entity() -> void:
	if _ecs_entity != null:
		return
	var ecs_node: Node = get_node_or_null("/root/ECS")
	if ecs_node == null:
		return
	var world = ecs_node.get("world")
	if world == null:
		return
	var entity_script: Script = load("res://addons/gecs/ecs/entity.gd") as Script
	if entity_script == null:
		return
	_ecs_entity = Node.new()
	_ecs_entity.set_script(entity_script)
	_ecs_entity.name = "ECSEntity"
	add_child(_ecs_entity)
	var c_structure: Resource = load("res://scripts/ecs/components/c_structure.gd").new()
	c_structure.set("structure_node", self)
	c_structure.set("building_type", building_type)
	c_structure.set("is_destroyed", is_destroyed)
	var c_health: Resource = load("res://scripts/ecs/components/c_health.gd").new()
	if health_component:
		c_health.set("maximum", health_component.max_health)
		c_health.set("current", health_component.health)
	var c_team: Resource = load("res://scripts/ecs/components/c_team.gd").new()
	if team_component:
		c_team.set("team", team_component.get_team_string())
	else:
		c_team.set("team", "player")
	var c_transform: Resource = load("res://scripts/ecs/components/c_transform3d.gd").new()
	c_transform.set("position", global_position)
	c_transform.set("rotation", rotation)
	var c_construction: Resource = load("res://scripts/ecs/components/c_construction.gd").new()
	if construction_component:
		c_construction.set("is_built", construction_component.is_built)
		c_construction.set("build_progress", construction_component.get_progress() if construction_component.has_method("get_progress") else 0.0)
	var components: Array = [c_structure, c_health, c_team, c_transform, c_construction]
	world.call("add_entity", _ecs_entity, components, false)


func _setup_components() -> void:
	# Find or create components
	for child in get_children():
		if child is TeamComponent:
			team_component = child
		elif child is HealthComponent:
			health_component = child
		elif child is ConstructionComponent:
			construction_component = child
		elif child is PowerNode:
			power_node = child


func _connect_signals() -> void:
	if health_component:
		health_component.destroyed.connect(_on_destroyed)
	if construction_component:
		construction_component.construction_completed.connect(_on_construction_completed)


func _setup_build_animation() -> void:
	# Find all mesh instances in this structure
	_find_mesh_instances(self)
	_compute_build_bounds_local()
	if _build_shell_shader == null:
		_build_shell_shader = load(BUILD_SHELL_SHADER_PATH) as Shader
	
	# Store original materials and apply construction print shader.
	for mesh_inst in _mesh_instances:
		var mat: Material = mesh_inst.get_active_material(0)
		if mat:
			var original_copy: Material = mat.duplicate()
			_apply_hull_params(original_copy)
			_original_materials.append(original_copy)
			var build_mat: ShaderMaterial = _create_build_shader_material(mesh_inst, original_copy)
			_build_shader_materials.append(build_mat)
			if build_mat:
				mesh_inst.set_surface_override_material(0, build_mat)
		else:
			_original_materials.append(null)
			_build_shader_materials.append(null)
	
	# Set initial scale if under construction
	if construction_component and not construction_component.is_built:
		scale = Vector3.ONE
	else:
		_restore_materials()
		_register_with_render_manager()


func _find_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		_mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		# Don't recurse into component nodes
		if child is TeamComponent or child is HealthComponent or child is ConstructionComponent or child is PowerNode:
			continue
		# Selection rings are runtime UI feedback and must never be multimesh-batched as structure geometry.
		if child is SelectionVisuals or child.name == "SelectionVisuals":
			continue
		_find_mesh_instances(child)


func _process(delta: float) -> void:
	_update_build_animation(delta)
	if selectable_component and selectable_component.is_selected():
		selectable_component.notify_details_changed()


func _update_build_animation(_delta: float) -> void:
	if not construction_component or construction_component.is_built:
		return
	
	var progress: float = construction_component.get_progress()
	
	# Keep final scale and drive construction print shader.
	scale = Vector3.ONE
	var print_dir_local: Vector3 = _get_build_print_direction_local()
	var axis_data: Dictionary = _compute_axis_projection_from_bounds(print_dir_local)
	for i in range(_build_shader_materials.size()):
		var build_mat: ShaderMaterial = _build_shader_materials[i]
		if build_mat:
			build_mat.set_shader_parameter("build_progress", progress)
			build_mat.set_shader_parameter("print_direction", print_dir_local)
			build_mat.set_shader_parameter("axis_center", float(axis_data.get("center", 0.0)))
			build_mat.set_shader_parameter("axis_extent", maxf(float(axis_data.get("extent", 1.0)), 0.01))
			build_mat.set_shader_parameter("build_radius", maxf(_build_bounds_radius_local * maxf(build_fx_radius_multiplier, 0.1), 0.01))
			build_mat.set_shader_parameter("finalize_blend", 0.0)


func _on_construction_completed() -> void:
	# Smoothly blend construction shader into final material before swapping.
	_start_build_finalize_tween()
	scale = Vector3.ONE


func _restore_materials() -> void:
	for i in range(_mesh_instances.size()):
		if i < _original_materials.size() and _original_materials[i]:
			var mat_to_set: Material = _original_materials[i].duplicate()
			_apply_hull_params(mat_to_set)
			_mesh_instances[i].set_surface_override_material(0, mat_to_set)
	_build_shader_materials.clear()


func _start_build_finalize_tween() -> void:
	if _build_finalize_tween:
		_build_finalize_tween.kill()
		_build_finalize_tween = null
	
	if _build_shader_materials.is_empty():
		_finish_construction_visuals()
		return
	
	var finalize_duration: float = 0.35
	_build_finalize_tween = create_tween()
	_build_finalize_tween.set_trans(Tween.TRANS_SINE)
	_build_finalize_tween.set_ease(Tween.EASE_OUT)
	_build_finalize_tween.tween_method(func(v: float) -> void:
		for mat in _build_shader_materials:
			if mat:
				mat.set_shader_parameter("build_progress", 1.0)
				mat.set_shader_parameter("finalize_blend", v)
	, 0.0, 1.0, finalize_duration)
	_build_finalize_tween.tween_callback(func() -> void:
		_build_finalize_tween = null
		_finish_construction_visuals()
	)


func _finish_construction_visuals() -> void:
	_restore_materials()
	_register_with_render_manager()
	# Use actual power state at build completion, not cached _is_powered_visual.
	# Structures with PowerUser may have set _is_powered_visual=false in _ready when
	# the buffer was empty (during construction). The graph has power now; sync visual.
	set_powered_visual_state(has_operational_power())
	_play_construction_finish_animation()
	if selectable_component:
		selectable_component.notify_details_changed()


func _play_construction_finish_animation() -> void:
	pass


func _create_build_shader_material(mesh_inst: MeshInstance3D, original_mat: Material) -> ShaderMaterial:
	if _build_shell_shader == null:
		return null
	if mesh_inst == null or mesh_inst.mesh == null:
		return null
	
	var final_color_val: Color = Color(0.45, 0.48, 0.52, 1.0)
	if original_mat is StandardMaterial3D:
		final_color_val = (original_mat as StandardMaterial3D).albedo_color
	elif original_mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = original_mat as ShaderMaterial
		if shader_mat.shader and shader_mat.shader.resource_path == STRUCTURE_HULL_SHADER_PATH:
			var base: Variant = shader_mat.get_shader_parameter("base_color")
			if base is Color:
				final_color_val = base
	
	var dir_local: Vector3 = _get_build_print_direction_local()
	var axis_data: Dictionary = _compute_axis_projection_from_bounds(dir_local)
	var build_mat: ShaderMaterial = ShaderMaterial.new()
	build_mat.shader = _build_shell_shader
	build_mat.set_shader_parameter("build_progress", 0.0)
	build_mat.set_shader_parameter("final_color", final_color_val)
	build_mat.set_shader_parameter("print_direction", dir_local)
	build_mat.set_shader_parameter("axis_center", float(axis_data.get("center", 0.0)))
	build_mat.set_shader_parameter("axis_extent", maxf(float(axis_data.get("extent", 1.0)), 0.01))
	build_mat.set_shader_parameter("build_radius", maxf(_build_bounds_radius_local * maxf(build_fx_radius_multiplier, 0.1), 0.01))
	build_mat.set_shader_parameter("finalize_blend", 0.0)
	return build_mat


func _apply_hull_params(mat: Material) -> void:
	if not mat is ShaderMaterial:
		return
	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	if shader_mat.shader == null:
		return
	if shader_mat.shader.resource_path != STRUCTURE_HULL_SHADER_PATH:
		return
	var dir_local: Vector3 = _get_build_print_direction_local()
	var axis_data: Dictionary = _compute_axis_projection_from_bounds(dir_local)
	shader_mat.set_shader_parameter("print_direction", dir_local)
	shader_mat.set_shader_parameter("axis_center", float(axis_data.get("center", 0.0)))
	shader_mat.set_shader_parameter("axis_extent", maxf(float(axis_data.get("extent", 1.0)), 0.01))
	shader_mat.set_shader_parameter("build_radius", maxf(_build_bounds_radius_local * maxf(build_fx_radius_multiplier, 0.1), 0.01))


func _get_build_print_direction_local() -> Vector3:
	if power_node and power_node.connected_nodes.size() > 0:
		var source_node: Node3D = power_node.connected_nodes[0] as Node3D
		if source_node:
			var source_structure: Node3D = source_node.get_parent() as Node3D
			if source_structure:
				var world_dir: Vector3 = global_position - source_structure.global_position
				world_dir.y = 0.0
				if world_dir.length() > 0.001:
					var local_dir: Vector3 = global_basis.inverse() * world_dir.normalized()
					local_dir.y = 0.0
					if local_dir.length() > 0.001:
						return local_dir.normalized()
	return Vector3.UP


func _compute_axis_projection_from_bounds(direction: Vector3) -> Dictionary:
	var dir: Vector3 = direction.normalized()
	if dir.length() < 0.001:
		dir = Vector3.UP
	
	var axis_center: float = _build_bounds_center_local.dot(dir)
	var axis_extent: float = absf(dir.x) * _build_bounds_extents_local.x + absf(dir.y) * _build_bounds_extents_local.y + absf(dir.z) * _build_bounds_extents_local.z
	axis_extent = maxf(axis_extent, _build_bounds_radius_local * 0.55)
	return {"center": axis_center, "extent": maxf(axis_extent, 0.01)}


func _compute_build_bounds_local() -> void:
	var has_bounds: bool = false
	var min_pos: Vector3 = Vector3.ZERO
	var max_pos: Vector3 = Vector3.ZERO
	
	for mesh_inst in _mesh_instances:
		if mesh_inst == null or mesh_inst.mesh == null:
			continue
		var local_aabb: AABB = mesh_inst.mesh.get_aabb()
		var transformed_aabb: AABB = local_aabb * mesh_inst.transform
		var mesh_min: Vector3 = transformed_aabb.position
		var mesh_max: Vector3 = transformed_aabb.position + transformed_aabb.size
		if not has_bounds:
			min_pos = mesh_min
			max_pos = mesh_max
			has_bounds = true
		else:
			min_pos = Vector3(
				minf(min_pos.x, mesh_min.x),
				minf(min_pos.y, mesh_min.y),
				minf(min_pos.z, mesh_min.z)
			)
			max_pos = Vector3(
				maxf(max_pos.x, mesh_max.x),
				maxf(max_pos.y, mesh_max.y),
				maxf(max_pos.z, mesh_max.z)
			)
	
	if not has_bounds:
		_build_bounds_center_local = Vector3.ZERO
		_build_bounds_extents_local = Vector3.ONE
		_build_bounds_radius_local = 1.0
		return
	
	_build_bounds_center_local = (min_pos + max_pos) * 0.5
	_build_bounds_extents_local = (max_pos - min_pos) * 0.5
	_build_bounds_radius_local = maxf(_build_bounds_extents_local.length(), 0.6)


func _exit_tree() -> void:
	_unregister_from_render_manager()


func _register_with_render_manager() -> void:
	if _registered_with_render_manager:
		return
	if not has_node("/root/StructureRenderManager"):
		return
	if _mesh_instances.is_empty():
		return
	
	var accent_mesh_names: Array[String] = _resolve_accent_mesh_names()
	var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
	if render_manager == null:
		return
	render_manager.call("register_structure", self, _mesh_instances, accent_mesh_names)
	render_manager.call("set_structure_powered", self, _is_powered_visual)
	_registered_with_render_manager = true


func _unregister_from_render_manager() -> void:
	if not _registered_with_render_manager:
		return
	var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
	if render_manager:
		render_manager.call("unregister_structure", self)
	_registered_with_render_manager = false


func _resolve_accent_mesh_names() -> Array[String]:
	var accent_meshes: Array[String] = []
	if _mesh_instances.size() == 1:
		accent_meshes.append(_mesh_instances[0].name)
		return accent_meshes
	
	for mesh_inst in _mesh_instances:
		var mesh_name: String = mesh_inst.name.to_lower()
		if mesh_name.contains("active") or mesh_name.contains("orb") or mesh_name.contains("panel") or mesh_name.contains("core") or mesh_name.contains("emiss"):
			accent_meshes.append(mesh_inst.name)
	
	return accent_meshes


func set_powered_visual_state(is_powered: bool) -> void:
	_is_powered_visual = is_powered
	if _registered_with_render_manager:
		var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
		if render_manager:
			render_manager.call("set_structure_powered", self, is_powered)
			return
	
	# Fallback for editor/runtime before render manager registration.
	for i in range(_mesh_instances.size()):
		var mesh_inst: MeshInstance3D = _mesh_instances[i]
		var mat: StandardMaterial3D = mesh_inst.get_active_material(0) as StandardMaterial3D
		if mat == null:
			continue
		
		var mesh_name: String = mesh_inst.name.to_lower()
		var is_accent_mesh: bool = _mesh_instances.size() == 1 \
			or mesh_name.contains("active") \
			or mesh_name.contains("orb") \
			or mesh_name.contains("panel") \
			or mesh_name.contains("core")
		if not is_accent_mesh:
			continue
		
		if is_powered:
			if i < _original_materials.size() and _original_materials[i]:
				mesh_inst.set_surface_override_material(0, _original_materials[i].duplicate())
		else:
			var off_mat: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
			off_mat.albedo_color = off_mat.albedo_color.lerp(Color(0.2, 0.22, 0.26, 1.0), 0.75)
			off_mat.emission_enabled = false
			off_mat.emission = Color(0.0, 0.0, 0.0, 1.0)
			off_mat.emission_energy_multiplier = 0.0
			mesh_inst.set_surface_override_material(0, off_mat)


func has_operational_power() -> bool:
	if not is_built():
		return false
	if building_type == "solar_panel":
		return true
	if power_node == null:
		return true
	if not power_node.is_enabled:
		return false
	
	if not has_node("/root/PowerGraphManager"):
		return power_node.connected_nodes.size() > 0
	
	var graph_manager: Node = get_node_or_null("/root/PowerGraphManager")
	if graph_manager == null or not graph_manager.has_method("find_subgraph_for_node"):
		return power_node.connected_nodes.size() > 0
	
	var subgraph: Variant = graph_manager.call("find_subgraph_for_node", power_node)
	if subgraph == null:
		return false
	
	var current_power: Variant = subgraph.get("power_current")
	if current_power != null:
		return float(current_power) > 0.0
	
	return power_node.connected_nodes.size() > 0


func _on_destroyed() -> void:
	is_destroyed = true
	if _ecs_entity != null:
		_ecs_entity.add_component(preload("res://scripts/ecs/components/c_destroyed.gd").new())
		if ECS != null and ECS.world != null:
			ECS.world.remove_entity(_ecs_entity)
		_ecs_entity = null
	destroyed.emit()
	queue_free()


## Get the team string for this structure
func get_team() -> String:
	if team_component:
		return team_component.get_team_string()
	return "player"


## Take damage
func take_damage(amount: float) -> void:
	if health_component:
		health_component.take_damage(amount)


func take_damage_event(event_payload: Dictionary) -> float:
	if health_component == null:
		return 0.0
	return health_component.take_damage_event(event_payload)


## Check if construction is complete
func is_built() -> bool:
	if construction_component:
		return construction_component.is_built
	return true


## Set as starter building (pre-built)
func set_starter_panel(is_starter: bool) -> void:
	if is_starter:
		if construction_component:
			construction_component.set_built()
		if power_node:
			power_node.is_enabled = true
		# Remove C_Construction so systems using with_none([C_Construction]) process this structure
		if _ecs_entity and _ecs_entity.has_method("remove_component"):
			var C_ConstructionClass: GDScript = load("res://scripts/ecs/components/c_construction.gd") as GDScript
			if C_ConstructionClass:
				_ecs_entity.remove_component(C_ConstructionClass)
		# Immediately finalize the build animation (restore materials, full scale)
		_on_construction_completed()


## Handle mouse input for selection
func _on_input_event(_camera: Node, _event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	pass


## Called when mouse enters the structure
func _on_mouse_entered() -> void:
	pass


## Called when mouse exits the structure
func _on_mouse_exited() -> void:
	pass


## Called when selection changes
func _on_selection_changed(_entity: Node3D, _entity_type: String) -> void:
	pass


## Called when selection is cleared
func _on_selection_cleared() -> void:
	pass


## Update visual feedback based on selection/hover state
func _update_visual_feedback() -> void:
	pass


## Called when this entity is deselected
func on_deselected() -> void:
	pass


func get_selection_name() -> String:
	if building_type != "":
		return building_type.replace("_", " ").capitalize()
	return name.replace("_", " ").capitalize()


func get_selection_details() -> Dictionary:
	var details: Dictionary = {
		"name": get_selection_name(),
		"category": "structure",
		"faction": get_team(),
		"building_type": building_type,
		"is_built": is_built(),
		"stats": []
	}

	if health_component:
		details["health_current"] = health_component.health
		details["health_max"] = health_component.max_health

	if construction_component and not construction_component.is_built:
		details["build_progress"] = construction_component.get_progress() * 100.0

	if power_node:
		details["is_powered"] = has_operational_power()
		details["is_connected"] = power_node.connected_nodes.size() > 0
		details["connection_count"] = power_node.connected_nodes.size()

	var stats: Array[Dictionary] = []
	stats.append({"label": "Type", "value": building_type.replace("_", " ").capitalize()})
	stats.append({"label": "Status", "value": "Operational" if details.is_built else "Building %.0f%%" % details.get("build_progress", 0.0)})
	if details.has("is_powered"):
		stats.append({"label": "Power", "value": "Online" if details.is_powered else "Offline"})
	if details.has("is_connected"):
		stats.append({"label": "Grid Link", "value": "Connected" if details.is_connected else "Disconnected"})
	if details.has("connection_count"):
		stats.append({"label": "Connections", "value": str(details.connection_count)})

	if get("attack_range") != null:
		stats.append({"label": "Range", "value": "%.0f" % float(get("attack_range"))})
	if get("fire_rate") != null:
		stats.append({"label": "Fire Rate", "value": "%.1f/s" % float(get("fire_rate"))})
	if get("damage") != null:
		stats.append({"label": "Damage", "value": "%.0f" % float(get("damage"))})
	if get("mining_radius") != null:
		stats.append({"label": "Mining Radius", "value": "%.1f" % float(get("mining_radius"))})
	if get("mine_amount") != null:
		stats.append({"label": "Mine Amount", "value": "%.0f" % float(get("mine_amount"))})

	details["stats"] = stats
	return details

extends Node
class_name StructureVisualHandler
## Base for structure visual behavior. Handles build animation, power visuals, StructureRenderManager.
## Add as child of StructureBody. Entity calls body.initialize_visuals(entity); body calls handler.init(entity).

const C_ConstructionClass = preload("res://scripts/ecs/components/c_construction.gd")
const C_HealthClass = preload("res://scripts/ecs/components/c_health.gd")
const BUILD_SHELL_SHADER_PATH: String = "res://shaders/structure_build_shell.gdshader"
const STRUCTURE_HULL_SHADER_PATH: String = "res://shaders/structure_hull.gdshader"

var _entity: Node = null
var _mesh_instances: Array[MeshInstance3D] = []
var _original_materials: Array = []
var _build_shader_materials: Array[ShaderMaterial] = []
var _build_finalize_tween: Tween = null
var _build_bounds_center_local: Vector3 = Vector3.ZERO
var _build_bounds_extents_local: Vector3 = Vector3.ONE
var _build_bounds_radius_local: float = 1.0
var _registered_with_render_manager: bool = false
var _is_powered_visual: bool = true
var _build_shell_shader: Shader = null
var _build_fx_radius_multiplier: float = 1.15
var _is_upgrade_animating: bool = false
var _upgrade_progress_visual: float = 0.0


func init(entity: Node) -> void:
	_entity = entity
	var body: Node3D = get_parent() as Node3D
	if body == null:
		return
	_find_mesh_instances(body)
	_compute_build_bounds_local()
	if _build_shell_shader == null:
		_build_shell_shader = load(BUILD_SHELL_SHADER_PATH) as Shader
	# Use ConstructionComponent as source of truth (Entity structures may not have C_Construction)
	var construction_component: Node = body.get_node_or_null("ConstructionComponent")
	var is_under_construction: bool = construction_component != null and construction_component.get("is_built") == false
	var c_health = _get_component(C_HealthClass)
	if is_under_construction:
		_setup_build_animation()
	else:
		_restore_materials()
		_register_with_render_manager()
	if c_health and c_health.has_signal("destroyed"):
		if not c_health.destroyed.is_connected(_on_health_destroyed):
			c_health.destroyed.connect(_on_health_destroyed)
	if construction_component and construction_component.has_signal("construction_completed"):
		if not construction_component.construction_completed.is_connected(_on_construction_completed):
			construction_component.construction_completed.connect(_on_construction_completed)


func _get_component(component_class: Variant) -> Variant:
	if _entity and _entity.has_method("get_component"):
		return _entity.get_component(component_class)
	return null


func _find_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		_mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		if child is PowerNode or child is SelectableComponent or child.name == "SelectionVisuals" or child.name == "VisualHandler":
			continue
		if child is ConstructionComponent:
			continue
		_find_mesh_instances(child)


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
			min_pos = Vector3(minf(min_pos.x, mesh_min.x), minf(min_pos.y, mesh_min.y), minf(min_pos.z, mesh_min.z))
			max_pos = Vector3(maxf(max_pos.x, mesh_max.x), maxf(max_pos.y, mesh_max.y), maxf(max_pos.z, mesh_max.z))
	if not has_bounds:
		_build_bounds_center_local = Vector3.ZERO
		_build_bounds_extents_local = Vector3.ONE
		_build_bounds_radius_local = 1.0
		return
	_build_bounds_center_local = (min_pos + max_pos) * 0.5
	_build_bounds_extents_local = (max_pos - min_pos) * 0.5
	_build_bounds_radius_local = maxf(_build_bounds_extents_local.length(), 0.6)


func _setup_build_animation() -> void:
	for mesh_inst in _mesh_instances:
		var mat: Material = mesh_inst.get_active_material(0)
		if mat:
			var original_copy: Material = mat.duplicate()
			_apply_hull_params(original_copy, mesh_inst)
			_original_materials.append(original_copy)
			var build_mat: ShaderMaterial = _create_build_shader_material(mesh_inst, original_copy)
			_build_shader_materials.append(build_mat)
			if build_mat:
				mesh_inst.set_surface_override_material(0, build_mat)
		else:
			_original_materials.append(null)
			_build_shader_materials.append(null)


func _create_build_shader_material(mesh_inst: MeshInstance3D, original_mat: Material) -> ShaderMaterial:
	if _build_shell_shader == null or mesh_inst == null or mesh_inst.mesh == null:
		return null
	var final_color_val: Color = Color(0.45, 0.48, 0.52, 1.0)
	if original_mat is StandardMaterial3D:
		final_color_val = (original_mat as StandardMaterial3D).albedo_color
	elif original_mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = original_mat as ShaderMaterial
		if shader_mat.shader and shader_mat.shader.resource_path == STRUCTURE_HULL_SHADER_PATH:
			var base_val: Variant = shader_mat.get_shader_parameter("base_color")
			if base_val is Color:
				final_color_val = base_val
	var dir_local: Vector3 = _get_build_print_direction_local()
	var axis_data: Dictionary = _compute_axis_projection_from_bounds(dir_local)
	var build_mat: ShaderMaterial = ShaderMaterial.new()
	build_mat.shader = _build_shell_shader
	build_mat.set_shader_parameter("build_progress", 0.0)
	build_mat.set_shader_parameter("final_color", final_color_val)
	build_mat.set_shader_parameter("print_direction", dir_local)
	build_mat.set_shader_parameter("axis_center", float(axis_data.get("center", 0.0)))
	build_mat.set_shader_parameter("axis_extent", maxf(float(axis_data.get("extent", 1.0)), 0.01))
	build_mat.set_shader_parameter("build_radius", maxf(_build_bounds_radius_local * maxf(_build_fx_radius_multiplier, 0.1), 0.01))
	build_mat.set_shader_parameter("finalize_blend", 0.0)
	return build_mat


func _get_build_print_direction_local() -> Vector3:
	var body: Node3D = get_parent() as Node3D
	if body == null:
		return Vector3.UP
	var power_node: PowerNode = null
	for child in body.get_children():
		if child is PowerNode:
			power_node = child
			break
	if power_node and power_node.connected_nodes.size() > 0:
		var source_node: Node3D = power_node.connected_nodes[0] as Node3D
		if source_node:
			var source_structure: Node3D = source_node.get_parent() as Node3D
			if source_structure:
				var world_dir: Vector3 = body.global_position - source_structure.global_position
				world_dir.y = 0.0
				if world_dir.length() > 0.001:
					var local_dir: Vector3 = body.global_basis.inverse() * world_dir.normalized()
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


func _apply_hull_params(mat: Material, _mesh_inst: MeshInstance3D = null) -> void:
	if not mat is ShaderMaterial:
		return
	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	if shader_mat.shader == null or shader_mat.shader.resource_path != STRUCTURE_HULL_SHADER_PATH:
		return
	var dir_local: Vector3 = _get_build_print_direction_local()
	var axis_data: Dictionary = _compute_axis_projection_from_bounds(dir_local)
	shader_mat.set_shader_parameter("print_direction", dir_local)
	shader_mat.set_shader_parameter("axis_center", float(axis_data.get("center", 0.0)))
	shader_mat.set_shader_parameter("axis_extent", maxf(float(axis_data.get("extent", 1.0)), 0.01))
	shader_mat.set_shader_parameter("build_radius", maxf(_build_bounds_radius_local * maxf(_build_fx_radius_multiplier, 0.1), 0.01))


func _restore_materials() -> void:
	for i in range(_mesh_instances.size()):
		if i < _original_materials.size() and _original_materials[i]:
			var mat_to_set: Material = (_original_materials[i] as Material).duplicate()
			_apply_hull_params(mat_to_set, _mesh_instances[i])
			_mesh_instances[i].set_surface_override_material(0, mat_to_set)
	_build_shader_materials.clear()


func _register_with_render_manager() -> void:
	if _registered_with_render_manager or _mesh_instances.is_empty():
		return
	var body: Node3D = get_parent() as Node3D
	if body == null or not has_node("/root/StructureRenderManager"):
		return
	var accent_mesh_names: Array[String] = _resolve_accent_mesh_names()
	var props: Dictionary = _get_register_structure_props()
	var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
	if render_manager and render_manager.has_method("register_structure"):
		render_manager.call("register_structure", body, _mesh_instances, accent_mesh_names, props)
		render_manager.call("set_structure_powered", body, _is_powered_visual)
	_registered_with_render_manager = true


## Override to pass props to StructureRenderManager (e.g. accent_no_shadow_mesh_names).
func _get_register_structure_props() -> Dictionary:
	return {}


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


func _process(_delta: float) -> void:
	_update_build_animation()


func _update_build_animation() -> void:
	if _is_upgrade_animating:
		return
	var body: Node = get_parent()
	if body == null:
		return
	var construction_component: Node = body.get_node_or_null("ConstructionComponent")
	if construction_component == null or construction_component.get("is_built") == true:
		return
	var progress: float = construction_component.get_progress() if construction_component.has_method("get_progress") else 0.0
	var print_dir_local: Vector3 = _get_build_print_direction_local()
	var axis_data: Dictionary = _compute_axis_projection_from_bounds(print_dir_local)
	for build_mat in _build_shader_materials:
		if build_mat:
			build_mat.set_shader_parameter("build_progress", progress)
			build_mat.set_shader_parameter("print_direction", print_dir_local)
			build_mat.set_shader_parameter("axis_center", float(axis_data.get("center", 0.0)))
			build_mat.set_shader_parameter("axis_extent", maxf(float(axis_data.get("extent", 1.0)), 0.01))
			build_mat.set_shader_parameter("build_radius", maxf(_build_bounds_radius_local * maxf(_build_fx_radius_multiplier, 0.1), 0.01))
			build_mat.set_shader_parameter("finalize_blend", 0.0)


func _on_construction_completed() -> void:
	if _entity and _entity.has_method("remove_component"):
		_entity.remove_component(C_ConstructionClass)
	_start_build_finalize_tween()


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
	_build_finalize_tween.tween_callback(_finish_construction_visuals)


func _finish_construction_visuals() -> void:
	_build_finalize_tween = null
	_restore_materials()
	_register_with_render_manager()
	var body: Node = get_parent()
	if body and body.has_method("has_operational_power"):
		set_powered_visual_state(body.has_operational_power())
	_play_construction_finish_animation()
	var selectable: Node = get_parent().get_node_or_null("SelectableComponent") if get_parent() else null
	if selectable and selectable.has_method("notify_details_changed"):
		selectable.notify_details_changed()


func _play_construction_finish_animation() -> void:
	pass


func set_powered_visual_state(is_powered: bool) -> void:
	_is_powered_visual = is_powered
	if _registered_with_render_manager:
		var body: Node3D = get_parent() as Node3D
		if body and has_node("/root/StructureRenderManager"):
			var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
			if render_manager and render_manager.has_method("set_structure_powered"):
				render_manager.call("set_structure_powered", body, is_powered)
		return
	for i in range(_mesh_instances.size()):
		var mesh_inst: MeshInstance3D = _mesh_instances[i]
		var mat: StandardMaterial3D = mesh_inst.get_active_material(0) as StandardMaterial3D
		if mat == null:
			continue
		var mesh_name: String = mesh_inst.name.to_lower()
		var is_accent: bool = _mesh_instances.size() == 1 or mesh_name.contains("active") or mesh_name.contains("orb") or mesh_name.contains("panel") or mesh_name.contains("core")
		if not is_accent:
			continue
		if is_powered:
			if i < _original_materials.size() and _original_materials[i]:
				mesh_inst.set_surface_override_material(0, (_original_materials[i] as Material).duplicate())
		else:
			var off_mat: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
			off_mat.albedo_color = off_mat.albedo_color.lerp(Color(0.2, 0.22, 0.26, 1.0), 0.75)
			off_mat.emission_enabled = false
			off_mat.emission = Color(0.0, 0.0, 0.0, 1.0)
			off_mat.emission_energy_multiplier = 0.0
			mesh_inst.set_surface_override_material(0, off_mat)


func _on_health_destroyed() -> void:
	pass


func start_upgrade_animation() -> void:
	if _is_upgrade_animating:
		return
	_is_upgrade_animating = true
	_upgrade_progress_visual = 0.0
	if _build_finalize_tween:
		_build_finalize_tween.kill()
		_build_finalize_tween = null
	if _registered_with_render_manager:
		var body: Node3D = get_parent() as Node3D
		if body and has_node("/root/StructureRenderManager"):
			var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
			if render_manager and render_manager.has_method("unregister_structure"):
				render_manager.call("unregister_structure", body)
		_registered_with_render_manager = false
	_build_shader_materials.clear()
	_original_materials.clear()
	_setup_build_animation()
	var print_dir_local: Vector3 = _get_build_print_direction_local()
	var axis_data: Dictionary = _compute_axis_projection_from_bounds(print_dir_local)
	for build_mat in _build_shader_materials:
		if build_mat:
			build_mat.set_shader_parameter("build_progress", 0.55)
			build_mat.set_shader_parameter("finalize_blend", 0.0)
			build_mat.set_shader_parameter("print_direction", print_dir_local)
			build_mat.set_shader_parameter("axis_center", float(axis_data.get("center", 0.0)))
			build_mat.set_shader_parameter("axis_extent", maxf(float(axis_data.get("extent", 1.0)), 0.01))
			build_mat.set_shader_parameter("build_radius", maxf(_build_bounds_radius_local * maxf(_build_fx_radius_multiplier, 0.1), 0.01))


func set_upgrade_progress(progress: float) -> void:
	if not _is_upgrade_animating:
		return
	_upgrade_progress_visual = clampf(progress, 0.0, 1.0)
	var rebuild_progress: float = 0.55 + (progress * 0.45)
	for build_mat in _build_shader_materials:
		if build_mat:
			build_mat.set_shader_parameter("build_progress", rebuild_progress)
			build_mat.set_shader_parameter("finalize_blend", 0.0)


func complete_upgrade_animation() -> void:
	if not _is_upgrade_animating:
		return
	_is_upgrade_animating = false
	_upgrade_progress_visual = 0.0
	for build_mat in _build_shader_materials:
		if build_mat:
			build_mat.set_shader_parameter("build_progress", 1.0)
			build_mat.set_shader_parameter("finalize_blend", 0.0)
	_start_build_finalize_tween()


func _exit_tree() -> void:
	if _registered_with_render_manager:
		var body: Node3D = get_parent() as Node3D
		if body and has_node("/root/StructureRenderManager"):
			var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
			if render_manager and render_manager.has_method("unregister_structure"):
				render_manager.call("unregister_structure", body)
		_registered_with_render_manager = false

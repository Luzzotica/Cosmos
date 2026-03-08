extends Node
class_name StructureBehavior
## Helper node for structure build animation and powered visual state.
## Parent must be an Entity (Node3D with Entity script). Finds mesh instances in parent.
## Subclass and override _play_construction_finish_animation() for structure-specific visuals.

@export_group("Build FX Tuning")
@export var build_fx_center_offset: Vector3 = Vector3.ZERO
@export var build_fx_radius_multiplier: float = 1.15

var _original_materials: Array[Material] = []
var _mesh_instances: Array[MeshInstance3D] = []
var _build_shader_materials: Array[ShaderMaterial] = []
var _build_finalize_tween: Tween = null
var _build_bounds_center_local: Vector3 = Vector3.ZERO
var _build_bounds_extents_local: Vector3 = Vector3.ONE
var _build_bounds_radius_local: float = 1.0
var _registered_with_render_manager: bool = false
var _is_powered_visual: bool = true
const BUILD_SHELL_SHADER_PATH: String = "res://shaders/structure_build_shell.gdshader"
var _build_shell_shader: Shader = null


func _get_entity() -> Node:
	return get_parent()


func _ready() -> void:
	_setup_build_animation()


func setup_after_ecs() -> void:
	var entity: Node = _get_entity()
	if not entity:
		return
	var c_construction: C_Construction = entity.get_component(C_Construction) as C_Construction if entity.has_method("get_component") else null
	var is_under_construction: bool = c_construction != null and not c_construction.is_built
	if is_under_construction and c_construction != null:
		c_construction.build_progress_changed.connect(_on_build_progress_changed)
		update_build_animation(c_construction.build_progress)
	else:
		_restore_materials()
		_register_with_render_manager()


func _on_build_progress_changed(progress: float) -> void:
	update_build_animation(progress)
	var entity: Node = _get_entity()
	if entity and entity.get("selectable_component"):
		var sel = entity.selectable_component
		if sel and sel.has_method("is_selected") and sel.is_selected() and sel.has_method("notify_details_changed"):
			sel.notify_details_changed()


func _setup_build_animation() -> void:
	_find_mesh_instances(_get_entity())
	_compute_build_bounds_local()
	if _build_shell_shader == null:
		_build_shell_shader = load(BUILD_SHELL_SHADER_PATH) as Shader
	for mesh_inst in _mesh_instances:
		var mat: Material = mesh_inst.get_active_material(0)
		if mat:
			var original_copy: Material = mat.duplicate()
			_original_materials.append(original_copy)
			var build_mat: ShaderMaterial = _create_build_shader_material(mesh_inst, mat)
			_build_shader_materials.append(build_mat)
			if build_mat:
				mesh_inst.set_surface_override_material(0, build_mat)
		else:
			_original_materials.append(null)
			_build_shader_materials.append(null)


func _find_mesh_instances(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		_mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		if child is SelectionVisuals or child.name == "SelectionVisuals":
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


func _get_material_base_color(mat: Material) -> Color:
	var standard: StandardMaterial3D = mat as StandardMaterial3D
	if standard:
		return standard.albedo_color
	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	if shader_mat:
		var base_col: Variant = shader_mat.get_shader_parameter("base_color")
		if base_col is Color:
			return base_col
	return Color(0.72, 0.75, 0.8, 1.0)


func _get_build_print_direction_local() -> Vector3:
	var entity: Node = _get_entity()
	if entity and ECS and ECS.world and entity.has_method("get_component"):
		var active_node: Variant = PowerGraph._get_active_power_node(entity) if PowerGraph else null
		if active_node and active_node.connected_entity_ids.size() > 0:
			var first_id: int = active_node.connected_entity_ids[0]
			var entities: Array = ECS.world.query.with_all([C_Structure]).execute()
			for e in entities:
				if e.get_instance_id() == first_id:
					var c_struct: C_Structure = e.get_component(C_Structure) as C_Structure
					if c_struct and c_struct.structure_node:
						var source_structure: Node3D = c_struct.structure_node as Node3D
						var world_dir: Vector3 = entity.global_position - source_structure.global_position
						world_dir.y = 0.0
						if world_dir.length() > 0.001:
							var local_dir: Vector3 = entity.global_basis.inverse() * world_dir.normalized()
							local_dir.y = 0.0
							if local_dir.length() > 0.001:
								return local_dir.normalized()
					break
	return Vector3.UP


func _compute_axis_projection_from_bounds(direction: Vector3) -> Dictionary:
	var dir: Vector3 = direction.normalized()
	if dir.length() < 0.001:
		dir = Vector3.UP
	var axis_center: float = _build_bounds_center_local.dot(dir)
	var axis_extent: float = absf(dir.x) * _build_bounds_extents_local.x + absf(dir.y) * _build_bounds_extents_local.y + absf(dir.z) * _build_bounds_extents_local.z
	axis_extent = maxf(axis_extent, _build_bounds_radius_local * 0.55)
	return {"center": axis_center, "extent": maxf(axis_extent, 0.01)}


func _create_build_shader_material(mesh_inst: MeshInstance3D, original_mat: Material) -> ShaderMaterial:
	if _build_shell_shader == null or mesh_inst == null or mesh_inst.mesh == null:
		return null
	var dir_local: Vector3 = _get_build_print_direction_local()
	var axis_data: Dictionary = _compute_axis_projection_from_bounds(dir_local)
	var build_mat: ShaderMaterial = ShaderMaterial.new()
	build_mat.shader = _build_shell_shader
	build_mat.set_shader_parameter("build_progress", 0.0)
	build_mat.set_shader_parameter("final_color", _get_material_base_color(original_mat))
	build_mat.set_shader_parameter("print_direction", dir_local)
	build_mat.set_shader_parameter("axis_center", float(axis_data.get("center", 0.0)))
	build_mat.set_shader_parameter("axis_extent", maxf(float(axis_data.get("extent", 1.0)), 0.01))
	build_mat.set_shader_parameter("build_radius", maxf(_build_bounds_radius_local * maxf(build_fx_radius_multiplier, 0.1), 0.01))
	build_mat.set_shader_parameter("finalize_blend", 0.0)
	return build_mat


func update_build_animation(progress: float) -> void:
	var entity: Node = _get_entity()
	if entity == null:
		return
	entity.scale = Vector3.ONE
	var print_dir_local: Vector3 = _get_build_print_direction_local()
	var axis_data: Dictionary = _compute_axis_projection_from_bounds(print_dir_local)
	for build_mat in _build_shader_materials:
		if build_mat:
			build_mat.set_shader_parameter("build_progress", progress)
			build_mat.set_shader_parameter("print_direction", print_dir_local)
			build_mat.set_shader_parameter("axis_center", float(axis_data.get("center", 0.0)))
			build_mat.set_shader_parameter("axis_extent", maxf(float(axis_data.get("extent", 1.0)), 0.01))
			build_mat.set_shader_parameter("build_radius", maxf(_build_bounds_radius_local * maxf(build_fx_radius_multiplier, 0.1), 0.01))
			build_mat.set_shader_parameter("finalize_blend", 0.0)


func on_construction_completed() -> void:
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
	_build_finalize_tween.tween_callback(func() -> void:
		_build_finalize_tween = null
		_finish_construction_visuals()
	)


func _finish_construction_visuals() -> void:
	_restore_materials()
	_register_with_render_manager()
	var entity: Node = _get_entity()
	if entity and entity.has_method("has_operational_power"):
		set_powered_visual_state(entity.has_operational_power())
	_play_construction_finish_animation()
	if entity and entity.get("selectable_component"):
		var sel = entity.selectable_component
		if sel and sel.has_method("notify_details_changed"):
			sel.notify_details_changed()


func _play_construction_finish_animation() -> void:
	pass


func _restore_materials() -> void:
	for i in range(_mesh_instances.size()):
		if i < _original_materials.size() and _original_materials[i]:
			_mesh_instances[i].set_surface_override_material(0, _original_materials[i].duplicate())
	_build_shader_materials.clear()


func _register_with_render_manager() -> void:
	if _registered_with_render_manager:
		return
	if not has_node("/root/StructureRenderManager"):
		return
	if _mesh_instances.is_empty():
		return
	var entity: Node = _get_entity()
	if entity == null:
		return
	var accent_mesh_names: Array[String] = _resolve_accent_mesh_names()
	var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
	if render_manager == null:
		return
	render_manager.call("register_structure", entity, _mesh_instances, accent_mesh_names)
	render_manager.call("set_structure_powered", entity, _is_powered_visual)
	_registered_with_render_manager = true


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
		var entity: Node = _get_entity()
		if entity:
			var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
			if render_manager:
				render_manager.call("set_structure_powered", entity, is_powered)
				return
	for i in range(_mesh_instances.size()):
		var mesh_inst: MeshInstance3D = _mesh_instances[i]
		var mat: Material = mesh_inst.get_active_material(0)
		if mat == null:
			continue
		var mesh_name: String = mesh_inst.name.to_lower()
		var is_accent_mesh: bool = _mesh_instances.size() == 1 or mesh_name.contains("active") or mesh_name.contains("orb") or mesh_name.contains("panel") or mesh_name.contains("core")
		if not is_accent_mesh:
			continue
		if is_powered:
			if i < _original_materials.size() and _original_materials[i]:
				mesh_inst.set_surface_override_material(0, _original_materials[i].duplicate())
		else:
			var shader_mat: ShaderMaterial = mat as ShaderMaterial
			if shader_mat != null and shader_mat.shader != null and "structure_accent" in shader_mat.shader.resource_path:
				var off_mat: ShaderMaterial = shader_mat.duplicate()
				var base_col: Color = off_mat.get_shader_parameter("base_color")
				off_mat.set_shader_parameter("base_color", base_col.lerp(Color(0.2, 0.22, 0.26, 1.0), 0.75))
				off_mat.set_shader_parameter("emission_strength", 0.0)
				mesh_inst.set_surface_override_material(0, off_mat)
			else:
				var off_mat: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
				if off_mat:
					off_mat.albedo_color = off_mat.albedo_color.lerp(Color(0.2, 0.22, 0.26, 1.0), 0.75)
					off_mat.emission_enabled = false
					off_mat.emission = Color(0.0, 0.0, 0.0, 1.0)
					off_mat.emission_energy_multiplier = 0.0
					mesh_inst.set_surface_override_material(0, off_mat)


func _exit_tree() -> void:
	if _registered_with_render_manager:
		var entity: Node = _get_entity()
		if entity:
			var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
			if render_manager:
				render_manager.call("unregister_structure", entity)
	_registered_with_render_manager = false

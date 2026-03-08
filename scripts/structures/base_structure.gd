extends Node3D
class_name BaseStructure
## Base class for all structures

# Preload ECS components so class_names resolve (load order)
const _C_Structure: GDScript = preload("res://scripts/ecs/components/c_structure.gd")
const _C_PowerNode: GDScript = preload("res://scripts/ecs/components/c_power_node.gd")
const _C_ConstructionPowerNode: GDScript = preload("res://scripts/ecs/components/c_construction_power_node.gd")
const _PowerConstants: GDScript = preload("res://scripts/ecs/power_constants.gd")

signal destroyed

@export var building_type: String = ""
@export_group("Build FX Tuning")
@export var build_fx_center_offset: Vector3 = Vector3.ZERO
@export var build_fx_radius_multiplier: float = 1.15
@export_group("Placement Preview")
@export var placement_preview_include_mesh_names: PackedStringArray = PackedStringArray()
@export var placement_preview_exclude_mesh_names: PackedStringArray = PackedStringArray()

var is_destroyed: bool = false
var selectable_component: Node

# Build animation
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

var _ecs_entity: Node = null
var _pending_monolith_power_required: float = -1.0

## If true, structure uses instant build (completes construction immediately). Set by map loader, starter base, editor.
var spawned_structure: bool = false

func _ready() -> void:
	selectable_component = get_node_or_null("SelectableComponent")
	_setup_build_animation()
	# Defer so we run after Main._setup_ecs sets ECS.world (map structures load before ECS init)
	call_deferred("_register_ecs_entity")


func _register_ecs_entity() -> void:
	var ecs_node: Node = get_node_or_null("/root/ECS")
	var world = ecs_node.get("world") if ecs_node else null
	if ecs_node == null:
		return
	if world == null:
		return
	var entity_script: Script = load("res://scripts/ecs/entities/structure_entity.gd") as Script
	if entity_script == null:
		return
	_ecs_entity = Node.new()
	_ecs_entity.set_script(entity_script)
	_ecs_entity.name = "ECSEntity"
	add_child(_ecs_entity)
	# GECS best practice: entity supplies components via define_components()
	world.call("add_entity", _ecs_entity, null, false)
	# GECS duplicates components via res.duplicate(true), which can null out Node refs.
	# Set structure_node on the stored components after add_entity.
	var c_struct_script: Script = load("res://scripts/ecs/components/c_structure.gd") as Script
	if c_struct_script:
		var stored: Resource = _ecs_entity.get_component(c_struct_script)
		if stored:
			stored.set("structure_node", self)
	for comp_script in [_C_Structure, _C_PowerNode, _C_ConstructionPowerNode, C_PowerSource, C_PowerUser, C_PowerGenerator, C_MonolithCharge]:
		var comp: Resource = _ecs_entity.get_component(comp_script)
		if comp:
			comp.set("structure_node", self)
	var c_charge: C_MonolithCharge = _ecs_entity.get_component(C_MonolithCharge) as C_MonolithCharge
	if c_charge and _pending_monolith_power_required > 0:
		c_charge.power_required = _pending_monolith_power_required
	# Sync max_connections for BuildManager when structure acts as power node proxy
	var c_pn: C_PowerNode = _ecs_entity.get_component(C_PowerNode) as C_PowerNode
	if c_pn:
		max_connections = c_pn.max_connections

	# Apply build animation state now that entity exists (keep shader if under construction)
	_apply_build_state_after_ecs()


## Override in subclasses to set c_power_node.node_type and return type-specific components (C_PowerSource, C_MiningProfile, etc.).
func _get_structure_type_components(c_power_node: C_PowerNode, build_data: Resource) -> Array:
	c_power_node.node_type = C_PowerNode.NodeType.NODE  # Default: relay
	return []


## Override in subclasses (e.g. LaserTurret) to add structure-specific ECS components.
func _get_extra_ecs_components() -> Array:
	return []


func _sync_ecs_construction_complete() -> void:
	if _ecs_entity == null:
		return
	var ConstructionScript: GDScript = load("res://scripts/ecs/components/c_construction.gd") as GDScript
	if ConstructionScript == null:
		return
	var c_construction: Resource = _ecs_entity.get_component(ConstructionScript)
	if c_construction != null:
		c_construction.set("is_built", true)
		c_construction.set("build_progress", 1.0)


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
			_original_materials.append(original_copy)
			var build_mat: ShaderMaterial = _create_build_shader_material(mesh_inst, mat)
			_build_shader_materials.append(build_mat)
			if build_mat:
				mesh_inst.set_surface_override_material(0, build_mat)
		else:
			_original_materials.append(null)
			_build_shader_materials.append(null)
	
	# Construction state applied in _register_ecs_entity (runs deferred, entity exists by then)


func _apply_build_state_after_ecs() -> void:
	## Runs after _register_ecs_entity so we can correctly detect construction state.
	if _is_under_construction():
		scale = Vector3.ONE
	else:
		_restore_materials()
		_register_with_render_manager()


func _find_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		_mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		# Selection rings are runtime UI feedback and must never be multimesh-batched as structure geometry.
		if child is SelectionVisuals or child.name == "SelectionVisuals":
			continue
		_find_mesh_instances(child)


func _process(delta: float) -> void:
	_update_build_animation(delta)
	if selectable_component and selectable_component.is_selected():
		selectable_component.notify_details_changed()


func _is_under_construction() -> bool:
	if _ecs_entity:
		var c_construction: C_Construction = _ecs_entity.get_component(C_Construction) as C_Construction
		if c_construction and not c_construction.is_built:
			return true
	return false


func _get_build_progress() -> float:
	if _ecs_entity:
		var c_construction: C_Construction = _ecs_entity.get_component(C_Construction) as C_Construction
		if c_construction:
			return c_construction.build_progress
	return 1.0


func _update_build_animation(_delta: float) -> void:
	if not _is_under_construction():
		return
	
	var progress: float = _get_build_progress()
	
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
	# ConstructionSystem calls this via signal when build completes.
	_start_build_finalize_tween()
	scale = Vector3.ONE


func _restore_materials() -> void:
	for i in range(_mesh_instances.size()):
		if i < _original_materials.size() and _original_materials[i]:
			_mesh_instances[i].set_surface_override_material(0, _original_materials[i].duplicate())
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
	_sync_ecs_construction_complete()
	# Use actual power state at build completion, not cached _is_powered_visual.
	# Structures with PowerUser may have set _is_powered_visual=false in _ready when
	# the buffer was empty (during construction). The graph has power now; sync visual.
	set_powered_visual_state(has_operational_power())
	_play_construction_finish_animation()
	if selectable_component:
		selectable_component.notify_details_changed()


func _play_construction_finish_animation() -> void:
	pass


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


func _create_build_shader_material(mesh_inst: MeshInstance3D, original_mat: Material) -> ShaderMaterial:
	if _build_shell_shader == null:
		return null
	if mesh_inst == null or mesh_inst.mesh == null:
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


func _get_build_print_direction_local() -> Vector3:
	if _ecs_entity and ECS and ECS.world:
		# Use active node - C_ConstructionPowerNode during build, C_PowerNode when built
		var active_node: Variant = PowerGraph._get_active_power_node(_ecs_entity) if PowerGraph else null
		if active_node and active_node.connected_entity_ids.size() > 0:
			var first_id: int = active_node.connected_entity_ids[0]
			var entities: Array = ECS.world.query.with_all([C_Structure]).execute()
			for e in entities:
				if e.get_instance_id() == first_id:
					var c_struct: C_Structure = e.get_component(C_Structure) as C_Structure
					if c_struct and c_struct.structure_node:
						var source_structure: Node3D = c_struct.structure_node as Node3D
						var world_dir: Vector3 = global_position - source_structure.global_position
						world_dir.y = 0.0
						if world_dir.length() > 0.001:
							var local_dir: Vector3 = global_basis.inverse() * world_dir.normalized()
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
	if _ecs_entity and ECS and ECS.world:
		ECS.world.remove_entity(_ecs_entity)
		_ecs_entity = null


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
		var mat: Material = mesh_inst.get_active_material(0)
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


func has_operational_power() -> bool:
	if not is_built():
		return false
	if building_type == "solar_panel":
		return true
	if _ecs_entity:
		var c_power_user: C_PowerUser = _ecs_entity.get_component(C_PowerUser) as C_PowerUser
		if c_power_user:
			return c_power_user.has_power()
		var c_power_node: C_PowerNode = _ecs_entity.get_component(C_PowerNode) as C_PowerNode
		if c_power_node:
			if not c_power_node.is_enabled:
				return false
			if not PowerGraph:
				return c_power_node.connected_entity_ids.size() > 0
			var sg: Variant = PowerGraph.find_subgraph_for_entity(_ecs_entity)
			if sg == null:
				return false
			return float(sg.power_current) > 0.0
		return true
	return true


func _on_destroyed() -> void:
	is_destroyed = true
	if _ecs_entity != null and ECS != null and ECS.world != null:
		ECS.world.remove_entity(_ecs_entity)
		_ecs_entity = null
	destroyed.emit()
	queue_free()


## Get the team string for this structure
func get_team() -> String:
	if _ecs_entity:
		var c_team: C_Team = _ecs_entity.get_component(C_Team) as C_Team
		if c_team:
			return c_team.team
	return "player"


## Take damage
func take_damage(amount: float) -> void:
	if _ecs_entity:
		var c_health: C_Health = _ecs_entity.get_component(C_Health) as C_Health
		if c_health:
			c_health.current = maxf(0.0, c_health.current - amount)


func take_damage_event(event_payload: Dictionary) -> float:
	if _ecs_entity:
		var c_health: C_Health = _ecs_entity.get_component(C_Health) as C_Health
		if c_health:
			var amount: float = float(event_payload.get("amount", 0.0))
			var dmg_type: String = String(event_payload.get("damage_type", "generic"))
			var multiplier: float = c_health.resistance_profile.get(dmg_type, 1.0) if c_health.resistance_profile else 1.0
			var actual: float = amount * multiplier
			c_health.current = maxf(0.0, c_health.current - actual)
			return actual
	return 0.0


## For BuildManager compatibility - structure acts as power node proxy
func can_accept_more_connections() -> bool:
	if _ecs_entity and PowerGraph:
		var c_power_node: C_PowerNode = _ecs_entity.get_component(C_PowerNode) as C_PowerNode
		if c_power_node:
			return PowerGraph.can_power_node_accept_more_connections(c_power_node)
	return false


## For BuildManager when structure acts as power node proxy
var max_connections: int = 4


## For PowerGraphManager reconnect - returns C_PowerNode.NodeType
func get_node_type() -> int:
	if _ecs_entity:
		var c_power_node: C_PowerNode = _ecs_entity.get_component(C_PowerNode) as C_PowerNode
		if c_power_node:
			return c_power_node.node_type
	return C_PowerNode.NodeType.NODE


## For PowerGraphManager - max connection distance
func get_max_connection_distance() -> float:
	if _ecs_entity:
		var c_power_node: C_PowerNode = _ecs_entity.get_component(C_PowerNode) as C_PowerNode
		if c_power_node:
			return c_power_node.max_connection_distance
	return PowerConstants.CONNECTION_RANGE


## For PowerGraphManager - check if can connect to other structure
func can_connect_to(other: Node3D) -> bool:
	if other == self:
		return false
	var other_struct: BaseStructure = other as BaseStructure
	if other_struct == null or not other_struct.has_method("get_node_type"):
		return false
	if not can_accept_more_connections():
		return false
	if not other_struct.can_accept_more_connections():
		return false
	return true


## For PowerGraphManager - establish bidirectional connection (updates ECS)
func connect_node(other: Node3D) -> void:
	if _ecs_entity == null or other == self:
		return
	var other_struct: BaseStructure = other as BaseStructure
	if other_struct == null or other_struct._ecs_entity == null:
		return
	var my_id: int = _ecs_entity.get_instance_id()
	var other_id: int = other_struct._ecs_entity.get_instance_id()
	var c_power_node: C_PowerNode = _ecs_entity.get_component(C_PowerNode) as C_PowerNode
	var other_c_power_node: C_PowerNode = other_struct._ecs_entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node and other_c_power_node:
		if other_id not in c_power_node.connected_entity_ids:
			c_power_node.connected_entity_ids.append(other_id)
		if my_id not in other_c_power_node.connected_entity_ids:
			other_c_power_node.connected_entity_ids.append(my_id)


## For BuildManager compatibility
func is_valid_connection_target() -> bool:
	if _ecs_entity and PowerGraph:
		return PowerGraph.is_entity_valid_connection_target(_ecs_entity)
	return false


## Check if construction is complete
func is_built() -> bool:
	if _ecs_entity:
		var c_construction: C_Construction = _ecs_entity.get_component(C_Construction) as C_Construction
		if c_construction:
			return c_construction.is_built
	return true


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

	if _ecs_entity:
		var c_health: C_Health = _ecs_entity.get_component(C_Health) as C_Health
		if c_health:
			details["health_current"] = c_health.current
			details["health_max"] = c_health.maximum
		var c_construction: C_Construction = _ecs_entity.get_component(C_Construction) as C_Construction
		if c_construction and not c_construction.is_built:
			details["build_progress"] = c_construction.build_progress * 100.0
		var c_power_node: C_PowerNode = _ecs_entity.get_component(C_PowerNode) as C_PowerNode
		if c_power_node:
			details["is_powered"] = has_operational_power()
			details["is_connected"] = c_power_node.connected_entity_ids.size() > 0
			details["connection_count"] = c_power_node.connected_entity_ids.size()

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

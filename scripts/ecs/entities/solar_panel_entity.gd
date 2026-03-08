extends Entity
class_name SolarPanelEntity
## Solar Panel entity — generates and stores power.
## Pure ECS entity. No BaseStructure dependency.

signal destroyed

@export var building_type: String = "solar_panel"
@export var pre_built: bool = false

@export_group("Build FX Tuning")
@export var build_fx_center_offset: Vector3 = Vector3.ZERO
@export var build_fx_radius_multiplier: float = 1.15

@export_group("Placement Preview")
@export var placement_preview_include_mesh_names: PackedStringArray = PackedStringArray()
@export var placement_preview_exclude_mesh_names: PackedStringArray = PackedStringArray()

var is_destroyed: bool = false
var is_active: bool = false
var selectable_component: Node
var max_connections: int = 20

@onready var structure_root: Node3D = $StructureRoot
@onready var panel_mesh: MeshInstance3D = $StructureRoot/Panel

# ── Build animation state ──────────────────────────────────────────────
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

# ── Panel intro animation ──────────────────────────────────────────────
var _panel_intro_complete: bool = false
var _panel_intro_tween: Tween = null
var _panel_rest_y: float = 1.5


# ════════════════════════════════════════════════════════════════════════
#  ECS LIFECYCLE
# ════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	selectable_component = structure_root.get_node_or_null("SelectableComponent") if structure_root else null
	_setup_build_animation()


func define_components() -> Array:
	var build_data: Resource = BuildManager.get_building_data(building_type) if BuildManager else null

	# C_Structure
	var c_structure: C_Structure = C_Structure.new()
	c_structure.building_type = building_type
	c_structure.is_destroyed = is_destroyed

	# C_Health
	var max_health_val: float = 75.0
	if build_data and build_data.get("max_health") != null:
		max_health_val = float(build_data.max_health)
	var c_health: C_Health = C_Health.new()
	c_health.maximum = max_health_val
	c_health.current = max_health_val

	# C_Team
	var c_team: C_Team = C_Team.new()
	c_team.team = "player"

	# C_Transform3D
	var c_transform: C_Transform3D = C_Transform3D.new()
	if structure_root:
		c_transform.position = structure_root.global_position
		c_transform.rotation = structure_root.rotation

	# C_Construction
	var c_construction: C_Construction = C_Construction.new()
	var construction_time_val: float = 3.0
	if build_data and build_data.get("construction_time") != null:
		construction_time_val = float(build_data.construction_time)
	c_construction.construction_time = construction_time_val
	c_construction.requires_power = true
	c_construction.build_power_cost = 10.0
	c_construction.is_built = pre_built
	c_construction.build_progress = 1.0 if pre_built else 0.0

	var components: Array = [c_structure, c_health, c_team, c_transform, c_construction]

	# C_PowerNode (SOURCE for solar panel)
	var c_power_node: C_PowerNode = C_PowerNode.new()
	c_power_node.node_type = C_PowerNode.NodeType.SOURCE
	c_power_node.max_connection_distance = PowerConstants.CONNECTION_RANGE
	c_power_node.max_connections = 20
	if build_data and build_data.get("max_connections") != null:
		c_power_node.max_connections = int(build_data.max_connections)
	c_power_node.is_enabled = pre_built
	components.append(c_power_node)
	max_connections = c_power_node.max_connections

	# Construction-phase components (removed by ConstructionSystem on completion)
	if not pre_built:
		var c_build_node: C_ConstructionPowerNode = C_ConstructionPowerNode.new()
		c_build_node.max_connection_distance = PowerConstants.CONNECTION_RANGE
		c_build_node.max_connections = c_power_node.max_connections
		components.append(c_build_node)
		var c_user: C_PowerUser = C_PowerUser.new()
		c_user.is_construction_user = true
		c_user.use_power_cost = 10.0
		c_user.buffer_capacity = 15.0
		components.append(c_user)

	# C_PowerSource (solar panel stores power)
	var c_source: C_PowerSource = C_PowerSource.new()
	c_source.max_storage = 100.0
	if build_data and build_data.get("max_energy_storage") != null:
		c_source.max_storage = float(build_data.max_energy_storage)
	components.append(c_source)

	# C_PowerGenerator (solar panel produces power)
	var c_gen: C_PowerGenerator = C_PowerGenerator.new()
	c_gen.power_output = 10.0
	if build_data and build_data.get("energy_production") != null:
		c_gen.power_output = float(build_data.energy_production)
	components.append(c_gen)

	return components


func on_ready() -> void:
	_fix_structure_node_refs()
	_apply_build_state()


func _fix_structure_node_refs() -> void:
	for comp_script in [C_Structure, C_PowerNode, C_ConstructionPowerNode, C_PowerSource, C_PowerUser, C_PowerGenerator]:
		var comp: Resource = get_component(comp_script)
		if comp and "structure_node" in comp:
			comp.structure_node = structure_root


# ════════════════════════════════════════════════════════════════════════
#  FRAME UPDATE
# ════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if structure_root == null:
		return
	_update_build_animation(delta)
	if not is_built():
		return
	is_active = true
	set_powered_visual_state(true)
	if selectable_component and selectable_component.is_selected():
		selectable_component.notify_details_changed()


# ════════════════════════════════════════════════════════════════════════
#  CONSTRUCTION STATE
# ════════════════════════════════════════════════════════════════════════

func is_built() -> bool:
	var c_construction: C_Construction = get_component(C_Construction) as C_Construction
	if c_construction:
		return c_construction.is_built
	return true


func _is_under_construction() -> bool:
	var c_construction: C_Construction = get_component(C_Construction) as C_Construction
	if c_construction and not c_construction.is_built:
		return true
	return false


func _get_build_progress() -> float:
	var c_construction: C_Construction = get_component(C_Construction) as C_Construction
	if c_construction:
		return c_construction.build_progress
	return 1.0


func set_pre_built(value: bool) -> void:
	if value:
		pre_built = true
		var c_construction: C_Construction = get_component(C_Construction) as C_Construction
		if c_construction:
			c_construction.is_built = true
			c_construction.build_progress = 1.0
		var c_power_node: C_PowerNode = get_component(C_PowerNode) as C_PowerNode
		if c_power_node:
			c_power_node.is_enabled = true
		_on_construction_completed()


func set_starter_panel(is_starter: bool) -> void:
	if is_starter:
		set_pre_built(true)
		is_active = true


func _on_construction_completed() -> void:
	_start_build_finalize_tween()
	if structure_root:
		structure_root.scale = Vector3.ONE


func _sync_ecs_construction_complete() -> void:
	var c_construction: C_Construction = get_component(C_Construction) as C_Construction
	if c_construction:
		c_construction.is_built = true
		c_construction.build_progress = 1.0


# ════════════════════════════════════════════════════════════════════════
#  BUILD ANIMATION (construction print shader)
# ════════════════════════════════════════════════════════════════════════

func _setup_build_animation() -> void:
	if structure_root == null:
		return
	_find_mesh_instances(structure_root)
	_compute_build_bounds_local()
	if _build_shell_shader == null:
		_build_shell_shader = load(BUILD_SHELL_SHADER_PATH) as Shader
	for mesh_inst in _mesh_instances:
		var mat: Material = mesh_inst.get_active_material(0)
		if mat:
			_original_materials.append(mat.duplicate())
			var build_mat: ShaderMaterial = _create_build_shader_material(mesh_inst, mat)
			_build_shader_materials.append(build_mat)
			if build_mat:
				mesh_inst.set_surface_override_material(0, build_mat)
		else:
			_original_materials.append(null)
			_build_shader_materials.append(null)


func _apply_build_state() -> void:
	if _is_under_construction():
		if structure_root:
			structure_root.scale = Vector3.ONE
	else:
		_restore_materials()
		_register_with_render_manager()


func _find_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		_mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		if child is SelectionVisuals or child.name == "SelectionVisuals":
			continue
		_find_mesh_instances(child)


func _update_build_animation(_delta: float) -> void:
	if not _is_under_construction():
		return
	var progress: float = _get_build_progress()
	if structure_root:
		structure_root.scale = Vector3.ONE
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
	set_powered_visual_state(true)
	_play_construction_finish_animation()
	if selectable_component:
		selectable_component.notify_details_changed()


func _restore_materials() -> void:
	for i in range(_mesh_instances.size()):
		if i < _original_materials.size() and _original_materials[i]:
			_mesh_instances[i].set_surface_override_material(0, _original_materials[i].duplicate())
	_build_shader_materials.clear()


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
	if structure_root == null:
		return Vector3.UP
	if ECS and ECS.world:
		var active_node: Variant = PowerGraph._get_active_power_node(self) if PowerGraph else null
		if active_node and active_node.connected_entity_ids.size() > 0:
			var first_id: int = active_node.connected_entity_ids[0]
			var entities: Array = ECS.world.query.with_all([C_Structure]).execute()
			for e in entities:
				if e.get_instance_id() == first_id:
					var c_struct: C_Structure = e.get_component(C_Structure) as C_Structure
					if c_struct and c_struct.structure_node:
						var source_structure: Node3D = c_struct.structure_node as Node3D
						var world_dir: Vector3 = structure_root.global_position - source_structure.global_position
						world_dir.y = 0.0
						if world_dir.length() > 0.001:
							var local_dir: Vector3 = structure_root.global_basis.inverse() * world_dir.normalized()
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


# ════════════════════════════════════════════════════════════════════════
#  SOLAR PANEL — construction finish + sun tracking
# ════════════════════════════════════════════════════════════════════════

func _play_construction_finish_animation() -> void:
	if panel_mesh == null:
		return
	if _panel_intro_tween:
		_panel_intro_tween.kill()
		_panel_intro_tween = null
	_panel_intro_complete = false
	var start_pos: Vector3 = panel_mesh.global_position
	var start_basis: Basis = panel_mesh.global_basis
	panel_mesh.global_position = start_pos
	var target_pos: Vector3 = Vector3(panel_mesh.global_position.x, _panel_rest_y, panel_mesh.global_position.z)
	var target_basis: Basis = _get_panel_target_basis()
	_panel_intro_tween = create_tween()
	_panel_intro_tween.set_trans(Tween.TRANS_CUBIC)
	_panel_intro_tween.set_ease(Tween.EASE_OUT)
	_panel_intro_tween.tween_property(panel_mesh, "global_position", target_pos, 0.5)
	_panel_intro_tween.tween_method(func(t: float) -> void:
		if panel_mesh == null:
			return
		var blended_q: Quaternion = Quaternion(start_basis.orthonormalized()).slerp(Quaternion(target_basis.orthonormalized()), t)
		panel_mesh.global_transform = Transform3D(Basis(blended_q).orthonormalized(), panel_mesh.global_position)
	, 0.0, 1.0, 0.3)
	_panel_intro_tween.tween_callback(func() -> void:
		_panel_intro_complete = true
		_panel_intro_tween = null
	)


func _get_panel_target_basis() -> Basis:
	var sun: DirectionalLight3D = GameWorld.sun_light if GameWorld else null
	if sun == null or not is_instance_valid(sun):
		return panel_mesh.global_basis if panel_mesh else Basis.IDENTITY
	var toward_sun: Vector3 = sun.global_basis.z.normalized()
	if toward_sun.length() <= 0.001:
		return panel_mesh.global_basis if panel_mesh else Basis.IDENTITY
	var up: Vector3 = Vector3.UP
	if abs(toward_sun.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var basis_to_sun: Basis = Basis.looking_at(toward_sun, up)
	return (basis_to_sun * Basis(Vector3.RIGHT, PI * 0.5)).orthonormalized()


func is_sun_tracking_active() -> bool:
	return _panel_intro_complete


# ════════════════════════════════════════════════════════════════════════
#  RENDER MANAGER + POWERED VISUAL STATE
# ════════════════════════════════════════════════════════════════════════

func _register_with_render_manager() -> void:
	if _registered_with_render_manager or structure_root == null:
		return
	if not has_node("/root/StructureRenderManager"):
		return
	if _mesh_instances.is_empty():
		return
	var accent_mesh_names: Array[String] = _resolve_accent_mesh_names()
	var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
	if render_manager == null:
		return
	render_manager.call("register_structure", structure_root, _mesh_instances, accent_mesh_names)
	render_manager.call("set_structure_powered", structure_root, _is_powered_visual)
	_registered_with_render_manager = true


func _unregister_from_render_manager() -> void:
	if not _registered_with_render_manager:
		return
	var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
	if render_manager:
		render_manager.call("unregister_structure", structure_root)
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
			render_manager.call("set_structure_powered", structure_root, is_powered)
			return
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


# ════════════════════════════════════════════════════════════════════════
#  POWER INTERFACE (BuildManager / PowerGraph compatibility)
# ════════════════════════════════════════════════════════════════════════

func has_operational_power() -> bool:
	if not is_built():
		return false
	return true


func can_accept_more_connections() -> bool:
	if PowerGraph:
		var c_power_node: C_PowerNode = get_component(C_PowerNode) as C_PowerNode
		if c_power_node:
			return PowerGraph.can_power_node_accept_more_connections(c_power_node)
	return false


func get_node_type() -> int:
	var c_power_node: C_PowerNode = get_component(C_PowerNode) as C_PowerNode
	if c_power_node:
		return c_power_node.node_type
	return C_PowerNode.NodeType.SOURCE


func get_max_connection_distance() -> float:
	var c_power_node: C_PowerNode = get_component(C_PowerNode) as C_PowerNode
	if c_power_node:
		return c_power_node.max_connection_distance
	return PowerConstants.CONNECTION_RANGE


func can_connect_to(other: Node3D) -> bool:
	if structure_root == null:
		return false
	if other == structure_root:
		return false
	if not other.has_method("can_accept_more_connections"):
		return false
	if not can_accept_more_connections():
		return false
	if not other.can_accept_more_connections():
		return false
	return true


func connect_node(other: Node3D) -> void:
	if structure_root == null or other == structure_root:
		return
	var other_entity: Entity = _resolve_entity_from_node(other)
	if other_entity == null:
		return
	var my_id: int = get_instance_id()
	var other_id: int = other_entity.get_instance_id()
	var c_power_node: C_PowerNode = get_component(C_PowerNode) as C_PowerNode
	var other_pn: C_PowerNode = other_entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node and other_pn:
		if other_id not in c_power_node.connected_entity_ids:
			c_power_node.connected_entity_ids.append(other_id)
		if my_id not in other_pn.connected_entity_ids:
			other_pn.connected_entity_ids.append(my_id)


func is_valid_connection_target() -> bool:
	if PowerGraph:
		return PowerGraph.is_entity_valid_connection_target(self)
	return false


func _resolve_entity_from_node(node: Node3D) -> Entity:
	if node is Entity:
		return node as Entity
	# Legacy BaseStructure: entity is stored in _ecs_entity
	var ecs_entity: Variant = node.get("_ecs_entity")
	if ecs_entity is Entity:
		return ecs_entity as Entity
	# Check if node is a child of an entity (our StructureRoot pattern)
	var parent: Node = node.get_parent()
	if parent is Entity:
		return parent as Entity
	return null


# ════════════════════════════════════════════════════════════════════════
#  HEALTH + DAMAGE
# ════════════════════════════════════════════════════════════════════════

func take_damage(amount: float) -> void:
	var c_health: C_Health = get_component(C_Health) as C_Health
	if c_health:
		c_health.current = maxf(0.0, c_health.current - amount)


func take_damage_event(event_payload: Dictionary) -> float:
	var c_health: C_Health = get_component(C_Health) as C_Health
	if c_health:
		var amount: float = float(event_payload.get("amount", 0.0))
		var dmg_type: String = String(event_payload.get("damage_type", "generic"))
		var multiplier: float = c_health.resistance_profile.get(dmg_type, 1.0) if c_health.resistance_profile else 1.0
		var actual: float = amount * multiplier
		c_health.current = maxf(0.0, c_health.current - actual)
		return actual
	return 0.0


func get_team() -> String:
	var c_team: C_Team = get_component(C_Team) as C_Team
	if c_team:
		return c_team.team
	return "player"


# ════════════════════════════════════════════════════════════════════════
#  DESTRUCTION + CLEANUP
# ════════════════════════════════════════════════════════════════════════

func _on_destroyed() -> void:
	is_destroyed = true
	var c_structure: C_Structure = get_component(C_Structure) as C_Structure
	if c_structure:
		c_structure.is_destroyed = true
	if ECS and ECS.world:
		ECS.world.remove_entity(self)
	destroyed.emit()
	queue_free()


func _exit_tree() -> void:
	_unregister_from_render_manager()
	if ECS and ECS.world:
		ECS.world.remove_entity(self)


# ════════════════════════════════════════════════════════════════════════
#  SELECTION INTERFACE
# ════════════════════════════════════════════════════════════════════════

func get_selection_name() -> String:
	return building_type.replace("_", " ").capitalize()


func get_selection_details() -> Dictionary:
	var details: Dictionary = {
		"name": get_selection_name(),
		"category": "structure",
		"faction": get_team(),
		"building_type": building_type,
		"is_built": is_built(),
		"stats": []
	}
	var c_health: C_Health = get_component(C_Health) as C_Health
	if c_health:
		details["health_current"] = c_health.current
		details["health_max"] = c_health.maximum
	var c_construction: C_Construction = get_component(C_Construction) as C_Construction
	if c_construction and not c_construction.is_built:
		details["build_progress"] = c_construction.build_progress * 100.0
	var c_power_node: C_PowerNode = get_component(C_PowerNode) as C_PowerNode
	if c_power_node:
		details["is_powered"] = has_operational_power()
		details["is_connected"] = c_power_node.connected_entity_ids.size() > 0
		details["connection_count"] = c_power_node.connected_entity_ids.size()
	var c_source: C_PowerSource = get_component(C_PowerSource) as C_PowerSource
	if c_source:
		details["energy_stored"] = c_source.current_storage
		details["energy_capacity"] = c_source.max_storage

	var stats: Array[Dictionary] = []
	stats.append({"label": "Type", "value": building_type.replace("_", " ").capitalize()})
	stats.append({"label": "Status", "value": "Operational" if details.is_built else "Building %.0f%%" % details.get("build_progress", 0.0)})
	if details.has("is_powered"):
		stats.append({"label": "Power", "value": "Online" if details.is_powered else "Offline"})
	if details.has("is_connected"):
		stats.append({"label": "Grid Link", "value": "Connected" if details.is_connected else "Disconnected"})
	if details.has("connection_count"):
		stats.append({"label": "Connections", "value": str(details.connection_count)})
	if c_source:
		stats.append({"label": "Energy", "value": "%.0f / %.0f" % [c_source.current_storage, c_source.max_storage]})
	details["stats"] = stats
	return details

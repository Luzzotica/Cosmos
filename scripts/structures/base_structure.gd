extends Node3D
class_name BaseStructure
## Base class for all structures

signal destroyed

@export var building_type: String = ""
@export_group("Build FX Tuning")
@export var build_fx_center_offset: Vector3 = Vector3.ZERO
@export var build_fx_radius_multiplier: float = 1.15

var team_component: TeamComponent
var health_component: HealthComponent
var construction_component: ConstructionComponent
var power_node: PowerNode

var is_destroyed: bool = false
var selectable_component: Node

# Build animation
var _original_materials: Array[StandardMaterial3D] = []
var _mesh_instances: Array[MeshInstance3D] = []
var _build_progress_ring: MeshInstance3D = null
var _build_ghost_materials: Array[StandardMaterial3D] = []
var _build_fx_sphere: MeshInstance3D = null
var _build_fx_material: ShaderMaterial = null
var _registered_with_render_manager: bool = false
var _is_powered_visual: bool = true
const BUILD_START_SCALE: float = 0.3
const BUILD_TRANSPARENCY: float = 0.5
const BUILD_SHELL_SHADER_PATH: String = "res://shaders/structure_build_shell.gdshader"
var _build_shell_shader: Shader = null

func _ready() -> void:
	print("[DEBUG] BaseStructure _ready called for: ", name)
	selectable_component = get_node_or_null("SelectableComponent")
	_setup_components()
	_connect_signals()
	_setup_build_animation()
	print("[DEBUG] BaseStructure initialization complete for: ", name, " - has Area3D: ", has_node("Area3D"))


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
	if _build_shell_shader == null:
		_build_shell_shader = load(BUILD_SHELL_SHADER_PATH) as Shader
	
	# Store original materials and create construction shell shader materials.
	for mesh_inst in _mesh_instances:
		var mat: StandardMaterial3D = mesh_inst.get_active_material(0) as StandardMaterial3D
		if mat:
			var original_copy: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
			_original_materials.append(original_copy)
			
			# Keep structure as a ghost while a separate build sphere runs the burn/warp effect.
			var ghost_mat: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
			ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost_mat.albedo_color.a = BUILD_TRANSPARENCY
			ghost_mat.emission_enabled = true
			if ghost_mat.emission == Color(0, 0, 0, 1):
				ghost_mat.emission = Color(0.1, 0.45, 0.85, 1.0)
			ghost_mat.emission_energy_multiplier = 1.4
			_build_ghost_materials.append(ghost_mat)
			mesh_inst.set_surface_override_material(0, ghost_mat)
		else:
			_original_materials.append(null)
			_build_ghost_materials.append(null)
	
	# Create the progress ring
	_create_build_progress_ring()
	_create_build_fx_sphere()
	
	# Set initial scale if under construction
	if construction_component and not construction_component.is_built:
		scale = Vector3.ONE
		if _build_progress_ring:
			_build_progress_ring.visible = true
		if _build_fx_sphere:
			_build_fx_sphere.visible = true
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


func _create_build_progress_ring() -> void:
	_build_progress_ring = MeshInstance3D.new()
	
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 1.5
	torus.outer_radius = 1.8
	torus.rings = 32
	torus.ring_segments = 32
	_build_progress_ring.mesh = torus
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 1.0, 0.6)  # Cyan
	material.emission_enabled = true
	material.emission = Color(0.1, 0.6, 1.0)
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_build_progress_ring.material_override = material
	
	# Torus is already flat on XZ plane, no rotation needed
	_build_progress_ring.position.y = 0.1
	_build_progress_ring.visible = false
	add_child(_build_progress_ring)


func _process(delta: float) -> void:
	_update_build_animation(delta)
	if selectable_component and selectable_component.is_selected():
		selectable_component.notify_details_changed()


func _update_build_animation(_delta: float) -> void:
	if not construction_component or construction_component.is_built:
		return
	
	var progress: float = construction_component.get_progress()
	
	# Keep final scale and fade materials in during construction.
	scale = Vector3.ONE
	
	# Keep structure ghosted for most of construction, then fade it out near completion.
	var ghost_fade: float = 1.0 - smoothstep(0.7, 0.97, progress)
	var ghost_alpha: float = clampf((0.12 + BUILD_TRANSPARENCY * 0.55) * ghost_fade, 0.02, 0.42)
	for i in range(_mesh_instances.size()):
		if i >= _build_ghost_materials.size():
			continue
		var ghost_mat: StandardMaterial3D = _build_ghost_materials[i]
		if ghost_mat:
			ghost_mat.albedo_color.a = ghost_alpha
			ghost_mat.emission_energy_multiplier = 0.4 + ghost_fade * 1.2
	
	# Drive the dedicated construction sphere shader.
	if _build_fx_material:
		_build_fx_material.set_shader_parameter("build_progress", progress)
	if _build_fx_sphere:
		_build_fx_sphere.visible = true
	
	# Update progress ring
	if _build_progress_ring:
		_build_progress_ring.visible = true
		# Rotate the ring
		_build_progress_ring.rotation_degrees.z += 180 * _delta
		var mat: StandardMaterial3D = _build_progress_ring.material_override as StandardMaterial3D
		if mat:
			var fade: float = clampf(1.0 - progress, 0.0, 1.0)
			mat.albedo_color.a = 0.6 * fade
			mat.emission_energy_multiplier = 0.5 + (2.5 * fade)


func _on_construction_completed() -> void:
	# Restore original materials
	_restore_materials()
	scale = Vector3.ONE
	if _build_progress_ring:
		_build_progress_ring.visible = false
	if _build_fx_sphere:
		_build_fx_sphere.visible = false
	_register_with_render_manager()
	set_powered_visual_state(_is_powered_visual)
	if selectable_component:
		selectable_component.notify_details_changed()


func _restore_materials() -> void:
	for i in range(_mesh_instances.size()):
		if i < _original_materials.size() and _original_materials[i]:
			_mesh_instances[i].set_surface_override_material(0, _original_materials[i].duplicate())
	_build_ghost_materials.clear()
	if _build_fx_sphere and is_instance_valid(_build_fx_sphere):
		_build_fx_sphere.queue_free()
	_build_fx_sphere = null
	_build_fx_material = null


func _create_build_fx_sphere() -> void:
	if _build_shell_shader == null:
		return
	
	var bounds: Dictionary = _compute_build_fx_bounds()
	var fx_center: Vector3 = bounds.get("center", Vector3.ZERO) + build_fx_center_offset
	var fx_radius: float = maxf(float(bounds.get("radius", 1.2)) * maxf(build_fx_radius_multiplier, 0.1), 0.6)
	
	_build_fx_sphere = MeshInstance3D.new()
	_build_fx_sphere.name = "BuildFxSphere"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = fx_radius
	sphere.height = sphere.radius * 2.0
	_build_fx_sphere.mesh = sphere
	_build_fx_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_fx_sphere.position = fx_center
	
	_build_fx_material = ShaderMaterial.new()
	_build_fx_material.shader = _build_shell_shader
	_build_fx_material.set_shader_parameter("build_progress", 0.0)
	_build_fx_material.set_shader_parameter("final_color", Color(0.16, 0.2, 0.28, 1.0))
	_build_fx_material.set_shader_parameter("min_local_y", -sphere.radius)
	_build_fx_material.set_shader_parameter("local_height", sphere.radius * 2.0)
	_build_fx_sphere.material_override = _build_fx_material
	_build_fx_sphere.visible = false
	add_child(_build_fx_sphere)


func _compute_build_fx_bounds() -> Dictionary:
	var has_bounds: bool = false
	var min_pos: Vector3 = Vector3.ZERO
	var max_pos: Vector3 = Vector3.ZERO
	
	for mesh_inst in _mesh_instances:
		if mesh_inst == null or mesh_inst.mesh == null:
			continue
		var local_aabb: AABB = mesh_inst.mesh.get_aabb()
		var mesh_aabb: AABB = local_aabb * mesh_inst.transform
		var mesh_min: Vector3 = mesh_aabb.position
		var mesh_max: Vector3 = mesh_aabb.position + mesh_aabb.size
		
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
		return {"center": Vector3.ZERO, "radius": 1.2}
	
	var center: Vector3 = (min_pos + max_pos) * 0.5
	var extents: Vector3 = (max_pos - min_pos) * 0.5
	var radius: float = maxf(extents.length(), 0.6)
	return {"center": center, "radius": radius}


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



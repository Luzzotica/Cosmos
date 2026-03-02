extends Node3D
class_name BaseStructure
## Base class for all structures

signal destroyed

@export var building_type: String = ""

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
const BUILD_START_SCALE: float = 0.3
const BUILD_TRANSPARENCY: float = 0.5

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
	
	# Store original materials and create transparent versions for building
	for mesh_inst in _mesh_instances:
		var mat: StandardMaterial3D = mesh_inst.get_active_material(0) as StandardMaterial3D
		if mat:
			var original_copy: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
			_original_materials.append(original_copy)
			
			# Make a building version (transparent, glowing)
			var build_mat: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
			build_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			build_mat.albedo_color.a = BUILD_TRANSPARENCY
			build_mat.emission_enabled = true
			if not build_mat.emission:
				build_mat.emission = build_mat.albedo_color
			build_mat.emission_energy_multiplier = 1.5
			mesh_inst.set_surface_override_material(0, build_mat)
		else:
			_original_materials.append(null)
	
	# Create the progress ring
	_create_build_progress_ring()
	
	# Set initial scale if under construction
	if construction_component and not construction_component.is_built:
		scale = Vector3.ONE * BUILD_START_SCALE
		if _build_progress_ring:
			_build_progress_ring.visible = true
	else:
		_restore_materials()


func _find_mesh_instances(node: Node) -> void:
	if node is MeshInstance3D:
		_mesh_instances.append(node as MeshInstance3D)
	for child in node.get_children():
		# Don't recurse into component nodes
		if child is TeamComponent or child is HealthComponent or child is ConstructionComponent or child is PowerNode:
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
	
	# Scale from BUILD_START_SCALE to 1.0
	var current_scale: float = BUILD_START_SCALE + (1.0 - BUILD_START_SCALE) * progress
	scale = Vector3.ONE * current_scale
	
	# Update material transparency (more opaque as it builds)
	var alpha: float = BUILD_TRANSPARENCY + (1.0 - BUILD_TRANSPARENCY) * progress
	for i in range(_mesh_instances.size()):
		var mesh_inst: MeshInstance3D = _mesh_instances[i]
		var mat: StandardMaterial3D = mesh_inst.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color.a = alpha
			mat.emission_energy_multiplier = 1.5 * (1.0 - progress) + 0.5  # Glow fades as it builds
	
	# Update progress ring
	if _build_progress_ring:
		_build_progress_ring.visible = true
		# Rotate the ring
		_build_progress_ring.rotation_degrees.z += 180 * _delta
		# Pulse the ring
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
		var mat: StandardMaterial3D = _build_progress_ring.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 2.0 + pulse * 2.0


func _on_construction_completed() -> void:
	# Restore original materials
	_restore_materials()
	scale = Vector3.ONE
	if _build_progress_ring:
		_build_progress_ring.visible = false
	if selectable_component:
		selectable_component.notify_details_changed()


func _restore_materials() -> void:
	for i in range(_mesh_instances.size()):
		if i < _original_materials.size() and _original_materials[i]:
			_mesh_instances[i].set_surface_override_material(0, _original_materials[i].duplicate())


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
		details["is_powered"] = power_node.is_enabled
		details["connection_count"] = power_node.connected_nodes.size()

	var stats: Array[Dictionary] = []
	stats.append({"label": "Type", "value": building_type.replace("_", " ").capitalize()})
	stats.append({"label": "Status", "value": "Operational" if details.is_built else "Building %.0f%%" % details.get("build_progress", 0.0)})
	if details.has("is_powered"):
		stats.append({"label": "Power", "value": "Connected" if details.is_powered else "Disconnected"})
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



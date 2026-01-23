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

# Build animation
var _original_materials: Array[StandardMaterial3D] = []
var _mesh_instances: Array[MeshInstance3D] = []
var _build_progress_ring: MeshInstance3D = null
const BUILD_START_SCALE: float = 0.3
const BUILD_TRANSPARENCY: float = 0.5


func _ready() -> void:
	_setup_components()
	_connect_signals()
	_setup_build_animation()


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
	
	_build_progress_ring.rotation_degrees.x = 90  # Flat on plane
	_build_progress_ring.position.y = 0.1
	_build_progress_ring.visible = false
	add_child(_build_progress_ring)


func _process(delta: float) -> void:
	_update_build_animation(delta)


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

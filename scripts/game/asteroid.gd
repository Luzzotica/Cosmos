extends Node3D
class_name Asteroid
## Asteroid - Minable resource node

signal minerals_changed(remaining: float, total: float)
signal depleted
signal destroyed  # For selection tracking

const MIN_SIZE: float = 2.0
const MAX_SIZE: float = 4.0
const MINERAL_DENSITY: float = 10.0  # Minerals per size unit
const ASTEROID_SHADER_PATH: String = "res://shaders/asteroid_sick.gdshader"
const MIN_ROTATION_SPEED: float = 0.04
const MAX_ROTATION_SPEED: float = 0.12

@export var asteroid_size: float = 3.0:
	set(value):
		asteroid_size = clampf(value, MIN_SIZE, MAX_SIZE)
		_update_visuals()

var total_minerals: float
var remaining_minerals: float
var is_depleted: bool = false
var selectable_component: Node
var _asteroid_shader: Shader = null
var _rotation_axis: Vector3 = Vector3.UP
var _rotation_speed: float = 0.0

# Mining impact visual
var _impact_ring: MeshInstance3D = null
var _impact_timer: float = 0.0
const IMPACT_DURATION: float = 0.4

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $SelectableComponent/CollisionShape3D
@onready var area_3d: Area3D = $SelectableComponent


func _ready() -> void:
	selectable_component = get_node_or_null("SelectableComponent")
	total_minerals = asteroid_size * MINERAL_DENSITY
	remaining_minerals = total_minerals
	_initialize_rotation()
	_create_unique_material()
	_create_impact_ring()
	_connect_signals()
	_update_visuals()


func _connect_signals() -> void:
	pass


func _process(delta: float) -> void:
	rotate(_rotation_axis, _rotation_speed * delta)
	_update_impact_effect(delta)
	if selectable_component and selectable_component.is_selected():
		selectable_component.notify_details_changed()


func _initialize_rotation() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	# Mostly Y-axis drift with a bit of tilt so asteroids feel alive but calm.
	_rotation_axis = Vector3(
		rng.randf_range(-0.25, 0.25),
		1.0,
		rng.randf_range(-0.25, 0.25)
	).normalized()
	_rotation_speed = rng.randf_range(MIN_ROTATION_SPEED, MAX_ROTATION_SPEED)


func _create_unique_material() -> void:
	if not mesh_instance:
		return

	if _asteroid_shader == null:
		_asteroid_shader = load(ASTEROID_SHADER_PATH) as Shader

	# Preferred look: procedural shader with per-instance randomization.
	if _asteroid_shader:
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.shader = _asteroid_shader
		_randomize_shader_material(shader_material)
		mesh_instance.set_surface_override_material(0, shader_material)
		return

	# Fallback if shader could not be loaded.
	var original_material: Material = mesh_instance.get_active_material(0)
	if original_material:
		var unique_material: StandardMaterial3D = original_material.duplicate() as StandardMaterial3D
		mesh_instance.set_surface_override_material(0, unique_material)


func _randomize_shader_material(shader_material: ShaderMaterial) -> void:
	var resource_percentage: float = remaining_minerals / total_minerals if total_minerals > 0 else 0.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	shader_material.set_shader_parameter("seed", rng.randf_range(0.0, 1000.0))
	shader_material.set_shader_parameter("deform_strength", rng.randf_range(0.26, 0.48))
	shader_material.set_shader_parameter("ridge_scale", rng.randf_range(2.2, 3.8))
	shader_material.set_shader_parameter("warp_scale", rng.randf_range(1.0, 1.8))
	shader_material.set_shader_parameter("warp_strength", rng.randf_range(0.20, 0.46))
	shader_material.set_shader_parameter("valley_sharpness", rng.randf_range(1.2, 2.0))
	shader_material.set_shader_parameter("line_frequency", rng.randf_range(16.0, 30.0))
	shader_material.set_shader_parameter("line_width", rng.randf_range(0.05, 0.10))
	shader_material.set_shader_parameter("line_scale", rng.randf_range(2.6, 5.0))
	shader_material.set_shader_parameter("line_contrast", rng.randf_range(0.32, 0.60))
	shader_material.set_shader_parameter("pulse_speed", rng.randf_range(0.8, 1.6))
	shader_material.set_shader_parameter("pulse_strength", rng.randf_range(0.16, 0.42))
	shader_material.set_shader_parameter("emission_base", rng.randf_range(0.38, 0.68))
	shader_material.set_shader_parameter("roughness", rng.randf_range(0.84, 0.97))
	shader_material.set_shader_parameter("metallic", rng.randf_range(0.0, 0.08))

	var hill_gray: float = rng.randf_range(0.38, 0.58)
	shader_material.set_shader_parameter("hill_color", Color(hill_gray, hill_gray * 0.98, hill_gray * 1.05))
	shader_material.set_shader_parameter(
		"valley_color",
		Color(rng.randf_range(0.04, 0.10), rng.randf_range(0.18, 0.34), rng.randf_range(0.06, 0.16))
	)
	shader_material.set_shader_parameter(
		"glow_color",
		Color(rng.randf_range(0.10, 0.22), rng.randf_range(0.88, 1.0), rng.randf_range(0.20, 0.38))
	)
	shader_material.set_shader_parameter("resource_level", resource_percentage)


## Create the impact ring effect mesh
func _create_impact_ring() -> void:
	_impact_ring = MeshInstance3D.new()
	
	# Create a torus mesh for the expanding ring effect
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.8
	torus.rings = 16
	torus.ring_segments = 24
	_impact_ring.mesh = torus
	
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 1.0, 0.3, 0.8)  # Bright green
	material.emission_enabled = true
	material.emission = Color(0.3, 1.0, 0.2)
	material.emission_energy_multiplier = 3.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impact_ring.material_override = material
	
	# Rotate to be flat on the plane
	# Torus is already flat on XZ plane, no rotation needed
	_impact_ring.visible = false
	add_child(_impact_ring)


## Show the mining impact visual effect
func show_mining_impact() -> void:
	_impact_timer = IMPACT_DURATION
	if _impact_ring:
		_impact_ring.visible = true
		_impact_ring.scale = Vector3.ONE * 0.5  # Start small
		var mat: StandardMaterial3D = _impact_ring.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color.a = 0.8
			mat.emission_energy_multiplier = 5.0


## Update the impact effect animation
func _update_impact_effect(delta: float) -> void:
	if not _impact_ring or _impact_timer <= 0:
		if _impact_ring:
			_impact_ring.visible = false
		return
	
	_impact_timer -= delta
	
	# Calculate progress (1 = just started, 0 = finished)
	var progress: float = _impact_timer / IMPACT_DURATION
	
	# Expand the ring as it fades
	var expand_factor: float = 1.0 + (1.0 - progress) * 2.0  # Expands from 1x to 3x
	_impact_ring.scale = Vector3.ONE * expand_factor * asteroid_size * 0.3
	
	# Fade out the ring
	var mat: StandardMaterial3D = _impact_ring.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = 0.8 * progress
		mat.emission_energy_multiplier = 5.0 * progress
	
	if _impact_timer <= 0:
		_impact_ring.visible = false


func _update_visuals() -> void:
	if not mesh_instance:
		return
	
	# Update mesh scale based on size
	var scale_factor: float = asteroid_size / 3.0  # Normalize to default size
	mesh_instance.scale = Vector3.ONE * scale_factor
	
	if collision_shape and collision_shape.shape is SphereShape3D:
		collision_shape.shape.radius = asteroid_size * 0.5
	
	# Update color based on remaining minerals
	_update_color()


func _update_color() -> void:
	if not mesh_instance or not mesh_instance.mesh:
		return
	
	var resource_percentage: float = remaining_minerals / total_minerals if total_minerals > 0 else 0.0
	var material: Material = mesh_instance.get_active_material(0)
	if material is ShaderMaterial:
		var shader_material: ShaderMaterial = material as ShaderMaterial
		# Keep pulse timing continuous by changing only intensity with resource updates.
		shader_material.set_shader_parameter("resource_level", resource_percentage)
		return
	
	# Green asteroids - darker when depleted, brighter green when full
	var base_color: Color = Color(
		0.1 + 0.1 * resource_percentage,  # R: slight variation
		0.3 + 0.5 * resource_percentage,  # G: strong green
		0.1 + 0.2 * resource_percentage   # B: slight variation
	)
	
	# Emission color - glows more when full of minerals
	var emission_color: Color = Color(
		0.05,
		0.2 + 0.4 * resource_percentage,  # Brighter green glow when full
		0.05
	)
	
	var standard_material: StandardMaterial3D = material as StandardMaterial3D
	if standard_material:
		standard_material.albedo_color = base_color
		standard_material.emission = emission_color
		standard_material.emission_energy_multiplier = 0.3 + 0.7 * resource_percentage


## Mine minerals from this asteroid
func mine_minerals(amount: int) -> int:
	if is_depleted:
		return 0
	
	var actual_amount: int = mini(amount, int(remaining_minerals))
	remaining_minerals -= actual_amount
	
	minerals_changed.emit(remaining_minerals, total_minerals)
	_update_color()
	
	if remaining_minerals <= 0:
		is_depleted = true
		depleted.emit()
		if selectable_component:
			selectable_component.notify_details_changed()
	
	return actual_amount


## Set the asteroid size
func set_size(size: float) -> void:
	asteroid_size = size
	total_minerals = asteroid_size * MINERAL_DENSITY
	remaining_minerals = total_minerals
	_update_visuals()


## Set the mineral amount directly
func set_minerals(minerals: float) -> void:
	total_minerals = minerals
	remaining_minerals = minerals
	_update_color()


## Reset the asteroid
func reset() -> void:
	remaining_minerals = total_minerals
	is_depleted = false
	_update_color()


## Get remaining mineral percentage
func get_mineral_percentage() -> float:
	if total_minerals <= 0:
		return 0.0
	return remaining_minerals / total_minerals


## Create a random asteroid at position
static func create_random(pos: Vector3) -> Asteroid:
	var asteroid_scene: PackedScene = load("res://scenes/game/asteroid.tscn") as PackedScene
	if not asteroid_scene:
		return null
	
	var asteroid: Asteroid = asteroid_scene.instantiate() as Asteroid
	if asteroid:
		asteroid.global_position = pos
		asteroid.asteroid_size = randf_range(MIN_SIZE, MAX_SIZE)
	
	return asteroid


## Handle mouse input for selection
func _on_input_event(_camera: Node, _event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	pass


func _on_mouse_entered() -> void:
	pass


func _on_mouse_exited() -> void:
	pass


func _on_selection_changed(_entity: Node3D, _entity_type: String) -> void:
	pass


func _on_selection_cleared() -> void:
	pass


func _update_visual_feedback() -> void:
	pass


## Called when this entity is deselected
func on_deselected() -> void:
	pass


func get_selection_name() -> String:
	return "Asteroid"


func get_selection_details() -> Dictionary:
	return {
		"name": get_selection_name(),
		"category": "asteroid",
		"faction": "neutral",
		"size": asteroid_size,
		"is_depleted": is_depleted,
		"resource_current": remaining_minerals,
		"resource_max": total_minerals,
		"stats": [
			{"label": "Size", "value": "%.1f" % asteroid_size},
			{"label": "Status", "value": "Depleted" if is_depleted else "Mineable"}
		]
	}


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		destroyed.emit()

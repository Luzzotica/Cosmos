extends Node3D
class_name Asteroid
## Asteroid - Minable resource node

signal minerals_changed(remaining: float, total: float)
signal depleted

const MIN_SIZE: float = 2.0
const MAX_SIZE: float = 4.0
const MINERAL_DENSITY: float = 10.0  # Minerals per size unit

@export var asteroid_size: float = 3.0:
	set(value):
		asteroid_size = clampf(value, MIN_SIZE, MAX_SIZE)
		_update_visuals()

var total_minerals: float
var remaining_minerals: float
var is_depleted: bool = false

# Mining impact visual
var _impact_ring: MeshInstance3D = null
var _impact_timer: float = 0.0
const IMPACT_DURATION: float = 0.4

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D


func _ready() -> void:
	total_minerals = asteroid_size * MINERAL_DENSITY
	remaining_minerals = total_minerals
	_create_unique_material()
	_create_impact_ring()
	_update_visuals()


func _process(delta: float) -> void:
	_update_impact_effect(delta)


func _create_unique_material() -> void:
	if not mesh_instance:
		return
	
	# Create a unique material for this asteroid instance
	var original_material: Material = mesh_instance.get_active_material(0)
	if original_material:
		var unique_material: StandardMaterial3D = original_material.duplicate() as StandardMaterial3D
		mesh_instance.set_surface_override_material(0, unique_material)


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
	_impact_ring.rotation_degrees.x = 90
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
	
	var material: StandardMaterial3D = mesh_instance.get_active_material(0) as StandardMaterial3D
	if material:
		material.albedo_color = base_color
		material.emission = emission_color
		material.emission_energy_multiplier = 0.3 + 0.7 * resource_percentage


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

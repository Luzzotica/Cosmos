extends Node3D
class_name AsteroidBody
## Asteroid visual and collision body. Child of AsteroidEntity; syncs with C_Asteroid via entity.

const ASTEROID_SHADER_PATH: String = "res://shaders/asteroid_sick.gdshader"
const MIN_ROTATION_SPEED: float = 0.04
const MAX_ROTATION_SPEED: float = 0.12
const IMPACT_DURATION: float = 0.4

var _entity_ref: Entity = null
var _asteroid_shader: Shader = null
var _rotation_axis: Vector3 = Vector3.UP
var _rotation_speed: float = 0.0

var _impact_ring: MeshInstance3D = null
var _impact_timer: float = 0.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $SelectableComponent/CollisionShape3D
@onready var selectable_component: Node = $SelectableComponent


func set_entity_ref(entity: Entity) -> void:
	_entity_ref = entity
	_create_unique_material()
	_update_visuals()


func get_asteroid_size() -> float:
	if _entity_ref:
		var c: C_Asteroid = _entity_ref.get_component(C_Asteroid) as C_Asteroid
		return c.size if c else 3.0
	return 3.0


func get_selection_name() -> String:
	return "Asteroid"


func get_selection_details() -> Dictionary:
	if _entity_ref and _entity_ref.has_method("get_selection_details"):
		return _entity_ref.call("get_selection_details")
	return {}


func get_total_minerals() -> float:
	if _entity_ref:
		var c: C_Asteroid = _entity_ref.get_component(C_Asteroid) as C_Asteroid
		return c.total_minerals if c else 30.0
	return 30.0


func _ready() -> void:
	_initialize_rotation()
	_create_unique_material()
	_create_impact_ring()
	_update_visuals()


func _process(delta: float) -> void:
	rotate(_rotation_axis, _rotation_speed * delta)
	_update_impact_effect(delta)
	if selectable_component and selectable_component.is_selected():
		selectable_component.notify_details_changed()


func _initialize_rotation() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
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
	if _asteroid_shader:
		var shader_material: ShaderMaterial = ShaderMaterial.new()
		shader_material.shader = _asteroid_shader
		_randomize_shader_material(shader_material)
		mesh_instance.set_surface_override_material(0, shader_material)
		return
	var original_material: Material = mesh_instance.get_active_material(0)
	if original_material:
		var unique_material: StandardMaterial3D = original_material.duplicate() as StandardMaterial3D
		mesh_instance.set_surface_override_material(0, unique_material)


func _randomize_shader_material(shader_material: ShaderMaterial) -> void:
	var resource_percentage: float = 1.0
	if _entity_ref:
		var c: C_Asteroid = _entity_ref.get_component(C_Asteroid) as C_Asteroid
		if c and c.total_minerals > 0:
			resource_percentage = c.remaining_minerals / c.total_minerals
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


func _create_impact_ring() -> void:
	_impact_ring = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.8
	torus.rings = 16
	torus.ring_segments = 24
	_impact_ring.mesh = torus
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 1.0, 0.3, 0.8)
	material.emission_enabled = true
	material.emission = Color(0.3, 1.0, 0.2)
	material.emission_energy_multiplier = 3.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impact_ring.material_override = material
	_impact_ring.visible = false
	add_child(_impact_ring)


func show_mining_impact() -> void:
	_impact_timer = IMPACT_DURATION
	if _impact_ring:
		_impact_ring.visible = true
		_impact_ring.scale = Vector3.ONE * 0.5
		var mat: StandardMaterial3D = _impact_ring.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color.a = 0.8
			mat.emission_energy_multiplier = 5.0


func _update_impact_effect(delta: float) -> void:
	if not _impact_ring or _impact_timer <= 0:
		if _impact_ring:
			_impact_ring.visible = false
		return
	_impact_timer -= delta
	var progress: float = _impact_timer / IMPACT_DURATION
	var sz: float = get_asteroid_size()
	var expand_factor: float = 1.0 + (1.0 - progress) * 2.0
	_impact_ring.scale = Vector3.ONE * expand_factor * sz * 0.3
	var mat: StandardMaterial3D = _impact_ring.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = 0.8 * progress
		mat.emission_energy_multiplier = 5.0 * progress
	if _impact_timer <= 0:
		_impact_ring.visible = false


func _on_minerals_changed() -> void:
	_update_color()


func _on_size_changed() -> void:
	_update_visuals()


func _update_visuals() -> void:
	if not mesh_instance:
		return
	var sz: float = get_asteroid_size()
	var scale_factor: float = sz / 3.0
	mesh_instance.scale = Vector3.ONE * scale_factor
	if collision_shape and collision_shape.shape is SphereShape3D:
		collision_shape.shape.radius = sz * 0.5
	_update_color()


func _update_color() -> void:
	if not mesh_instance or not mesh_instance.mesh:
		return
	var resource_percentage: float = 0.0
	if _entity_ref:
		var c: C_Asteroid = _entity_ref.get_component(C_Asteroid) as C_Asteroid
		if c and c.total_minerals > 0:
			resource_percentage = c.remaining_minerals / c.total_minerals
	var material: Material = mesh_instance.get_active_material(0)
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("resource_level", resource_percentage)
		return
	var base_color: Color = Color(
		0.1 + 0.1 * resource_percentage,
		0.3 + 0.5 * resource_percentage,
		0.1 + 0.2 * resource_percentage
	)
	var emission_color: Color = Color(0.05, 0.2 + 0.4 * resource_percentage, 0.05)
	var standard_material: StandardMaterial3D = material as StandardMaterial3D
	if standard_material:
		standard_material.albedo_color = base_color
		standard_material.emission = emission_color
		standard_material.emission_energy_multiplier = 0.3 + 0.7 * resource_percentage

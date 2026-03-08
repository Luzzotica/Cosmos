extends BaseStructure
class_name SolarPanel
## Solar Panel - Generates and stores power

var is_active: bool = false
@onready var panel_mesh: MeshInstance3D = $Panel

func _get_structure_type_components(c_power_node: C_PowerNode, build_data: Resource) -> Array:
	c_power_node.node_type = C_PowerNode.NodeType.SOURCE
	var arr: Array = []
	var c_source: C_PowerSource = C_PowerSource.new()
	c_source.structure_node = self
	c_source.max_storage = 100.0
	if build_data and build_data.get("max_energy_storage") != null:
		c_source.max_storage = float(build_data.max_energy_storage)
	arr.append(c_source)
	var c_gen: C_PowerGenerator = C_PowerGenerator.new()
	c_gen.structure_node = self
	c_gen.power_output = 10.0
	if build_data and build_data.get("energy_production") != null:
		c_gen.power_output = float(build_data.energy_production)
	arr.append(c_gen)
	return arr

var _panel_intro_complete: bool = false
var _panel_intro_tween: Tween = null
var _panel_rest_y: float = 1.5


func _ready() -> void:
	building_type = "solar_panel"
	super._ready()



func _process(_delta: float) -> void:
	super._process(_delta)
	if not is_built():
		return

	is_active = true
	if has_method("set_powered_visual_state"):
		call("set_powered_visual_state", is_active)


func is_sun_tracking_active() -> bool:
	return _panel_intro_complete


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
	# Step 1: float up into place.
	_panel_intro_tween.tween_property(panel_mesh, "global_position", target_pos, 0.5)
	# Step 2: rotate toward sun after floating.
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

extends BaseStructure
class_name SolarPanel
## Solar Panel - Generates and stores power

var power_source: PowerSource
var power_generator: PowerGenerator
var is_active: bool = false
var _is_starter_panel: bool = false
@export var sun_light_path: NodePath = NodePath("/root/Main/DirectionalLight3D")
@onready var panel_mesh: MeshInstance3D = $Panel

var _sun_light: DirectionalLight3D = null
var _panel_intro_complete: bool = false
var _panel_intro_tween: Tween = null
var _panel_rest_y: float = 1.5


func _ready() -> void:
	building_type = "solar_panel"
	super._ready()
	_setup_power_components()
	_resolve_sun_light()


func _setup_power_components() -> void:
	# Find power components
	if power_node:
		for child in power_node.get_children():
			if child is PowerSource:
				power_source = child
				for source_child in power_source.get_children():
					if source_child is PowerGenerator:
						power_generator = source_child


func set_starter_panel(is_starter: bool) -> void:
	_is_starter_panel = is_starter
	super.set_starter_panel(is_starter)
	
	if is_starter and power_source:
		# Start with 50% power
		power_source.current_storage = power_source.max_storage * 0.5
		is_active = true


func _process(_delta: float) -> void:
	super._process(_delta)
	if not is_built():
		return
	
	is_active = true
	if has_method("set_powered_visual_state"):
		call("set_powered_visual_state", is_active)
	if _panel_intro_complete:
		_orient_panel_toward_light()


func _resolve_sun_light() -> void:
	_sun_light = null
	if not sun_light_path.is_empty():
		_sun_light = get_node_or_null(sun_light_path) as DirectionalLight3D


func _orient_panel_toward_light() -> void:
	if panel_mesh == null:
		return
	if _sun_light == null or not is_instance_valid(_sun_light):
		_resolve_sun_light()
		if _sun_light == null:
			return
	
	# DirectionalLight3D emits in a fixed direction; use it so all panels align consistently.
	var toward_sun: Vector3 = _sun_light.global_basis.z.normalized()
	if toward_sun.length() <= 0.001:
		return
	var up: Vector3 = Vector3.UP
	if abs(toward_sun.dot(up)) > 0.99:
		up = Vector3.RIGHT
	
	var basis_to_sun: Basis = Basis.looking_at(toward_sun, up)
	# Align the panel's +Y normal toward the sun direction.
	var panel_basis: Basis = basis_to_sun * Basis(Vector3.RIGHT, PI * 0.5)
	panel_mesh.global_transform = Transform3D(panel_basis.orthonormalized(), panel_mesh.global_position)


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
	if _sun_light == null or not is_instance_valid(_sun_light):
		_resolve_sun_light()
		if _sun_light == null:
			return panel_mesh.global_basis if panel_mesh else Basis.IDENTITY
	
	var toward_sun: Vector3 = _sun_light.global_basis.z.normalized()
	if toward_sun.length() <= 0.001:
		return panel_mesh.global_basis if panel_mesh else Basis.IDENTITY
	var up: Vector3 = Vector3.UP
	if abs(toward_sun.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var basis_to_sun: Basis = Basis.looking_at(toward_sun, up)
	return (basis_to_sun * Basis(Vector3.RIGHT, PI * 0.5)).orthonormalized()

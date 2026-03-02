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

extends BaseStructure
class_name PowerNodeStructure
## Power Node - Relay structure for extending power grid

@onready var active_connection_ring: MeshInstance3D = $ActiveConnectionRing

func _get_structure_type_components(c_power_node: C_PowerNode, build_data: Resource) -> Array:
	c_power_node.node_type = C_PowerNode.NodeType.NODE
	return []
@onready var connection_point: Node3D = $ConnectionPoint

var _ring_intro_tween: Tween = null


func _ready() -> void:
	building_type = "power_node"
	super._ready()
	if active_connection_ring:
		active_connection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Defer: _ecs_entity is set in _register_ecs_entity (deferred from super._ready)
		call_deferred("_apply_build_phase_ring_visibility")


func _apply_build_phase_ring_visibility() -> void:
	if active_connection_ring == null:
		return
	if not is_built():
		active_connection_ring.visible = false
		active_connection_ring.scale = Vector3.ZERO


func _process(delta: float) -> void:
	super._process(delta)
	if not is_built():
		# Keep ring hidden during construction
		if active_connection_ring and active_connection_ring.visible:
			active_connection_ring.visible = false
			active_connection_ring.scale = Vector3.ZERO
		return

	var powered: bool = has_operational_power()
	if has_method("set_powered_visual_state"):
		call("set_powered_visual_state", powered)


func _play_construction_finish_animation() -> void:
	if active_connection_ring == null:
		return
	if _ring_intro_tween:
		_ring_intro_tween.kill()
		_ring_intro_tween = null

	active_connection_ring.visible = true
	active_connection_ring.scale = Vector3.ZERO
	var mat: Material = active_connection_ring.get_active_material(0)
	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	if shader_mat != null:
		shader_mat.set_shader_parameter("emission_strength", 5.0)
	else:
		var std_mat: StandardMaterial3D = mat as StandardMaterial3D
		if std_mat:
			std_mat.emission_energy_multiplier = 5.0

	_ring_intro_tween = create_tween()
	_ring_intro_tween.set_trans(Tween.TRANS_BACK)
	_ring_intro_tween.set_ease(Tween.EASE_OUT)
	_ring_intro_tween.tween_property(active_connection_ring, "scale", Vector3.ONE, 0.38)
	_ring_intro_tween.tween_callback(func() -> void:
		_ring_intro_tween = null
	)

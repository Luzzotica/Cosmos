extends BaseStructure
class_name PowerNodeStructure
## Power Node - Relay structure for extending power grid

@onready var active_connection_orb: MeshInstance3D = $Root/ActiveConnectionOrb
@onready var connection_point: Node3D = $ConnectionPoint

var _orb_intro_tween: Tween = null
var _orb_rest_local_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	building_type = "power_node"
	super._ready()
	if active_connection_orb:
		active_connection_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_orb_rest_local_pos = active_connection_orb.position
		if not is_built():
			active_connection_orb.scale = Vector3.ZERO


func _process(delta: float) -> void:
	super._process(delta)
	if not is_built():
		return
	
	var powered: bool = has_operational_power()
	if has_method("set_powered_visual_state"):
		call("set_powered_visual_state", powered)


func _play_construction_finish_animation() -> void:
	if active_connection_orb == null:
		return
	if _orb_intro_tween:
		_orb_intro_tween.kill()
		_orb_intro_tween = null
	
	var target_pos: Vector3 = _orb_rest_local_pos
	if connection_point:
		target_pos = connection_point.position
	
	active_connection_orb.visible = true
	active_connection_orb.position = target_pos
	active_connection_orb.scale = Vector3.ZERO
	var mat: StandardMaterial3D = active_connection_orb.get_active_material(0) as StandardMaterial3D
	if mat:
		mat.emission_energy_multiplier = 5.0
	
	_orb_intro_tween = create_tween()
	_orb_intro_tween.set_trans(Tween.TRANS_BACK)
	_orb_intro_tween.set_ease(Tween.EASE_OUT)
	_orb_intro_tween.tween_property(active_connection_orb, "scale", Vector3.ONE, 0.38)
	_orb_intro_tween.tween_callback(func() -> void:
		_orb_intro_tween = null
	)

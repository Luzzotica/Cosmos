extends "res://scripts/structures/structure_visual_handler.gd"
class_name PowerNodeVisualHandler
## Power Node visuals: ActiveConnectionOrb orb intro on construction finish, powered-state updates.

@onready var _body: Node3D = get_parent() as Node3D
@onready var _active_orb: MeshInstance3D = _body.get_node_or_null("VisualRoot/ActiveConnectionOrb") as MeshInstance3D
@onready var _connection_point: Node3D = _body.get_node_or_null("VisualRoot/ConnectionPoint") as Node3D

var _orb_intro_tween: Tween = null
var _orb_rest_local_pos: Vector3 = Vector3.ZERO


func _get_register_structure_props() -> Dictionary:
	return {"accent_no_shadow_mesh_names": ["ActiveConnectionOrb"]}


func init(entity: Node) -> void:
	super.init(entity)
	if _body and _active_orb:
		_active_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_orb_rest_local_pos = _active_orb.position
		var construction_component: Node = _body.get_node_or_null("ConstructionComponent")
		if construction_component and construction_component.get("is_built") == false:
			_active_orb.visible = false
			_active_orb.scale = Vector3.ZERO


func _process(delta: float) -> void:
	super._process(delta)
	if not _body or not _body.has_method("is_built") or not _body.is_built():
		return
	var powered: bool = _body.has_operational_power() if _body.has_method("has_operational_power") else true
	set_powered_visual_state(powered)


func _play_construction_finish_animation() -> void:
	if _active_orb == null:
		return
	if _orb_intro_tween:
		_orb_intro_tween.kill()
		_orb_intro_tween = null
	var target_pos: Vector3 = _orb_rest_local_pos
	if _connection_point:
		target_pos = _connection_point.position
	_active_orb.visible = true
	_active_orb.position = target_pos
	_active_orb.scale = Vector3.ZERO
	var mat: StandardMaterial3D = _active_orb.get_active_material(0) as StandardMaterial3D
	if mat:
		mat.emission_energy_multiplier = 5.0
	_orb_intro_tween = create_tween()
	_orb_intro_tween.set_trans(Tween.TRANS_BACK)
	_orb_intro_tween.set_ease(Tween.EASE_OUT)
	_orb_intro_tween.tween_property(_active_orb, "scale", Vector3.ONE, 0.38)
	_orb_intro_tween.tween_callback(func() -> void:
		_orb_intro_tween = null
	)

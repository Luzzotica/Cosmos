extends "res://scripts/ecs/structure_behavior.gd"
class_name PowerNodeBehavior
## Structure behavior for Power Node - connection ring intro animation.

var _ring_intro_tween: Tween = null


func _get_active_connection_ring() -> MeshInstance3D:
	var entity: Node = _get_entity()
	if entity:
		return entity.get_node_or_null("ActiveConnectionRing") as MeshInstance3D
	return null


func _ready() -> void:
	super._ready()
	var ring: MeshInstance3D = _get_active_connection_ring()
	if ring:
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func apply_build_phase_ring_visibility() -> void:
	var ring: MeshInstance3D = _get_active_connection_ring()
	if ring == null:
		return
	var entity: Node = _get_entity()
	if entity and entity.has_method("is_built") and entity.is_built():
		return
	ring.visible = false
	ring.scale = Vector3.ZERO


func _play_construction_finish_animation() -> void:
	var ring: MeshInstance3D = _get_active_connection_ring()
	if ring == null:
		return
	if _ring_intro_tween:
		_ring_intro_tween.kill()
		_ring_intro_tween = null
	ring.visible = true
	ring.scale = Vector3.ZERO
	var mat: Material = ring.get_active_material(0)
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
	_ring_intro_tween.tween_property(ring, "scale", Vector3.ONE, 0.38)
	_ring_intro_tween.tween_callback(func() -> void:
		_ring_intro_tween = null
	)

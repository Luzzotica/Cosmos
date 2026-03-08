extends "res://scripts/ecs/structure_behavior.gd"
class_name SolarPanelBehavior
## Structure behavior for Solar Panel - panel float/rotate intro animation.

var _panel_intro_complete: bool = false
var _panel_intro_tween: Tween = null
var _panel_rest_y: float = 1.5


func _get_panel_mesh() -> MeshInstance3D:
	var entity: Node = _get_entity()
	if entity:
		return entity.get_node_or_null("Panel") as MeshInstance3D
	return null


func _play_construction_finish_animation() -> void:
	var panel_mesh: MeshInstance3D = _get_panel_mesh()
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
	_panel_intro_tween.tween_property(panel_mesh, "global_position", target_pos, 0.5)
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


func is_sun_tracking_active() -> bool:
	return _panel_intro_complete


func _get_panel_target_basis() -> Basis:
	var panel_mesh: MeshInstance3D = _get_panel_mesh()
	if panel_mesh == null:
		return Basis.IDENTITY
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

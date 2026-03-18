extends "res://scripts/structures/structure_visual_handler.gd"
class_name SolarPanelVisualHandler
## Solar Panel visuals: panel orientation toward sun, construction finish float-up animation.

@onready var _body: Node3D = get_parent() as Node3D
@onready var _panel_mesh: MeshInstance3D = _body.get_node_or_null("VisualRoot/Panel") as MeshInstance3D

## Optional override. If empty, uses GameWorld.sun_light (set by MainGame/MainMenuBackground).
@export var sun_light_path: NodePath = NodePath()

var _sun_light: DirectionalLight3D = null
var _panel_intro_complete: bool = false
var _panel_intro_tween: Tween = null
var _panel_rest_y: float = 1.5


func init(entity: Node) -> void:
	super.init(entity)
	_resolve_sun_light()


func _process(delta: float) -> void:
	super._process(delta)
	if not _body or not _body.has_method("is_built") or not _body.is_built():
		return
	set_powered_visual_state(true)
	if _panel_intro_complete:
		_orient_panel_toward_light()


func _resolve_sun_light() -> void:
	_sun_light = null
	if not sun_light_path.is_empty():
		_sun_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	if _sun_light == null and GameWorld:
		_sun_light = GameWorld.sun_light


func _orient_panel_toward_light() -> void:
	if _panel_mesh == null:
		return
	if _sun_light == null or not is_instance_valid(_sun_light):
		_resolve_sun_light()
		if _sun_light == null:
			return
	var toward_sun: Vector3 = _sun_light.global_basis.z.normalized()
	if toward_sun.length() <= 0.001:
		return
	var up: Vector3 = Vector3.UP
	if abs(toward_sun.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var basis_to_sun: Basis = Basis.looking_at(toward_sun, up)
	var panel_basis: Basis = basis_to_sun * Basis(Vector3.RIGHT, PI * 0.5)
	_panel_mesh.global_transform = Transform3D(panel_basis.orthonormalized(), _panel_mesh.global_position)


func _get_panel_target_basis() -> Basis:
	if _sun_light == null or not is_instance_valid(_sun_light):
		_resolve_sun_light()
		if _sun_light == null:
			return _panel_mesh.global_basis if _panel_mesh else Basis.IDENTITY
	var toward_sun: Vector3 = _sun_light.global_basis.z.normalized()
	if toward_sun.length() <= 0.001:
		return _panel_mesh.global_basis if _panel_mesh else Basis.IDENTITY
	var up: Vector3 = Vector3.UP
	if abs(toward_sun.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var basis_to_sun: Basis = Basis.looking_at(toward_sun, up)
	return (basis_to_sun * Basis(Vector3.RIGHT, PI * 0.5)).orthonormalized()


func _play_construction_finish_animation() -> void:
	if _panel_mesh == null:
		return
	if _panel_intro_tween:
		_panel_intro_tween.kill()
		_panel_intro_tween = null
	_panel_intro_complete = false
	var start_pos: Vector3 = _panel_mesh.global_position
	var start_basis: Basis = _panel_mesh.global_basis
	_panel_mesh.global_position = start_pos
	var target_pos: Vector3 = Vector3(_panel_mesh.global_position.x, _panel_rest_y, _panel_mesh.global_position.z)
	var target_basis: Basis = _get_panel_target_basis()
	_panel_intro_tween = create_tween()
	_panel_intro_tween.set_trans(Tween.TRANS_CUBIC)
	_panel_intro_tween.set_ease(Tween.EASE_OUT)
	_panel_intro_tween.tween_property(_panel_mesh, "global_position", target_pos, 0.5)
	_panel_intro_tween.tween_method(func(t: float) -> void:
		if _panel_mesh == null:
			return
		var blended_q: Quaternion = Quaternion(start_basis.orthonormalized()).slerp(Quaternion(target_basis.orthonormalized()), t)
		_panel_mesh.global_transform = Transform3D(Basis(blended_q).orthonormalized(), _panel_mesh.global_position)
	, 0.0, 1.0, 0.3)
	_panel_intro_tween.tween_callback(func() -> void:
		_panel_intro_complete = true
		_panel_intro_tween = null
	)

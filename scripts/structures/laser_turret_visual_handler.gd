extends "res://scripts/structures/structure_visual_handler.gd"
class_name LaserTurretVisualHandler
## Turret-specific visuals: orb flash, recoil on attack_fired; construction finish orb animation.

const C_BeamWeaponClass = preload("res://scripts/ecs/components/c_beam_weapon.gd")

@onready var _body: Node3D = get_parent() as Node3D
@onready var _active_orb: MeshInstance3D = _body.get_node_or_null("VisualRoot/ActiveOrb") as MeshInstance3D
@onready var _turret_base: MeshInstance3D = _body.get_node_or_null("VisualRoot/TurretBase") as MeshInstance3D
@onready var _power_node: PowerNode = _body.get_node_or_null("PowerNode") as PowerNode

const UNPOWERED_ORB_SCALE: float = 0.5

var _orb_rest_local_pos: Vector3 = Vector3.ZERO
var _orb_hidden_local_pos: Vector3 = Vector3.ZERO
var _orb_recoil_tween: Tween = null
var _orb_intro_tween: Tween = null
var _last_powered_state: bool = true


func _get_orb_scale_for_power_state(is_powered: bool) -> Vector3:
	return Vector3.ONE if is_powered else Vector3.ONE * UNPOWERED_ORB_SCALE


func set_powered_visual_state(is_powered: bool) -> void:
	_last_powered_state = is_powered
	if _active_orb:
		_active_orb.scale = _get_orb_scale_for_power_state(is_powered)
	# Keep orb glowing (STATE_ACTIVE); scale indicates power state
	super.set_powered_visual_state(true)


func _get_register_structure_props() -> Dictionary:
	return {"accent_no_shadow_mesh_names": ["ActiveOrb"]}


func init(entity: Node) -> void:
	super.init(entity)
	if _body:
		if _active_orb:
			_orb_rest_local_pos = _active_orb.position
			_orb_hidden_local_pos = (_turret_base.position + Vector3(0.0, 0.08, 0.0)) if _turret_base else _orb_rest_local_pos + Vector3(0.0, -0.4, 0.0)
			var construction_component: Node = _body.get_node_or_null("ConstructionComponent")
			if construction_component and construction_component.get("is_built") == false:
				_active_orb.visible = false
				_active_orb.position = _orb_hidden_local_pos
		if _body.has_method("has_operational_power"):
			_last_powered_state = _body.has_operational_power()
	var c_weapon = _get_component(C_BeamWeaponClass)
	if c_weapon and not c_weapon.attack_fired.is_connected(_on_attack_fired):
		c_weapon.attack_fired.connect(_on_attack_fired)
	if _power_node:
		for child in _power_node.get_children():
			if child is PowerUser and not (child as PowerUser).is_construction_user:
				if not (child as PowerUser).power_state_changed.is_connected(_on_power_state_changed):
					(child as PowerUser).power_state_changed.connect(_on_power_state_changed)
				break


func _on_power_state_changed(has_power: bool) -> void:
	_last_powered_state = has_power
	set_powered_visual_state(has_power)


func _on_attack_fired(from_pos: Vector3, target_pos: Vector3, _beam_color: Color) -> void:
	if _body == null or _active_orb == null:
		return
	_flash_active_orb(_active_orb, target_pos, _body)
	var render_manager: Node = get_tree().root.get_node_or_null("StructureRenderManager")
	if render_manager and render_manager.has_method("pulse_structure"):
		render_manager.call("pulse_structure", _body, 0.1)
	var sfx_manager: Node = get_tree().root.get_node_or_null("SfxManager")
	if sfx_manager and sfx_manager.has_method("play_sfx"):
		sfx_manager.call("play_sfx", "laser_shot", -6.0)
		sfx_manager.call("play_sfx", "laser_impact", -8.0)


func _flash_active_orb(active_orb: MeshInstance3D, target_pos: Vector3, body: Node3D) -> void:
	var mat: StandardMaterial3D = active_orb.get_active_material(0) as StandardMaterial3D
	if mat:
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 6.0
		var timer: SceneTreeTimer = get_tree().create_timer(0.08)
		timer.timeout.connect(func() -> void:
			if not is_instance_valid(active_orb):
				return
			var reset_mat: StandardMaterial3D = active_orb.get_active_material(0) as StandardMaterial3D
			if reset_mat:
				reset_mat.emission_energy_multiplier = 2.4
		)
	if _orb_recoil_tween:
		_orb_recoil_tween.kill()
		_orb_recoil_tween = null
		_ensure_orb_centered(active_orb)
	var fire_dir_world: Vector3 = (target_pos - active_orb.global_position).normalized()
	if fire_dir_world.length() > 0.001:
		var recoil_world: Vector3 = -fire_dir_world * 0.14
		var recoil_local: Vector3 = body.global_basis.inverse() * recoil_world
		var recoil_target: Vector3 = _orb_rest_local_pos + recoil_local
		_orb_recoil_tween = create_tween()
		_orb_recoil_tween.set_trans(Tween.TRANS_SINE)
		_orb_recoil_tween.set_ease(Tween.EASE_OUT)
		_orb_recoil_tween.tween_property(active_orb, "position", recoil_target, 0.055)
		_orb_recoil_tween.set_ease(Tween.EASE_IN)
		_orb_recoil_tween.tween_property(active_orb, "position", _orb_rest_local_pos, 0.11)
		_orb_recoil_tween.tween_callback(func() -> void:
			_orb_recoil_tween = null
		)


func _ensure_orb_centered(active_orb: MeshInstance3D) -> void:
	active_orb.position = _orb_rest_local_pos
	active_orb.scale = _get_orb_scale_for_power_state(_last_powered_state)


func _play_construction_finish_animation() -> void:
	super._play_construction_finish_animation()
	if _body == null or _active_orb == null:
		return
	if _orb_intro_tween:
		_orb_intro_tween.kill()
		_orb_intro_tween = null
	if _orb_recoil_tween:
		_orb_recoil_tween.kill()
		_orb_recoil_tween = null
	_ensure_orb_centered(_active_orb)
	_active_orb.visible = true
	_active_orb.position = _orb_hidden_local_pos
	_active_orb.scale = Vector3.ONE * 0.72
	var mat: StandardMaterial3D = _active_orb.get_active_material(0) as StandardMaterial3D
	if mat:
		mat.emission_energy_multiplier = 4.2
	_orb_intro_tween = create_tween()
	_orb_intro_tween.set_trans(Tween.TRANS_BACK)
	_orb_intro_tween.set_ease(Tween.EASE_OUT)
	_orb_intro_tween.tween_property(_active_orb, "position", _orb_rest_local_pos, 0.38)
	_orb_intro_tween.parallel().tween_property(_active_orb, "scale", _get_orb_scale_for_power_state(_last_powered_state), 0.38)
	_orb_intro_tween.tween_callback(func() -> void:
		_orb_intro_tween = null
		_ensure_orb_centered(_active_orb)
		if mat:
			mat.emission_energy_multiplier = 2.4
	)

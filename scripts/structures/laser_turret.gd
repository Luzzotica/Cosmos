extends BaseStructure
class_name LaserTurret
## Laser Turret - Defensive structure that attacks enemies. Targeting and combat logic handled by ECS systems.

signal target_acquired(target: Node3D)
signal target_lost
signal fired(target: Node3D, damage: float)
const LASER_DURATION: float = 0.12
const LASER_THICKNESS: float = 0.18

@export var attack_range: float = 35.0
@export var fire_rate: float = 1.0  # Shots per second
@export var damage: float = 10.0

@onready var turret_base: MeshInstance3D = $TurretBase
@onready var active_orb: MeshInstance3D = $ActiveOrb
var _last_powered_state: bool = true
var _orb_rest_local_pos: Vector3 = Vector3.ZERO
var _orb_hidden_local_pos: Vector3 = Vector3.ZERO
var _orb_intro_tween: Tween = null
var _orb_recoil_tween: Tween = null


func _ready() -> void:
	building_type = "laser_turret"
	_apply_balance_data()
	super._ready()
	if active_orb:
		active_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_orb_rest_local_pos = active_orb.position
		_orb_hidden_local_pos = turret_base.position + Vector3(0.0, 0.08, 0.0) if turret_base else _orb_rest_local_pos + Vector3(0.0, -0.4, 0.0)
		# Defer: _ecs_entity is set in _register_ecs_entity (deferred from super._ready)
		call_deferred("_apply_build_phase_orb_visibility")
	_last_powered_state = _get_has_power()
	if has_method("set_powered_visual_state"):
		call("set_powered_visual_state", _last_powered_state)


func _apply_build_phase_orb_visibility() -> void:
	if active_orb == null:
		return
	if not is_built():
		active_orb.visible = false
		active_orb.position = _orb_hidden_local_pos


func _apply_balance_data() -> void:
	var data: Resource = BuildManager.get_building_data(building_type)
	if data == null:
		return
	var configured_range: Variant = data.get("action_range")
	if configured_range != null:
		attack_range = maxf(float(configured_range), 0.0)
	var configured_damage: Variant = data.get("damage")
	if configured_damage != null:
		damage = maxf(float(configured_damage), 0.0)
	var configured_speed: Variant = data.get("attack_speed")
	if configured_speed != null and float(configured_speed) > 0.0:
		fire_rate = float(configured_speed)


func _get_has_power() -> bool:
	if _ecs_entity:
		var c_power_user: C_PowerUser = _ecs_entity.get_component(C_PowerUser) as C_PowerUser
		if c_power_user:
			return c_power_user.has_power()
	return false


func _get_structure_type_components(c_power_node: C_PowerNode, build_data: Resource) -> Array:
	c_power_node.node_type = C_PowerNode.NodeType.LEAF
	return []


func _get_extra_ecs_components() -> Array:
	var c_turret: C_TurretProfile = C_TurretProfile.new()
	c_turret.attack_range = attack_range
	c_turret.fire_rate = fire_rate
	c_turret.damage = damage
	c_turret.beam_color = Color(0.2, 0.9, 1.0, 0.95)
	var c_targeting: C_Targeting = C_Targeting.new()
	return [c_turret, c_targeting]


func _process(delta: float) -> void:
	super._process(delta)
	if not is_built():
		# Keep orb hidden during construction
		if active_orb and active_orb.visible:
			active_orb.visible = false
			active_orb.position = _orb_hidden_local_pos
		return

	var powered_now: bool = _get_has_power()
	if powered_now != _last_powered_state:
		_last_powered_state = powered_now
		if has_method("set_powered_visual_state"):
			call("set_powered_visual_state", powered_now)
		if not powered_now:
			_ensure_orb_centered()


## Called by LaserTurretAttackSystem when the turret fires. Handles visuals and SFX only.
func play_attack_visuals(target_pos: Vector3, beam_color: Color) -> void:
	_show_laser_beam(_get_muzzle_position(target_pos), target_pos, beam_color)
	_flash_active_orb(target_pos)
	_play_sfx("laser_shot", -6.0)
	_play_sfx("laser_impact", -8.0)
	var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
	if render_manager:
		render_manager.call("pulse_structure", self, 0.1)


func _get_muzzle_position(target_pos: Vector3) -> Vector3:
	if active_orb:
		var to_target: Vector3 = target_pos - active_orb.global_position
		if to_target.length() > 0.01:
			return active_orb.global_position + to_target.normalized() * 0.22
	return global_position + Vector3.UP * 0.8


func _show_laser_beam(from_pos: Vector3, to_pos: Vector3, color: Color) -> void:
	var distance: float = from_pos.distance_to(to_pos)
	if distance <= 0.05:
		return

	var beam: MeshInstance3D = MeshInstance3D.new()
	var beam_mesh: BoxMesh = BoxMesh.new()
	beam_mesh.size = Vector3(LASER_THICKNESS, LASER_THICKNESS, distance)
	beam.mesh = beam_mesh

	var beam_material: StandardMaterial3D = StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.albedo_color = color
	beam_material.emission_enabled = true
	beam_material.emission = color
	beam_material.emission_energy_multiplier = 2.0
	beam_material.no_depth_test = true
	beam.material_override = beam_material

	get_tree().root.add_child(beam)
	beam.global_position = (from_pos + to_pos) * 0.5
	beam.look_at(to_pos, Vector3.UP)

	var cleanup_timer: SceneTreeTimer = get_tree().create_timer(LASER_DURATION)
	cleanup_timer.timeout.connect(func() -> void:
		if is_instance_valid(beam):
			beam.queue_free()
	)


## Get current target from ECS component (for UI/selection).
func get_target() -> Node3D:
	if _ecs_entity == null:
		return null
	var c_targeting: C_Targeting = _ecs_entity.get_component(C_Targeting) as C_Targeting
	return c_targeting.target_node if c_targeting else null


## Check if turret is active and powered
func is_active() -> bool:
	return is_built() and _get_has_power()


func _set_orb_emission_strength(strength: float) -> void:
	if active_orb == null:
		return
	var mat: Material = active_orb.get_active_material(0)
	var shader_mat: ShaderMaterial = mat as ShaderMaterial
	if shader_mat != null:
		shader_mat.set_shader_parameter("emission_strength", strength)
	else:
		var std_mat: StandardMaterial3D = mat as StandardMaterial3D
		if std_mat:
			std_mat.emission_enabled = strength > 0.0
			std_mat.emission_energy_multiplier = strength


func _flash_active_orb(target_pos: Vector3) -> void:
	if active_orb:
		var mat: Material = active_orb.get_active_material(0)
		if mat:
			_set_orb_emission_strength(6.0)
			var timer: SceneTreeTimer = get_tree().create_timer(0.08)
			timer.timeout.connect(func() -> void:
				if not is_instance_valid(active_orb):
					return
				_set_orb_emission_strength(2.4 if _last_powered_state else 0.0)
			)

		# Small recoil: orb moves away from firing direction, then settles.
		if _orb_recoil_tween:
			_orb_recoil_tween.kill()
			_orb_recoil_tween = null
			_ensure_orb_centered()
		var fire_dir_world: Vector3 = (target_pos - active_orb.global_position).normalized()
		if fire_dir_world.length() > 0.001:
			var recoil_world: Vector3 = -fire_dir_world * 0.14
			var recoil_local: Vector3 = global_basis.inverse() * recoil_world
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


func _play_sfx(sfx_id: String, volume_db: float = -6.0) -> void:
	var sfx_manager: Node = get_node_or_null("/root/SfxManager")
	if sfx_manager and sfx_manager.has_method("play_sfx"):
		sfx_manager.call("play_sfx", sfx_id, volume_db)


func _play_construction_finish_animation() -> void:
	if active_orb == null:
		return
	if _orb_intro_tween:
		_orb_intro_tween.kill()
		_orb_intro_tween = null
	if _orb_recoil_tween:
		_orb_recoil_tween.kill()
		_orb_recoil_tween = null
	_ensure_orb_centered()

	active_orb.visible = true
	active_orb.position = _orb_hidden_local_pos
	active_orb.scale = Vector3.ONE * 0.72
	_set_orb_emission_strength(4.2)

	_orb_intro_tween = create_tween()
	_orb_intro_tween.set_trans(Tween.TRANS_BACK)
	_orb_intro_tween.set_ease(Tween.EASE_OUT)
	_orb_intro_tween.tween_property(active_orb, "position", _orb_rest_local_pos, 0.38)
	_orb_intro_tween.parallel().tween_property(active_orb, "scale", Vector3.ONE, 0.38)
	_orb_intro_tween.tween_callback(func() -> void:
		_orb_intro_tween = null
		_ensure_orb_centered()
		_set_orb_emission_strength(2.4 if _last_powered_state else 0.0)
	)


func _ensure_orb_centered() -> void:
	if active_orb == null:
		return
	active_orb.position = _orb_rest_local_pos
	active_orb.scale = Vector3.ONE

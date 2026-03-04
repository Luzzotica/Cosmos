extends BaseStructure
class_name LaserTurret
## Laser Turret - Defensive structure that attacks enemies

signal target_acquired(target: Node3D)
signal target_lost
signal fired(target: Node3D, damage: float)
const LASER_DURATION: float = 0.12
const LASER_THICKNESS: float = 0.18

@export var attack_range: float = 35.0
@export var fire_rate: float = 1.0  # Shots per second
@export var damage: float = 10.0

var power_user: PowerUser
var target: Node3D = null
var fire_timer: float = 0.0

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
		if not is_built():
			active_orb.visible = false
			active_orb.position = _orb_hidden_local_pos
	_setup_power_user()


func _apply_balance_data() -> void:
	var data: Resource = BuildManager.get_building_data(building_type)
	if data == null:
		return
	var configured_range: Variant = data.get("action_range")
	if configured_range != null:
		attack_range = maxf(float(configured_range), 0.0)


func _setup_power_user() -> void:
	power_user = null
	if power_node:
		for child in power_node.get_children():
			if child is PowerUser and not child.is_construction_user:
				power_user = child
				if not power_user.power_state_changed.is_connected(_on_power_state_changed):
					power_user.power_state_changed.connect(_on_power_state_changed)
				break
	_last_powered_state = power_user != null and power_user.has_power
	if has_method("set_powered_visual_state"):
		call("set_powered_visual_state", _last_powered_state)


func _process(delta: float) -> void:
	super._process(delta)
	if not is_built():
		return
	
	# Update fire timer
	fire_timer -= delta
	
	# Construction cleanup may change user validity; re-resolve lazily.
	if not is_instance_valid(power_user):
		_setup_power_user()
	
	if power_user and not power_user.has_power:
		power_user.draw_power_from_graph()
	var powered_now: bool = power_user != null and power_user.has_power
	if powered_now != _last_powered_state:
		_last_powered_state = powered_now
		if has_method("set_powered_visual_state"):
			call("set_powered_visual_state", powered_now)
	
	# Only operate if powered
	if powered_now:
		_find_target()
		_try_attack()
	else:
		target = null
		_ensure_orb_centered()


func _find_target() -> void:
	# Clear target if destroyed or out of range
	if target != null:
		if not is_instance_valid(target):
			target = null
			target_lost.emit()
		elif _is_target_destroyed(target):
			target = null
			target_lost.emit()
		elif global_position.distance_to(target.global_position) > attack_range:
			target = null
			target_lost.emit()
	
	# Find new target if needed
	if target == null:
		target = _find_closest_enemy()
		if target:
			target_acquired.emit(target)


func _find_closest_enemy() -> Node3D:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if not main:
		return null
	
	var enemies_parent: Node = main.get_node_or_null("Enemies")
	if not enemies_parent:
		return null
	
	var closest_distance: float = INF
	var closest_enemy: Node3D = null
	
	for child in enemies_parent.get_children():
		if _is_target_destroyed(child):
			continue
		
		var distance: float = global_position.distance_to(child.global_position)
		if distance <= attack_range and distance < closest_distance:
			closest_distance = distance
			closest_enemy = child
	
	return closest_enemy


func _is_target_destroyed(t: Node3D) -> bool:
	if t.has_method("is_destroyed"):
		return t.is_destroyed
	if t.get("is_destroyed") != null:
		return t.is_destroyed
	return false


func _try_attack() -> void:
	if fire_timer > 0 or target == null:
		return
	
	if not power_user or not power_user.consume_power():
		return
	
	# Fire!
	fire_timer = 1.0 / fire_rate
	var target_pos: Vector3 = target.global_position + Vector3.UP * 0.8
	_show_laser_beam(_get_muzzle_position(target_pos), target_pos, Color(0.2, 0.9, 1.0, 0.95))
	_flash_active_orb(target_pos)
	_play_sfx("laser_shot", -6.0)
	
	# Deal damage to target
	if target.has_method("take_damage_event"):
		target.take_damage_event({
			"amount": damage,
			"damage_type": "laser",
			"source": self,
			"tags": PackedStringArray()
		})
	elif target.has_method("take_damage"):
		target.take_damage(damage)
	_play_sfx("laser_impact", -8.0)
	
	fired.emit(target, damage)


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


## Get current target
func get_target() -> Node3D:
	return target


## Check if turret is active and powered
func is_active() -> bool:
	return is_built() and power_user and power_user.has_power


func _on_power_state_changed(has_power: bool) -> void:
	_last_powered_state = has_power
	if has_method("set_powered_visual_state"):
		call("set_powered_visual_state", has_power)


func _flash_active_orb(target_pos: Vector3) -> void:
	if active_orb:
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
					reset_mat.emission_energy_multiplier = 2.4 if _last_powered_state else 0.0
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
	
	var render_manager: Node = get_node_or_null("/root/StructureRenderManager")
	if render_manager:
		render_manager.call("pulse_structure", self, 0.1)


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
	var mat: StandardMaterial3D = active_orb.get_active_material(0) as StandardMaterial3D
	if mat:
		mat.emission_energy_multiplier = 4.2
	
	_orb_intro_tween = create_tween()
	_orb_intro_tween.set_trans(Tween.TRANS_BACK)
	_orb_intro_tween.set_ease(Tween.EASE_OUT)
	_orb_intro_tween.tween_property(active_orb, "position", _orb_rest_local_pos, 0.38)
	_orb_intro_tween.parallel().tween_property(active_orb, "scale", Vector3.ONE, 0.38)
	_orb_intro_tween.tween_callback(func() -> void:
		_orb_intro_tween = null
		_ensure_orb_centered()
		if mat:
			mat.emission_energy_multiplier = 2.4 if _last_powered_state else 0.0
	)


func _ensure_orb_centered() -> void:
	if active_orb == null:
		return
	active_orb.position = _orb_rest_local_pos
	active_orb.scale = Vector3.ONE

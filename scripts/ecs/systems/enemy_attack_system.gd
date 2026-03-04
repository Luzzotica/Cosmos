extends System
class_name EnemyAttackSystem
## Batch attack: cooldown, range check, damage application, beam visual.

const LASER_DURATION: float = 0.08
const LASER_THICKNESS: float = 0.12


func query() -> QueryBuilder:
	return q.with_all([C_EnemyState, C_Targeting, C_PhysicsBodyRef, C_AttackProfile])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity_attack(entity, delta)


func _process_entity_attack(entity: Entity, delta: float) -> void:
	var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var c_attack: C_AttackProfile = entity.get_component(C_AttackProfile) as C_AttackProfile
	if c_state.is_destroyed or c_body_ref == null or c_body_ref.body == null:
		return
	c_attack.cooldown_remaining = maxf(c_attack.cooldown_remaining - delta, 0.0)
	var target: Node3D = c_targeting.target_node if c_targeting else null
	if target == null or not is_instance_valid(target):
		return
	var body: CharacterBody3D = c_body_ref.body
	var tactical: Dictionary = _get_tactical_modifier(entity)
	var attack_range: float = c_state.attack_range * float(tactical.get("attack_range_multiplier", 1.0))
	if body.global_position.distance_to(target.global_position) > attack_range:
		return
	if c_attack.cooldown_remaining > 0.0:
		return
	var cooldown: float = c_state.attack_cooldown * float(tactical.get("attack_cooldown_multiplier", 1.0))
	c_attack.cooldown_remaining = maxf(cooldown, 0.1)
	var from_pos: Vector3 = body.global_position + Vector3.UP * 0.6
	var target_pos: Vector3 = target.global_position + Vector3.UP * 0.8
	_spawn_beam(from_pos, target_pos, c_attack.beam_color)
	var damage: float = c_state.damage * float(tactical.get("damage_multiplier", 1.0))
	var packet: Dictionary = {
		"amount": damage,
		"damage_type": c_attack.damage_type,
		"source": body,
		"tags": PackedStringArray()
	}
	if target.has_method("take_damage_event"):
		target.take_damage_event(packet)
	elif target.has_method("take_damage"):
		target.take_damage(float(packet.amount))


func _spawn_beam(from_pos: Vector3, target_pos: Vector3, color: Color) -> void:
	var distance: float = from_pos.distance_to(target_pos)
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
	var root: Node = Engine.get_main_loop().root
	root.add_child(beam)
	beam.global_position = (from_pos + target_pos) * 0.5
	beam.look_at(target_pos, Vector3.UP)
	var timer: SceneTreeTimer = root.get_tree().create_timer(LASER_DURATION)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(beam):
			beam.queue_free()
	)


func _get_tactical_modifier(entity: Entity) -> Dictionary:
	var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
	if enemy_manager == null or not enemy_manager.has_method("get_tactical_modifier_for_enemy"):
		return {}
	var body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var node_for_lookup: Node = body_ref.body if body_ref and body_ref.body else entity
	return enemy_manager.get_tactical_modifier_for_enemy(node_for_lookup)

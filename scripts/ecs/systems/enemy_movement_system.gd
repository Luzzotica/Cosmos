extends System
class_name EnemyMovementSystem
## Batch movement: computes velocity from movement behavior and applies to physics body.

const MovementBehaviorClass: Script = preload("res://scripts/enemies/behaviors/movement_behavior.gd")


func query() -> QueryBuilder:
	return q.with_all([C_EnemyState, C_Targeting, C_Transform3D, C_PhysicsBodyRef, C_MovementProfile])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity_movement(entity, delta)


func _process_entity_movement(entity: Entity, delta: float) -> void:
	var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_transform: C_Transform3D = entity.get_component(C_Transform3D) as C_Transform3D
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var c_movement: C_MovementProfile = entity.get_component(C_MovementProfile) as C_MovementProfile
	if c_state.is_destroyed or c_body_ref == null or c_body_ref.body == null:
		return
	var body: CharacterBody3D = c_body_ref.body
	# Sync state to body so movement behavior can read speed/attack_range via get()
	body.set_meta("speed", c_state.speed)
	body.set_meta("attack_range", c_state.attack_range)
	var movement_behavior: RefCounted = _get_or_create_movement_behavior(entity, c_movement)
	if movement_behavior == null:
		return
	var target: Node3D = null
	if c_targeting and c_targeting.target_node != null:
		var raw: Variant = c_targeting.target_node
		if raw != null and is_instance_valid(raw):
			target = raw as Node3D
		else:
			c_targeting.target_node = null
	var fallback: Vector3 = c_targeting.fallback_position if c_targeting else body.global_position + Vector3.FORWARD * 8.0
	var tactical: Dictionary = _get_tactical_modifier(entity)
	var velocity_result: Vector3 = movement_behavior.step(delta, body, target, fallback, tactical)
	body.velocity = velocity_result
	body.move_and_slide()
	# Sync transform back to component
	c_transform.position = body.global_position
	c_transform.rotation = body.rotation
	# Update facing
	var planar: Vector3 = Vector3(body.velocity.x, 0.0, body.velocity.z)
	if planar.length() >= 0.1:
		var look_dir: Vector3 = planar.normalized()
		var target_rot: float = atan2(look_dir.x, look_dir.z)
		body.rotation.y = lerp_angle(body.rotation.y, target_rot, delta * 4.0)
		c_targeting.forward_direction = look_dir


var _entity_behaviors: Dictionary = {}  # entity id -> MovementBehavior


func _get_or_create_movement_behavior(entity: Entity, c_movement: C_MovementProfile) -> RefCounted:
	var id_key = entity.get_instance_id()
	if _entity_behaviors.has(id_key):
		return _entity_behaviors[id_key]
	var behavior: RefCounted = MovementBehaviorClass.new()
	var body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	if body_ref and body_ref.body:
		behavior.set_initial_forward(-body_ref.body.global_basis.z)
	if c_movement and not c_movement.profile.is_empty():
		behavior.configure(c_movement.profile)
	_entity_behaviors[id_key] = behavior
	return behavior


func _get_tactical_modifier(entity: Entity) -> Dictionary:
	var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
	if enemy_manager == null or not enemy_manager.has_method("get_tactical_modifier_for_enemy"):
		return {}
	var body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var node_for_lookup: Node = body_ref.body if body_ref and body_ref.body else entity
	return enemy_manager.get_tactical_modifier_for_enemy(node_for_lookup)

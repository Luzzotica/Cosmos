extends System
class_name EnemyMovementFlybySystem
## Flyby movement: constant speed, approach, shoot while flying past, loop back.

const _C_MovementSteering: Script = preload("res://scripts/ecs/components/c_movement_steering.gd")
const _C_MovementState: Script = preload("res://scripts/ecs/components/c_movement_state.gd")
const _C_MovementFlyby: Script = preload("res://scripts/ecs/components/c_movement_flyby.gd")
const SteeringUtils: Script = preload("res://scripts/enemies/movement_steering_utils.gd")


func query() -> QueryBuilder:
	return q.with_all([C_EnemyState, C_Targeting, C_Transform3D, C_PhysicsBodyRef, _C_MovementSteering, _C_MovementState, _C_MovementFlyby])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity(entity, delta)


func _process_entity(entity: Entity, delta: float) -> void:
	var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_transform: C_Transform3D = entity.get_component(C_Transform3D) as C_Transform3D
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var c_steering = entity.get_component(_C_MovementSteering)
	var c_state_mov = entity.get_component(_C_MovementState)
	var c_flyby = entity.get_component(_C_MovementFlyby)
	if c_state.is_destroyed or c_body_ref == null or c_body_ref.body == null:
		return

	var body: CharacterBody3D = c_body_ref.body
	var target: Node3D = _get_target(c_targeting)
	var fallback: Vector3 = c_targeting.fallback_position if c_targeting else body.global_position + Vector3.FORWARD * 8.0
	var tactical: Dictionary = _get_tactical_modifier(entity)

	var desired_dir: Vector3 = _compute_desired_direction(body, c_state_mov, c_state, target, fallback)
	var avoidance: Vector3 = SteeringUtils.compute_obstacle_avoidance(body, c_steering, c_state_mov.forward_dir)
	var separation: Vector3 = SteeringUtils.compute_separation(body, c_steering)
	var blended: Vector3 = (desired_dir + avoidance + separation).normalized()
	if blended.length() < 0.01:
		blended = c_state_mov.forward_dir
	c_state_mov.forward_dir = SteeringUtils.rotate_dir_toward(c_state_mov.forward_dir, blended, deg_to_rad(c_steering.max_turn_rate_deg) * delta)

	var speed_target: float = c_state.speed * float(tactical.get("speed_multiplier", 1.0))
	var speed: float = maxf(speed_target, c_flyby.min_speed)
	body.velocity = c_state_mov.forward_dir * speed
	body.move_and_slide()

	_finish_movement(entity, body, c_transform, c_targeting, delta)


func _compute_desired_direction(body: CharacterBody3D, c_state_mov, c_state: C_EnemyState, target: Node3D, fallback: Vector3) -> Vector3:
	if target == null:
		return SteeringUtils.flat_dir_to(body.global_position, fallback)

	var to_target: Vector3 = target.global_position - body.global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance < 0.01:
		return c_state_mov.forward_dir

	if distance > c_state.attack_range:
		return to_target.normalized()

	var to_norm: Vector3 = to_target.normalized()
	var tangent_left: Vector3 = Vector3(-to_norm.z, 0.0, to_norm.x)
	var tangent_right: Vector3 = Vector3(to_norm.z, 0.0, -to_norm.x)
	var dot_left: float = tangent_left.dot(c_state_mov.forward_dir)
	var dot_right: float = tangent_right.dot(c_state_mov.forward_dir)
	var tangent: Vector3 = tangent_left if dot_left >= dot_right else tangent_right
	return tangent.normalized()


func _get_target(c_targeting: C_Targeting) -> Node3D:
	if c_targeting == null or c_targeting.target_node == null:
		return null
	var raw: Variant = c_targeting.target_node
	if raw != null and is_instance_valid(raw):
		return raw as Node3D
	c_targeting.target_node = null
	return null


func _get_tactical_modifier(entity: Entity) -> Dictionary:
	var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
	if enemy_manager == null or not enemy_manager.has_method("get_tactical_modifier_for_enemy"):
		return {}
	var body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var node_for_lookup: Node = body_ref.body if body_ref and body_ref.body else entity
	return enemy_manager.get_tactical_modifier_for_enemy(node_for_lookup)


func _finish_movement(entity: Entity, body: CharacterBody3D, c_transform: C_Transform3D, c_targeting: C_Targeting, delta: float) -> void:
	c_transform.position = body.global_position
	c_transform.rotation = body.rotation
	var planar: Vector3 = Vector3(body.velocity.x, 0.0, body.velocity.z)
	if planar.length() >= 0.1:
		var look_dir: Vector3 = planar.normalized()
		body.rotation.y = lerp_angle(body.rotation.y, atan2(look_dir.x, look_dir.z), delta * 4.0)
		c_targeting.forward_direction = look_dir

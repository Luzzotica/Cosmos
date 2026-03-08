extends System
class_name EnemyMovementSwarmSystem
## Swarm movement: dive in, orbit at range, circle out, repeat.

const _C_MovementSteering: Script = preload("res://scripts/ecs/components/c_movement_steering.gd")
const _C_MovementState: Script = preload("res://scripts/ecs/components/c_movement_state.gd")
const _C_MovementSwarm: Script = preload("res://scripts/ecs/components/c_movement_swarm.gd")
const SteeringUtils: Script = preload("res://scripts/enemies/movement_steering_utils.gd")

const PHASE_DIVE_IN: int = 0
const PHASE_ORBIT: int = 1
const PHASE_CIRCLE_OUT: int = 2


func query() -> QueryBuilder:
	return q.with_all([C_EnemyState, C_Targeting, C_Transform3D, C_PhysicsBodyRef, _C_MovementSteering, _C_MovementState, _C_MovementSwarm])


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
	var c_swarm = entity.get_component(_C_MovementSwarm)
	if c_state.is_destroyed or c_body_ref == null or c_body_ref.body == null:
		return

	var body: CharacterBody3D = c_body_ref.body
	var target: Node3D = _get_target(c_targeting)
	var fallback: Vector3 = c_targeting.fallback_position if c_targeting else body.global_position + Vector3.FORWARD * 8.0
	var tactical: Dictionary = _get_tactical_modifier(entity)

	var desired_dir: Vector3 = _compute_desired_direction(body, c_state_mov, c_state, c_swarm, target, fallback, delta)
	var avoidance: Vector3 = SteeringUtils.compute_obstacle_avoidance(body, c_steering, c_state_mov.forward_dir)
	var separation: Vector3 = SteeringUtils.compute_separation(body, c_steering)
	var blended: Vector3 = (desired_dir + avoidance + separation).normalized()
	if blended.length() < 0.01:
		blended = c_state_mov.forward_dir
	c_state_mov.forward_dir = SteeringUtils.rotate_dir_toward(c_state_mov.forward_dir, blended, deg_to_rad(c_steering.max_turn_rate_deg) * delta)

	var speed_target: float = c_state.speed * float(tactical.get("speed_multiplier", 1.0))
	if target != null:
		var dist: float = body.global_position.distance_to(target.global_position)
		if dist <= c_state.attack_range:
			if c_swarm.swarm_phase == PHASE_CIRCLE_OUT:
				speed_target *= c_swarm.swarm_circle_out_speed_mult
			else:
				speed_target *= 0.85
	c_swarm.current_speed = move_toward(c_swarm.current_speed, speed_target, c_swarm.max_acceleration * delta)
	c_swarm.current_speed = maxf(c_swarm.current_speed - c_swarm.drag * delta, 0.0)

	body.velocity = c_state_mov.forward_dir * c_swarm.current_speed
	body.move_and_slide()

	_finish_movement(entity, body, c_transform, c_targeting, delta)


func _compute_desired_direction(body: CharacterBody3D, c_state_mov, c_state: C_EnemyState, c_swarm, target: Node3D, fallback: Vector3, delta: float) -> Vector3:
	if target == null:
		c_swarm.swarm_phase = PHASE_DIVE_IN
		c_swarm.swarm_timer = 0.0
		return SteeringUtils.flat_dir_to(body.global_position, fallback)

	var to_target: Vector3 = target.global_position - body.global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance < 0.01:
		return c_state_mov.forward_dir

	if not c_swarm.swarm_enabled:
		if distance > c_state.attack_range:
			c_swarm.orbit_direction = 0
			return to_target.normalized()
		return _orbit_internal(body, c_swarm, to_target, distance)

	c_swarm.swarm_timer -= delta
	if distance > c_state.attack_range:
		c_swarm.swarm_phase = PHASE_DIVE_IN
		c_swarm.swarm_timer = 0.0
		c_swarm.orbit_direction = 0
		return to_target.normalized()

	match c_swarm.swarm_phase:
		PHASE_DIVE_IN:
			c_swarm.swarm_phase = PHASE_ORBIT
			c_swarm.swarm_timer = c_swarm.swarm_orbit_duration
			if c_swarm.orbit_direction == 0:
				var cross: float = body.velocity.x * to_target.z - body.velocity.z * to_target.x
				c_swarm.orbit_direction = 1 if cross >= 0.0 else -1
			return _orbit_internal(body, c_swarm, to_target, distance)
		PHASE_ORBIT:
			if c_swarm.swarm_timer <= 0.0:
				c_swarm.swarm_phase = PHASE_CIRCLE_OUT
				c_swarm.swarm_timer = c_swarm.swarm_circle_out_duration
			return _orbit_internal(body, c_swarm, to_target, distance)
		PHASE_CIRCLE_OUT:
			if c_swarm.swarm_timer <= 0.0:
				c_swarm.swarm_phase = PHASE_DIVE_IN
				c_swarm.swarm_timer = 0.0
			return (-to_target).normalized()
	return to_target.normalized()


func _orbit_internal(body: CharacterBody3D, c_swarm, to_target: Vector3, distance: float) -> Vector3:
	if c_swarm.orbit_direction == 0:
		var cross: float = body.velocity.x * to_target.z - body.velocity.z * to_target.x
		c_swarm.orbit_direction = 1 if cross >= 0.0 else -1
	var tangent: Vector3 = Vector3(-to_target.z, 0.0, to_target.x).normalized() * c_swarm.orbit_direction
	var radius_error: float = distance - c_swarm.orbit_distance
	var radial_fix: Vector3 = Vector3.ZERO
	if abs(radius_error) > c_swarm.orbit_error_radius:
		radial_fix = to_target.normalized() * clampf(radius_error * 0.45, -1.0, 1.0)
	return (tangent + radial_fix).normalized()


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

extends System
class_name RepairRobotMovementSystem
## Fighter-style movement for repair robots when state is HEALING or FLY_TO_STATION.

const ObstacleDebugStoreClass = preload("res://scripts/debug/obstacle_debug_store.gd")


func query() -> QueryBuilder:
	return q.with_all([C_RepairRobotState, C_RepairRobotMovement, C_Targeting, C_Transform3D, C_PhysicsBodyRef])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity_movement(entity, delta)


func _process_entity_movement(entity: Entity, delta: float) -> void:
	var c_state: C_RepairRobotState = entity.get_component(C_RepairRobotState) as C_RepairRobotState
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_transform: C_Transform3D = entity.get_component(C_Transform3D) as C_Transform3D
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var c_movement: C_RepairRobotMovement = entity.get_component(C_RepairRobotMovement) as C_RepairRobotMovement
	if c_state == null or c_body_ref == null or c_body_ref.body == null or c_movement == null:
		return
	if c_state.state == C_RepairRobotState.State.DOCKED_RECHARGING:
		return
	var body: CharacterBody3D = c_body_ref.body

	var current_forward: Vector3 = _forward_from_rotation_y(c_transform.rotation.y)
	if current_forward.length() < 0.01:
		current_forward = c_targeting.forward_direction if c_targeting else Vector3.FORWARD
	current_forward = current_forward.normalized()

	var exclude_rids: Array[RID] = []
	if c_state.state == C_RepairRobotState.State.FLY_TO_STATION:
		exclude_rids = _get_station_exclude_rids(c_state)

	var overlay = Engine.get_main_loop().root.get_node_or_null("Main/EnemyTargetDebugOverlay")
	var want_debug: bool = overlay != null and overlay.get("obstacle_debug_enabled") == true
	var avoidance_result = ObstacleAvoidance.compute(
		body, current_forward, c_movement.avoid_radius,
		c_movement.ship_radius, c_movement.obstacle_radius, c_movement.steer_force,
		want_debug, exclude_rids
	)
	var avoidance_force: Vector3 = avoidance_result.get("force", Vector3.ZERO)
	var closest_obstacle_dist: float = avoidance_result.get("closest_dist", INF)
	var desired_dir: Vector3
	if avoidance_force.length() > 0.01:
		desired_dir = avoidance_force.normalized()
	else:
		desired_dir = _compute_desired_direction(body, c_targeting, c_movement)
		if desired_dir.length() < 0.01:
			desired_dir = current_forward

	if want_debug and avoidance_result.has("debug_sphere_center"):
		ObstacleDebugStoreClass.push(
			body.global_position,
			avoidance_result.debug_sphere_center,
			avoidance_result.debug_sphere_radius,
			desired_dir,
			current_forward
		)

	var max_turn: float = deg_to_rad(c_movement.turn_rate_deg * 0.5) * delta
	var new_forward: Vector3 = _rotate_toward(current_forward, desired_dir, max_turn)

	var new_rotation_y: float = atan2(new_forward.x, new_forward.z)
	c_transform.rotation.y = new_rotation_y
	if c_targeting:
		c_targeting.forward_direction = new_forward

	body.global_position = c_transform.position
	body.rotation = Vector3(0.0, c_transform.rotation.y, 0.0)

	var dock_target: Vector3 = Vector3.INF
	var dock_dist: float = INF
	if c_state.state == C_RepairRobotState.State.FLY_TO_STATION and c_targeting and c_targeting.target_position != Vector3.INF:
		dock_target = c_targeting.target_position
		var to_dock: Vector3 = dock_target - body.global_position
		to_dock.y = 0.0
		dock_dist = to_dock.length()

	if dock_dist < c_state.arrival_range:
		var lerp_t: float = min(1.0, delta / maxf(c_state.arrival_lerp_duration, 0.001))
		var new_pos: Vector3 = body.global_position.lerp(dock_target, lerp_t)
		body.global_position = new_pos
		body.velocity = Vector3.ZERO
		c_transform.position = body.global_position
		return

	var speed_mult: float = 1.0
	if closest_obstacle_dist < c_movement.obstacle_slow_dist:
		var t: float = clampf(closest_obstacle_dist / c_movement.obstacle_slow_dist, 0.0, 1.0)
		speed_mult = lerpf(c_movement.min_speed_near_obstacle, 1.0, t)

	if dock_dist < 4.0:
		speed_mult *= clampf(dock_dist / 4.0, 0.05, 1.0)

	var speed: float = c_movement.speed * speed_mult
	var prev_y: float = body.global_position.y
	body.velocity = new_forward * speed
	body.move_and_slide()
	body.global_position.y = prev_y

	c_transform.position = body.global_position


func _get_station_exclude_rids(c_state: C_RepairRobotState) -> Array[RID]:
	if c_state.source_station == null or not is_instance_valid(c_state.source_station):
		return []
	var obstacle_body: Node = (c_state.source_station as Node).get_node_or_null("ObstacleBody")
	if obstacle_body is PhysicsBody3D:
		return [(obstacle_body as PhysicsBody3D).get_rid()]
	return []


func _forward_from_rotation_y(rotation_y: float) -> Vector3:
	return Vector3(sin(rotation_y), 0.0, cos(rotation_y)).normalized()


func _compute_desired_direction(body: CharacterBody3D, c_targeting: C_Targeting, c_movement: C_RepairRobotMovement) -> Vector3:
	var target_pos: Vector3
	if c_targeting and c_targeting.target_node != null and is_instance_valid(c_targeting.target_node):
		target_pos = (c_targeting.target_node as Node3D).global_position
		var ship_pos: Vector3 = body.global_position
		var to_struct: Vector3 = target_pos - ship_pos
		to_struct.y = 0.0
		if to_struct.length() > 0.01 and c_movement.target_offset_length > 0.01:
			var perp: Vector3 = Vector3(-to_struct.z, 0.0, to_struct.x).normalized()
			perp *= signf(c_movement.target_offset_side) if c_movement.target_offset_side != 0.0 else 1.0
			target_pos += perp * c_movement.target_offset_length
	elif c_targeting and c_targeting.target_position != Vector3.INF:
		target_pos = c_targeting.target_position
	else:
		target_pos = body.global_position + Vector3.FORWARD * 8.0
	var to_target: Vector3 = target_pos - body.global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return Vector3.ZERO
	return to_target.normalized()


func _rotate_toward(from_dir: Vector3, to_dir: Vector3, max_radians: float) -> Vector3:
	var a: Vector2 = Vector2(from_dir.x, from_dir.z).normalized()
	var b: Vector2 = Vector2(to_dir.x, to_dir.z).normalized()
	if a.length() < 0.01:
		return to_dir
	if b.length() < 0.01:
		return from_dir
	var from_angle: float = atan2(a.x, a.y)
	var to_angle: float = atan2(b.x, b.y)
	var next_angle: float = rotate_toward(from_angle, to_angle, max_radians)
	return Vector3(sin(next_angle), 0.0, cos(next_angle)).normalized()

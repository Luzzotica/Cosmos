extends System
class_name EnemyMovementSystem
## Fighter movement: constant speed, local-space obstacle avoidance, turn-rate-limited steering.
const ObstacleDebugStoreClass = preload("res://scripts/debug/obstacle_debug_store.gd")
## Does not handle collision damage (see CollisionDamageSystem).


func query() -> QueryBuilder:
	return q.with_all([C_EnemyState, C_Targeting, C_Transform3D, C_PhysicsBodyRef, C_FighterMovement])


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	for entity in entities:
		_process_entity_movement(entity, delta)


func _process_entity_movement(entity: Entity, delta: float) -> void:
	var c_state: C_EnemyState = entity.get_component(C_EnemyState) as C_EnemyState
	var c_targeting: C_Targeting = entity.get_component(C_Targeting) as C_Targeting
	var c_transform: C_Transform3D = entity.get_component(C_Transform3D) as C_Transform3D
	var c_body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var c_fighter: C_FighterMovement = entity.get_component(C_FighterMovement) as C_FighterMovement
	if c_state.is_destroyed or c_body_ref == null or c_body_ref.body == null or c_fighter == null:
		return
	var body: CharacterBody3D = c_body_ref.body

	# Current forward from C_Transform (source of truth for rotation)
	var current_forward: Vector3 = _forward_from_rotation_y(c_transform.rotation.y)
	if current_forward.length() < 0.01:
		current_forward = c_targeting.forward_direction if c_targeting else Vector3.FORWARD
	current_forward = current_forward.normalized()

	# Obstacle avoidance (local-space, takes priority)
	var overlay = Engine.get_main_loop().root.get_node_or_null("Main/EnemyTargetDebugOverlay")
	var want_debug: bool = overlay != null and overlay.get("obstacle_debug_enabled") == true
	var avoidance_result = ObstacleAvoidance.compute(
		body, current_forward, c_fighter.avoid_radius,
		c_fighter.ship_radius, c_fighter.obstacle_radius, c_fighter.steer_force,
		want_debug
	)
	var avoidance_force: Vector3 = avoidance_result.get("force", Vector3.ZERO)
	var closest_obstacle_dist: float = avoidance_result.get("closest_dist", INF)
	var desired_dir: Vector3
	if avoidance_force.length() > 0.01:
		desired_dir = avoidance_force.normalized()
	else:
		desired_dir = _compute_desired_direction(body, c_targeting, c_fighter)
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

	# Turn-rate limit -> new facing direction (halved for less agile turning)
	var max_turn: float = deg_to_rad(c_fighter.turn_rate_deg * 0.5) * delta
	var new_forward: Vector3 = _rotate_toward(current_forward, desired_dir, max_turn)

	# Update C_Transform rotation (source of truth)
	var new_rotation_y: float = atan2(new_forward.x, new_forward.z)
	c_transform.rotation.y = new_rotation_y
	if c_targeting:
		c_targeting.forward_direction = new_forward

	# Apply C_Transform to body (drives visual rotation + position)
	body.global_position = c_transform.position
	body.rotation = Vector3(0.0, c_transform.rotation.y, 0.0)

	# Speed: reduce when near obstacles to allow time to swerve
	var tactical: Dictionary = _get_tactical_modifier(entity)
	var base_speed: float = c_state.speed * float(tactical.get("speed_multiplier", 1.0))
	var speed_mult: float = 1.0
	if closest_obstacle_dist < c_fighter.obstacle_slow_dist:
		var t: float = clampf(closest_obstacle_dist / c_fighter.obstacle_slow_dist, 0.0, 1.0)
		speed_mult = lerpf(c_fighter.min_speed_near_obstacle, 1.0, t)
	var speed: float = base_speed * speed_mult
	body.velocity = new_forward * speed
	body.move_and_slide()

	# Sync position back from body (collision may have adjusted it)
	c_transform.position = body.global_position


func _forward_from_rotation_y(rotation_y: float) -> Vector3:
	return Vector3(sin(rotation_y), 0.0, cos(rotation_y)).normalized()


func _compute_desired_direction(body: CharacterBody3D, c_targeting: C_Targeting, c_fighter: C_FighterMovement) -> Vector3:
	var target_pos: Vector3
	if c_targeting and c_targeting.target_node != null and is_instance_valid(c_targeting.target_node):
		target_pos = (c_targeting.target_node as Node3D).global_position
		# Offset target perpendicular to ship-target line so enemies approach from the side
		var ship_pos: Vector3 = body.global_position
		var to_struct: Vector3 = target_pos - ship_pos
		to_struct.y = 0.0
		if to_struct.length() > 0.01:
			var perp: Vector3 = Vector3(-to_struct.z, 0.0, to_struct.x).normalized()
			perp *= signf(c_fighter.target_offset_side) if c_fighter.target_offset_side != 0.0 else 1.0
			target_pos += perp * c_fighter.target_offset_length
	elif c_targeting:
		target_pos = c_targeting.fallback_position
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


func _get_tactical_modifier(entity: Entity) -> Dictionary:
	var enemy_manager: Node = Engine.get_main_loop().root.get_node_or_null("EnemyManager")
	if enemy_manager == null or not enemy_manager.has_method("get_tactical_modifier_for_enemy"):
		return {}
	var body_ref: C_PhysicsBodyRef = entity.get_component(C_PhysicsBodyRef) as C_PhysicsBodyRef
	var node_for_lookup: Node = body_ref.body if body_ref and body_ref.body else entity
	return enemy_manager.get_tactical_modifier_for_enemy(node_for_lookup)

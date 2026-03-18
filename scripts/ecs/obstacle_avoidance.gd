class_name ObstacleAvoidance
## Local-space obstacle avoidance: convert obstacles to ship-local coords,
## detect in-path collisions, aggregate lateral pushes from ALL in-path obstacles.
## Returns { "force": Vector3, "closest_dist": float }.


const OBSTACLE_COLLISION_LAYER: int = 4  # Structures and asteroids


static func compute(
	body: CharacterBody3D,
	forward: Vector3,
	avoid_radius: float,
	ship_radius: float,
	obstacle_radius: float,
	steer_force: float,
	include_debug: bool = false,
	exclude_rids: Array[RID] = []
) -> Dictionary:
	var empty_result: Dictionary = {"force": Vector3.ZERO, "closest_dist": INF}
	var obstacles: Array = _get_obstacles_in_range(body, forward, avoid_radius, exclude_rids)
	if obstacles.is_empty():
		if include_debug:
			_empty_result_add_debug(empty_result, body, forward, avoid_radius)
		return empty_result

	var ship_pos: Vector3 = body.global_position
	var fwd: Vector3 = forward
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		if include_debug:
			_empty_result_add_debug(empty_result, body, forward, avoid_radius)
		return empty_result
	fwd = fwd.normalized()

	var perp: Vector3 = Vector3(-fwd.z, 0.0, fwd.x).normalized()
	var avoidance_width: float = ship_radius + obstacle_radius

	var total_lateral_push: float = 0.0
	var closest_dist: float = INF

	for collider in obstacles:
		var obs_pos: Vector3 = (collider as Node3D).global_position
		var to_obs: Vector3 = obs_pos - ship_pos
		to_obs.y = 0.0
		var dist: float = to_obs.length()
		if dist > avoid_radius or dist < 0.001:
			continue

		var local_x: float = to_obs.dot(fwd)
		if local_x <= 0.0:
			continue

		var lateral: float = to_obs.dot(perp)
		var lateral_abs: float = absf(lateral)
		if lateral_abs >= avoidance_width:
			continue

		var strength: float = steer_force * (1.0 - dist / maxf(avoid_radius, 0.01))
		if absf(lateral) < 0.001:
			total_lateral_push += strength  # dead ahead, arbitrarily steer right
		else:
			total_lateral_push += -signf(lateral) * strength

		if dist < closest_dist:
			closest_dist = dist

	if closest_dist >= INF:
		if include_debug:
			_empty_result_add_debug(empty_result, body, forward, avoid_radius)
		return empty_result

	# Clamp magnitude to avoid overshoot
	total_lateral_push = clampf(total_lateral_push, -steer_force, steer_force)
	var result: Dictionary = {
		"force": perp * total_lateral_push,
		"closest_dist": closest_dist
	}
	if include_debug:
		_empty_result_add_debug(result, body, forward, avoid_radius)
	return result


static func _empty_result_add_debug(out: Dictionary, body: CharacterBody3D, forward: Vector3, avoid_radius: float) -> void:
	var fwd: Vector3 = forward
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	out["debug_sphere_center"] = body.global_position + fwd * (avoid_radius * 0.5)
	out["debug_sphere_radius"] = avoid_radius * 0.6


static func _get_obstacles_in_range(body: CharacterBody3D, forward: Vector3, avoid_radius: float, exclude_rids: Array[RID] = []) -> Array:
	var space_state: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = avoid_radius * 0.6

	var fwd: Vector3 = forward
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()

	var center: Vector3 = body.global_position + fwd * (avoid_radius * 0.5)
	var xform: Transform3D = Transform3D(Basis(), center)

	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = xform
	params.collision_mask = OBSTACLE_COLLISION_LAYER
	var rids: Array[RID] = [body.get_rid()]
	rids.append_array(exclude_rids)
	params.exclude = rids

	var results: Array = space_state.intersect_shape(params, 24)
	var colliders: Array = []
	var seen: Dictionary = {}
	for result in results:
		var collider: Object = result.get("collider", null)
		if collider == null or collider == body or not (collider is Node3D):
			continue
		if seen.get(collider.get_instance_id(), false):
			continue
		seen[collider.get_instance_id()] = true
		colliders.append(collider)
	return colliders

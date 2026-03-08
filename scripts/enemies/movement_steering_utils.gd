extends RefCounted
class_name MovementSteeringUtils
## Pure functions for steering - no state. Used by movement systems.


static func compute_obstacle_avoidance(body: CharacterBody3D, steering: Object, forward_dir: Vector3) -> Vector3:
	if body == null or steering == null:
		return Vector3.ZERO
	var space_state: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	if space_state == null:
		return Vector3.ZERO
	var scan_dir: Vector3 = forward_dir
	if body.velocity.length() > 0.3:
		scan_dir = Vector3(body.velocity.x, 0.0, body.velocity.z).normalized()
	var range_used: float = maxf(steering.avoidance_scan_range, steering.avoidance_range)
	var total_avoid: Vector3 = Vector3.ZERO
	var ray_angles: Array[float] = [0.0, -steering.avoidance_cone_deg * 0.5, steering.avoidance_cone_deg * 0.5, -steering.avoidance_cone_deg, steering.avoidance_cone_deg]
	for angle_deg in ray_angles:
		var ray_dir: Vector3 = _rotate_around_y(scan_dir, angle_deg)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			body.global_position,
			body.global_position + ray_dir * range_used
		)
		query.exclude = [body]
		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			continue
		var obstacle_pos: Vector3 = result.position
		var dist: float = body.global_position.distance_to(obstacle_pos)
		var strength: float = steering.avoidance_force * (1.0 - dist / maxf(range_used, 0.01))
		var away: Vector3 = (body.global_position - obstacle_pos)
		away.y = 0.0
		if away.length() > 0.01:
			away = away.normalized()
		else:
			away = Vector3(-ray_dir.z, 0.0, ray_dir.x).normalized()
		total_avoid += away * strength * 0.08
	return total_avoid


static func compute_separation(body: CharacterBody3D, steering: Object) -> Vector3:
	if body == null or steering == null:
		return Vector3.ZERO
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = steering.separation_radius
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), body.global_position)
	query.exclude = [body]
	query.collision_mask = 0xFFFFFFFF
	var space_state: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	if space_state == null:
		return Vector3.ZERO
	var results: Array[Dictionary] = space_state.intersect_shape(query, 8)
	var total_repel: Vector3 = Vector3.ZERO
	for hit in results:
		var collider: Object = hit.get("collider", null)
		if collider == null or collider == body:
			continue
		var hit_pos: Vector3 = hit.get("position", body.global_position)
		var diff: Vector3 = body.global_position - hit_pos
		diff.y = 0.0
		var dist: float = diff.length()
		if dist < 0.01:
			continue
		var strength: float = steering.separation_force * (1.0 - dist / maxf(steering.separation_radius, 0.01))
		total_repel += diff.normalized() * strength * 0.012
	return total_repel


static func rotate_dir_toward(from_dir: Vector3, to_dir: Vector3, max_radians: float) -> Vector3:
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


static func flat_dir_to(from_pos: Vector3, to_pos: Vector3) -> Vector3:
	var to_target: Vector3 = to_pos - from_pos
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return Vector3.ZERO
	return to_target.normalized()


static func _rotate_around_y(dir: Vector3, angle_deg: float) -> Vector3:
	var angle: float = deg_to_rad(angle_deg)
	var c: float = cos(angle)
	var s: float = sin(angle)
	return Vector3(dir.x * c - dir.z * s, 0.0, dir.x * s + dir.z * c).normalized()



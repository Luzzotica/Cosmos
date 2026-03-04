extends RefCounted
class_name EnemyMovementBehavior
## Turn-rate-limited impulse flight with swarm dive/circle and obstacle avoidance.

enum SwarmPhase { DIVE_IN, ORBIT, CIRCLE_OUT }

var max_acceleration: float = 10.0
var drag: float = 2.0
var max_turn_rate_deg: float = 110.0
var avoidance_range: float = 18.0
var avoidance_force: float = 22.0
var avoidance_scan_range: float = 25.0
var avoidance_cone_deg: float = 32.0
var separation_radius: float = 6.0
var separation_force: float = 35.0
var orbit_distance: float = 10.0
var orbit_error_radius: float = 2.5
var swarm_orbit_duration: float = 2.5
var swarm_circle_out_duration: float = 1.2
var swarm_circle_out_speed_mult: float = 1.15

var _forward_dir: Vector3 = Vector3.FORWARD
var _current_speed: float = 0.0
var _orbit_direction: int = 0
var _swarm_phase: SwarmPhase = SwarmPhase.DIVE_IN
var _swarm_timer: float = 0.0
var _swarm_enabled: bool = true


func configure(profile: Dictionary) -> void:
	max_acceleration = float(profile.get("max_acceleration", max_acceleration))
	drag = float(profile.get("drag", drag))
	max_turn_rate_deg = float(profile.get("max_turn_rate_deg", max_turn_rate_deg))
	avoidance_range = float(profile.get("avoidance_range", avoidance_range))
	avoidance_force = float(profile.get("avoidance_force", avoidance_force))
	avoidance_scan_range = float(profile.get("avoidance_scan_range", avoidance_scan_range))
	avoidance_cone_deg = float(profile.get("avoidance_cone_deg", avoidance_cone_deg))
	separation_radius = float(profile.get("separation_radius", separation_radius))
	separation_force = float(profile.get("separation_force", separation_force))
	orbit_distance = float(profile.get("orbit_distance", orbit_distance))
	orbit_error_radius = float(profile.get("orbit_error_radius", orbit_error_radius))
	swarm_orbit_duration = float(profile.get("swarm_orbit_duration", swarm_orbit_duration))
	swarm_circle_out_duration = float(profile.get("swarm_circle_out_duration", swarm_circle_out_duration))
	swarm_circle_out_speed_mult = float(profile.get("swarm_circle_out_speed_mult", swarm_circle_out_speed_mult))
	_swarm_enabled = bool(profile.get("swarm_dive_circle", true))


func set_initial_forward(forward: Vector3) -> void:
	var flat: Vector3 = Vector3(forward.x, 0.0, forward.z)
	if flat.length() > 0.01:
		_forward_dir = flat.normalized()


func step(delta: float, enemy: CharacterBody3D, target: Node3D, fallback_position: Vector3, tactical_modifier: Dictionary = {}) -> Vector3:
	var desired_dir: Vector3 = _compute_desired_direction(delta, enemy, target, fallback_position)
	var avoidance: Vector3 = _compute_obstacle_avoidance(enemy)
	var separation: Vector3 = _compute_separation(enemy)
	desired_dir = (desired_dir + avoidance + separation).normalized()
	if desired_dir.length() < 0.01:
		desired_dir = _forward_dir
	_forward_dir = _rotate_toward(_forward_dir, desired_dir, deg_to_rad(max_turn_rate_deg) * delta)

	var speed_target: float = float(enemy.get("speed")) * float(tactical_modifier.get("speed_multiplier", 1.0))
	if target != null:
		var dist: float = enemy.global_position.distance_to(target.global_position)
		var attack_range: float = float(enemy.get("attack_range"))
		if dist <= attack_range:
			if _swarm_phase == SwarmPhase.CIRCLE_OUT:
				speed_target *= swarm_circle_out_speed_mult
			else:
				speed_target *= 0.85
	_current_speed = move_toward(_current_speed, speed_target, max_acceleration * delta)
	_current_speed = maxf(_current_speed - drag * delta, 0.0)

	return _forward_dir * _current_speed


func _compute_desired_direction(delta: float, enemy: CharacterBody3D, target: Node3D, fallback_position: Vector3) -> Vector3:
	if target == null:
		_swarm_phase = SwarmPhase.DIVE_IN
		_swarm_timer = 0.0
		return _flat_dir_to(enemy.global_position, fallback_position)

	var to_target: Vector3 = target.global_position - enemy.global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance < 0.01:
		return _forward_dir
	var attack_range: float = float(enemy.get("attack_range"))

	if not _swarm_enabled:
		if distance > attack_range:
			_orbit_direction = 0
			return to_target.normalized()
		return _orbit_direction_internal(enemy, to_target, distance)

	_swarm_timer -= delta
	if distance > attack_range:
		_swarm_phase = SwarmPhase.DIVE_IN
		_swarm_timer = 0.0
		_orbit_direction = 0
		return to_target.normalized()

	match _swarm_phase:
		SwarmPhase.DIVE_IN:
			_swarm_phase = SwarmPhase.ORBIT
			_swarm_timer = swarm_orbit_duration
			if _orbit_direction == 0:
				var cross: float = enemy.velocity.x * to_target.z - enemy.velocity.z * to_target.x
				_orbit_direction = 1 if cross >= 0.0 else -1
			return _orbit_direction_internal(enemy, to_target, distance)
		SwarmPhase.ORBIT:
			if _swarm_timer <= 0.0:
				_swarm_phase = SwarmPhase.CIRCLE_OUT
				_swarm_timer = swarm_circle_out_duration
			return _orbit_direction_internal(enemy, to_target, distance)
		SwarmPhase.CIRCLE_OUT:
			if _swarm_timer <= 0.0:
				_swarm_phase = SwarmPhase.DIVE_IN
				_swarm_timer = 0.0
			return (-to_target).normalized()
	return to_target.normalized()


func _orbit_direction_internal(enemy: CharacterBody3D, to_target: Vector3, distance: float) -> Vector3:
	if _orbit_direction == 0:
		var cross: float = enemy.velocity.x * to_target.z - enemy.velocity.z * to_target.x
		_orbit_direction = 1 if cross >= 0.0 else -1
	var tangent: Vector3 = Vector3(-to_target.z, 0.0, to_target.x).normalized() * _orbit_direction
	var radius_error: float = distance - orbit_distance
	var radial_fix: Vector3 = Vector3.ZERO
	if abs(radius_error) > orbit_error_radius:
		radial_fix = to_target.normalized() * clampf(radius_error * 0.45, -1.0, 1.0)
	return (tangent + radial_fix).normalized()


func _compute_obstacle_avoidance(enemy: CharacterBody3D) -> Vector3:
	var space_state: PhysicsDirectSpaceState3D = enemy.get_world_3d().direct_space_state
	var scan_dir: Vector3 = _forward_dir
	if enemy.velocity.length() > 0.3:
		scan_dir = Vector3(enemy.velocity.x, 0.0, enemy.velocity.z).normalized()
	var range_used: float = maxf(avoidance_scan_range, avoidance_range)

	var total_avoid: Vector3 = Vector3.ZERO
	var ray_angles: Array[float] = [0.0, -avoidance_cone_deg * 0.5, avoidance_cone_deg * 0.5, -avoidance_cone_deg, avoidance_cone_deg]
	for angle_deg in ray_angles:
		var ray_dir: Vector3 = _rotate_around_y(scan_dir, angle_deg)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			enemy.global_position,
			enemy.global_position + ray_dir * range_used
		)
		query.exclude = [enemy]
		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			continue
		var obstacle_pos: Vector3 = result.position
		var dist: float = enemy.global_position.distance_to(obstacle_pos)
		var strength: float = avoidance_force * (1.0 - dist / maxf(range_used, 0.01))
		var away: Vector3 = (enemy.global_position - obstacle_pos)
		away.y = 0.0
		if away.length() > 0.01:
			away = away.normalized()
		else:
			away = Vector3(-ray_dir.z, 0.0, ray_dir.x).normalized()
		total_avoid += away * strength * 0.08
	return total_avoid


func _rotate_around_y(dir: Vector3, angle_deg: float) -> Vector3:
	var angle: float = deg_to_rad(angle_deg)
	var c: float = cos(angle)
	var s: float = sin(angle)
	return Vector3(dir.x * c - dir.z * s, 0.0, dir.x * s + dir.z * c).normalized()


func _compute_separation(enemy: CharacterBody3D) -> Vector3:
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = separation_radius
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), enemy.global_position)
	query.exclude = [enemy]
	query.collision_mask = 0xFFFFFFFF

	var space_state: PhysicsDirectSpaceState3D = enemy.get_world_3d().direct_space_state
	var results: Array[Dictionary] = space_state.intersect_shape(query, 8)

	var total_repel: Vector3 = Vector3.ZERO
	for hit in results:
		var collider: Object = hit.get("collider", null)
		if collider == null or collider == enemy:
			continue
		var hit_pos: Vector3 = hit.get("position", enemy.global_position)
		var diff: Vector3 = enemy.global_position - hit_pos
		diff.y = 0.0
		var dist: float = diff.length()
		if dist < 0.01:
			continue
		var strength: float = separation_force * (1.0 - dist / maxf(separation_radius, 0.01))
		total_repel += diff.normalized() * strength * 0.012
	return total_repel


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


func _flat_dir_to(from_pos: Vector3, to_pos: Vector3) -> Vector3:
	var to_target: Vector3 = to_pos - from_pos
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return Vector3.ZERO
	return to_target.normalized()

class_name ObstacleDebugStore
## Static store for per-frame obstacle avoidance debug data.
## Movement systems push entries when overlay has obstacle_debug_enabled;
## overlay pops and draws each frame.


static var _entries: Array[Dictionary] = []


static func push(position: Vector3, sphere_center: Vector3, sphere_radius: float, desired_dir: Vector3, current_forward: Vector3) -> void:
	_entries.append({
		"position": position,
		"sphere_center": sphere_center,
		"sphere_radius": sphere_radius,
		"desired_dir": desired_dir,
		"current_forward": current_forward
	})


static func pop_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = _entries.duplicate()
	_entries.clear()
	return out

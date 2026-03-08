extends RefCounted
class_name EnemyTargetingBehavior
## Target scoring strategies per enemy type.

var mode: String = "nearest"
var power_priority_bias: float = 20.0
var base_retarget_interval: float = 0.5


func configure(profile: Dictionary) -> void:
	mode = String(profile.get("mode", mode))
	power_priority_bias = float(profile.get("power_priority_bias", power_priority_bias))
	base_retarget_interval = float(profile.get("retarget_interval", base_retarget_interval))


func get_retarget_interval(tactical_modifier: Dictionary) -> float:
	var override_interval: float = float(tactical_modifier.get("retarget_interval_override", base_retarget_interval))
	return maxf(override_interval, 0.1)


func choose_target(enemy: Node3D, candidates: Array, tactical_modifier: Dictionary) -> Node3D:
	var best_score: float = -INF
	var best_target: Node3D = null
	var priority_multiplier: float = float(tactical_modifier.get("target_priority_multiplier", 1.0))
	for candidate in candidates:
		var target: Node3D = candidate as Node3D
		if target == null:
			continue
		var score: float = _score_target(enemy, target, priority_multiplier)
		if score > best_score:
			best_score = score
			best_target = target
	return best_target


func _score_target(enemy: Node3D, target: Node3D, priority_multiplier: float) -> float:
	var distance: float = enemy.global_position.distance_to(target.global_position)
	var score: float = -distance
	if mode == "power_priority":
		if _is_power_critical(target):
			score += power_priority_bias * priority_multiplier
		if String(target.get("building_type")) == "laser_turret":
			score += (power_priority_bias * 0.6) * priority_multiplier
	return score


func _is_power_critical(target: Node3D) -> bool:
	if target.get("power_node") != null:
		return true
	var entity = target.get("_ecs_entity") if target.get("_ecs_entity") != null else (target if target.has_method("get_component") else null)
	if entity and entity.has_method("get_component") and entity.get_component(C_PowerNode) != null:
		return true
	var building_type: String = String(target.get("building_type"))
	return building_type == "power_node" or building_type == "solar_panel"

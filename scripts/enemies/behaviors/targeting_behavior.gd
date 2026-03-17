extends RefCounted
class_name EnemyTargetingBehavior
## Target scoring strategies per enemy type.

const SaboteurTargets: Script = preload("res://scripts/enemies/saboteur_power_targets.gd")

var mode: String = "nearest"
var power_priority_bias: float = 20.0
var base_retarget_interval: float = 0.5


func configure(profile: Dictionary) -> void:
	mode = str(profile.get("mode", mode))
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
		if str(target.get("building_type")) == "laser_turret":
			score += (power_priority_bias * 0.6) * priority_multiplier
	return score


func _is_power_critical(target: Node3D) -> bool:
	if target.get("power_node") != null:
		return true
	var building_type: String = str(target.get("building_type"))
	return building_type == "power_node" or building_type == "solar_panel"


## Saboteur-specific: pick best target from power graph (leaf lines first, else source lines).
## Prioritizes damage-dealers (e.g. laser turrets) for leaf targets. Returns { target_structure, hover_position } or {}.
func choose_saboteur_target(enemy: Node3D, player_structures: Array) -> Dictionary:
	var targets: Array = SaboteurTargets.get_leaf_targets(player_structures)
	if targets.is_empty():
		targets = SaboteurTargets.get_source_targets(player_structures)
	if targets.is_empty():
		return {}
	var enemy_pos: Vector3 = enemy.global_position
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.is_damage_dealer and not b.is_damage_dealer:
			return true
		if not a.is_damage_dealer and b.is_damage_dealer:
			return false
		var dist_a: float = enemy_pos.distance_to(a.line_midpoint)
		var dist_b: float = enemy_pos.distance_to(b.line_midpoint)
		return dist_a < dist_b
	)
	var best: Dictionary = targets[0]
	var structure: Node3D = best.structure
	if not is_instance_valid(structure) or structure.get("is_destroyed") == true:
		return {}
	return {
		"target_structure": structure,
		"hover_position": best.line_midpoint,
		"line_start": best.get("line_start", Vector3.ZERO),
		"line_end": best.get("line_end", Vector3.ZERO)
	}

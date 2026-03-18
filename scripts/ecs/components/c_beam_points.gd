class_name C_BeamPoints
extends Component
## Stores cached beam emit and attack point nodes for O(1) lookup.
## Populated once at init by BeamPointsSetupSystem.

var emit_point: Node3D = null  ## Beam origin; null = use fallback
var attack_points: Array[Node3D] = []  ## Hit points; empty = use fallback


func has_emit_point() -> bool:
	return emit_point != null and is_instance_valid(emit_point)


func get_beam_emit_position() -> Vector3:
	return emit_point.global_position if has_emit_point() else Vector3.ZERO


func has_attack_points() -> bool:
	return not attack_points.is_empty()


func get_random_attack_position() -> Vector3:
	if not has_attack_points():
		return Vector3.ZERO
	var idx: int = randi() % attack_points.size()
	var node: Node3D = attack_points[idx]
	return node.global_position if node and is_instance_valid(node) else Vector3.ZERO

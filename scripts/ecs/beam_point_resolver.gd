class_name BeamPointResolver
## O(1) beam point lookup. Requires C_BeamPoints on entity; fallback if missing.

const C_BeamPointsClass = preload("res://scripts/ecs/components/c_beam_points.gd")


static func get_beam_emit_point(body_node: Node3D) -> Vector3:
	var entity: Node = _get_entity_for_body(body_node)
	var c = entity.get_component(C_BeamPointsClass) if entity else null
	if c and c.has_emit_point():
		return c.get_beam_emit_position()
	return body_node.global_position + Vector3.UP * 0.6  # fallback


static func get_random_attack_point(target_node: Node3D) -> Vector3:
	var entity: Node = _get_entity_for_body(target_node)
	var c = entity.get_component(C_BeamPointsClass) if entity else null
	if c and c.has_attack_points():
		return c.get_random_attack_position()
	return Vector3(target_node.global_position.x, 0, target_node.global_position.z)  # fallback


static func _get_entity_for_body(body: Node3D) -> Node:
	var n: Node = body
	while n:
		if n.has_method("get_component"):
			return n
		n = n.get_parent()
	return null

extends RefCounted
class_name SaboteurPowerTargets
## Helper functions that query PowerGraphManager for saboteur targeting.
## Uses only public API - does not modify PowerGraphManager.


static func get_leaf_targets(player_structures: Array) -> Array:
	if not PowerGraphManager:
		return []
	var graph: Dictionary = PowerGraphManager.get_graph()
	var targets: Array = []
	for node in graph.keys():
		if not is_instance_valid(node):
			continue
		if not node.has_method("get_node_type"):
			continue
		if int(node.get_node_type()) != int(PowerNode.NodeType.LEAF):
			continue
		var struct: Node3D = node.get_parent() as Node3D
		if not struct or struct not in player_structures:
			continue
		var construction: Node = struct.get_node_or_null("ConstructionComponent")
		if construction != null and construction.get("is_built") != true:
			continue
		if struct.get("is_destroyed") == true:
			continue
		var neighbors: Array = graph[node].keys()
		if neighbors.is_empty():
			continue
		var upstream_node: Node3D = neighbors[0]
		if not is_instance_valid(upstream_node):
			continue
		var line_start: Vector3 = _get_node_world_position(node)
		var line_end: Vector3 = _get_node_world_position(upstream_node)
		var line_midpoint: Vector3 = (line_start + line_end) * 0.5
		var building_type: String = str(struct.get("building_type"))
		var is_damage_dealer: bool = (building_type == "laser_turret")
		targets.append({
			"structure": struct,
			"power_node": node,
			"upstream_node": upstream_node,
			"line_midpoint": line_midpoint,
			"line_start": line_start,
			"line_end": line_end,
			"is_damage_dealer": is_damage_dealer
		})
	return targets


static func get_source_targets(player_structures: Array) -> Array:
	if not PowerGraphManager:
		return []
	var graph: Dictionary = PowerGraphManager.get_graph()
	var targets: Array = []
	for node in graph.keys():
		if not is_instance_valid(node):
			continue
		if not node.has_method("get_node_type"):
			continue
		if int(node.get_node_type()) != int(PowerNode.NodeType.SOURCE):
			continue
		var struct: Node3D = node.get_parent() as Node3D
		if not struct or struct not in player_structures:
			continue
		var construction: Node = struct.get_node_or_null("ConstructionComponent")
		if construction != null and construction.get("is_built") != true:
			continue
		if struct.get("is_destroyed") == true:
			continue
		var neighbors: Array = graph[node].keys()
		if neighbors.is_empty():
			continue
		var neighbor_node: Node3D = neighbors[0]
		if not is_instance_valid(neighbor_node):
			continue
		var line_start: Vector3 = _get_node_world_position(node)
		var line_end: Vector3 = _get_node_world_position(neighbor_node)
		var line_midpoint: Vector3 = (line_start + line_end) * 0.5
		targets.append({
			"structure": struct,
			"power_node": node,
			"upstream_node": neighbor_node,
			"line_midpoint": line_midpoint,
			"line_start": line_start,
			"line_end": line_end,
			"is_damage_dealer": false
		})
	return targets


static func _get_node_world_position(node: Node3D) -> Vector3:
	var struct: Node3D = node.get_parent() as Node3D
	if struct:
		return struct.global_position
	return node.global_position

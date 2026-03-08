extends System
class_name ConstructionPowerPreviewSystem
## Renders dim power lines for preview connections on entities under construction.
## Uses PowerGraph.compute_preview_connections with saved_max_connections. Lines are visual-only.

const C_ConstructionPowerNode = preload("res://scripts/ecs/components/c_construction_power_node.gd")
const ConstructionPowerPreviewLine = preload("res://scripts/ecs/construction_power_preview_line.gd")
const PowerEdgeLineNode = preload("res://scripts/ecs/power_edge_line_node.gd")

## Preview lines by canonical pair key "lo_hi"
var _preview_lines: Dictionary = {}


func query() -> QueryBuilder:
	return q.with_all([C_Structure, C_PowerNode, C_ConstructionPowerNode])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	pass
	# if not PowerGraph or not GameWorld or not GameWorld.power_lines_parent:
	# 	return

	# var entity_by_id: Dictionary = _build_entity_by_id()
	# var active_pairs: Dictionary = {}  # "lo_hi" -> true

	# for entity in entities:
	# 	var c_pn: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	# 	var c_struct: C_Structure = entity.get_component(C_Structure) as C_Structure
	# 	if c_pn == null or c_struct == null or c_struct.structure_node == null:
	# 		continue

	# 	var preview_ids: Array[int] = PowerGraph.compute_preview_connections(entity, c_cpn.saved_max_connections)
	# 	c_cpn.preview_connected_entity_ids = preview_ids

	# 	var struct_a: Node3D = c_struct.structure_node as Node3D
	# 	var id_a: int = entity.get_instance_id()

	# 	for other_id in preview_ids:
	# 		var key: String = _pair_key(id_a, other_id)
	# 		active_pairs[key] = true
	# 		if not _preview_lines.has(key):
	# 			_create_preview_line(entity_by_id, id_a, other_id, struct_a)

	# _update_preview_line_positions(entity_by_id, active_pairs)
	# _remove_stale_preview_lines(active_pairs)


func _build_entity_by_id() -> Dictionary:
	var result: Dictionary = {}
	if not ECS or not ECS.world:
		return result
	var qry = ECS.world.get("query")
	if qry == null:
		return result
	for ent in qry.with_all([C_Structure]).execute():
		result[ent.get_instance_id()] = ent
	return result


func _pair_key(id_a: int, id_b: int) -> String:
	var lo: int = mini(id_a, id_b)
	var hi: int = maxi(id_a, id_b)
	return "%d_%d" % [lo, hi]


func _create_preview_line(entity_by_id: Dictionary, id_a: int, id_b: int, struct_a: Node3D) -> void:
	var ent_b: Entity = entity_by_id.get(id_b) as Entity
	if ent_b == null:
		return
	var c_struct_b: C_Structure = ent_b.get_component(C_Structure) as C_Structure
	if c_struct_b == null or c_struct_b.structure_node == null:
		return
	var struct_b: Node3D = c_struct_b.structure_node as Node3D

	var pos_a: Vector3 = PowerEdgeLineNode.get_connection_anchor(struct_a)
	var pos_b: Vector3 = PowerEdgeLineNode.get_connection_anchor(struct_b)

	var line: ConstructionPowerPreviewLine = ConstructionPowerPreviewLine.new()
	line.setup(pos_a, pos_b, struct_a, struct_b)

	var lines_parent: Node3D = GameWorld.power_lines_parent
	if lines_parent and is_instance_valid(lines_parent):
		lines_parent.add_child(line)

	var key: String = _pair_key(id_a, id_b)
	line.set_meta("pair_key", key)
	line.set_meta("id_a", id_a)
	line.set_meta("id_b", id_b)
	_preview_lines[key] = line


func _update_preview_line_positions(entity_by_id: Dictionary, active_pairs: Dictionary) -> void:
	for key in active_pairs.keys():
		var line: Variant = _preview_lines.get(key)
		if line == null or not is_instance_valid(line):
			continue
		var id_a: int = line.get_meta("id_a", 0)
		var id_b: int = line.get_meta("id_b", 0)
		var ent_a: Entity = entity_by_id.get(id_a) as Entity
		var ent_b: Entity = entity_by_id.get(id_b) as Entity
		if ent_a == null or ent_b == null:
			continue
		var c_sa: C_Structure = ent_a.get_component(C_Structure) as C_Structure
		var c_sb: C_Structure = ent_b.get_component(C_Structure) as C_Structure
		if c_sa == null or c_sb == null or c_sa.structure_node == null or c_sb.structure_node == null:
			continue
		var struct_a: Node3D = c_sa.structure_node as Node3D
		var struct_b: Node3D = c_sb.structure_node as Node3D
		var pos_a: Vector3 = PowerEdgeLineNode.get_connection_anchor(struct_a)
		var pos_b: Vector3 = PowerEdgeLineNode.get_connection_anchor(struct_b)
		if line is ConstructionPowerPreviewLine:
			line.update_positions(pos_a, pos_b, struct_a, struct_b)


func _remove_stale_preview_lines(active_pairs: Dictionary) -> void:
	var to_remove: Array[String] = []
	for key in _preview_lines.keys():
		if not active_pairs.has(key):
			to_remove.append(key)
	for key in to_remove:
		var line: Variant = _preview_lines.get(key)
		_preview_lines.erase(key)
		if line != null and is_instance_valid(line):
			line.queue_free()

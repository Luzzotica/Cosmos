extends Node
## PowerGraph - In-memory graph updated by observers (refresh_graph). Fast lookups, no per-frame sync.

class_name PowerGraphClass

const C_PowerEdge = preload("res://scripts/ecs/components/c_power_edge.gd")
const PowerEdgeLineNode = preload("res://scripts/ecs/power_edge_line_node.gd")
const _C_ConstructionPowerNode = preload("res://scripts/ecs/components/c_construction_power_node.gd")

var _refresh_pending: bool = false
var _edge_by_pair: Dictionary = {}  # "e_lo_hi" -> edge Entity, used during refresh_graph

## PowerSubgraph - holds entity refs, derives component-based properties.
class PowerSubgraph:
	var nodes: Array = []
	var users: Array = []
	var sources: Array = []
	var generators: Array = []

	var power_capacity: float:
		get:
			var total: float = 0.0
			for ent in sources:
				if is_instance_valid(ent):
					var c: C_PowerSource = ent.get_component(C_PowerSource) as C_PowerSource
					if c:
						total += c.max_storage
			return total

	var power_current: float:
		get:
			var total: float = 0.0
			for ent in sources:
				if is_instance_valid(ent):
					var c: C_PowerSource = ent.get_component(C_PowerSource) as C_PowerSource
					if c:
						total += c.current_storage
			return total

	var power_generation: float:
		get:
			var total: float = 0.0
			for ent in generators:
				if is_instance_valid(ent):
					var c: C_PowerGenerator = ent.get_component(C_PowerGenerator) as C_PowerGenerator
					if c:
						total += c.current_output
			return total

	var power_consumption: float:
		get:
			var total: float = 0.0
			for ent in users:
				if is_instance_valid(ent):
					var c: C_PowerUser = ent.get_component(C_PowerUser) as C_PowerUser
					if c:
						total += c.power_consumption
			return total

	var power_balance: float:
		get:
			return power_generation - power_consumption

	var available_power: float:
		get:
			return power_current + power_balance

	var has_enough_power: bool:
		get:
			return available_power >= power_consumption


# Graph caches - node_id keyed (composite: multiple nodes per entity)
var _nodes: Dictionary = {}  # node_id -> {entity_id, neighbor_node_ids, is_source, is_enabled, struct_node, has_user, has_generator}
var _node_id_to_entity_id: Dictionary = {}
var _entity_by_id: Dictionary = {}
var _struct_id_to_entity_id: Dictionary = {}  # struct instance_id -> entity_id
var _edge_enabled: Dictionary = {}  # edge_key(node_id) -> bool
var _edge_entity_by_pair: Dictionary = {}  # edge_key -> Entity
var _edges_struct_map: Dictionary = {}  # struct_a -> {struct_b -> {}}


func _edge_key(id_a: int, id_b: int) -> String:
	var lo: int = mini(id_a, id_b)
	var hi: int = maxi(id_a, id_b)
	return "%d_%d" % [lo, hi]


func _edge_key_node_ids(node_id_a: String, node_id_b: String) -> String:
	if node_id_a < node_id_b:
		return "%s|%s" % [node_id_a, node_id_b]
	return "%s|%s" % [node_id_b, node_id_a]


func _edge_key_ids(id_a: int, id_b: int) -> String:
	var lo: int = mini(id_a, id_b)
	var hi: int = maxi(id_a, id_b)
	return "e_%d_%d" % [lo, hi]


static func _make_node_id(entity_id: int, node: Variant) -> String:
	if node is C_PowerNode:
		return "%d:PowerNode" % entity_id
	if node is C_ConstructionPowerNode:
		return "%d:ConstructionPowerNode" % entity_id
	return ""


## Returns all power node components on entity (C_PowerNode, C_ConstructionPowerNode).
static func _get_all_power_nodes(entity: Entity) -> Array:
	var out: Array = []
	var c_pn: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_pn:
		out.append(c_pn)
	var c_cpn = entity.get_component(_C_ConstructionPowerNode)
	if c_cpn:
		out.append(c_cpn)
	return out


## Returns the first/primary power node for entity. Prefers C_ConstructionPowerNode when present (during build).
## Used by structure_behavior, base_structure, solar_panel_entity for build print direction.
static func _get_active_power_node(entity: Entity) -> Variant:
	var nodes: Array = _get_all_power_nodes(entity)
	if nodes.is_empty():
		return null
	var c_cpn = entity.get_component(_C_ConstructionPowerNode)
	if c_cpn:
		return c_cpn
	return nodes[0]


## Whether the power node is enabled. Works with C_PowerNode or C_ConstructionPowerNode.
static func _is_power_node_enabled(node: Variant) -> bool:
	if node is C_PowerNode:
		return (node as C_PowerNode).is_enabled
	if node is C_ConstructionPowerNode:
		return (node as C_ConstructionPowerNode).is_enabled
	return false


## For placement preview: get built max_connections.
static func _get_preview_max_connections_for_entity(entity: Entity) -> int:
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node:
		return c_power_node.max_connections
	return 0


## Whether the node can accept more connections. Works with C_PowerNode or C_ConstructionPowerNode.
static func _can_accept_more_connections(node: Variant) -> bool:
	if node == null:
		return false
	return node.connected_entity_ids.size() < node.max_connections


## Returns node_ids for entity (for BFS, draw_power). Uses first enabled node if multiple.
func _get_node_ids_for_entity(entity_id: int) -> Array:
	var out: Array = []
	var ent = _entity_by_id.get(entity_id)
	if ent == null or not is_instance_valid(ent):
		return out
	for node in _get_all_power_nodes(ent as Entity):
		var nid: String = _make_node_id(entity_id, node)
		if _nodes.has(nid) and _is_power_node_enabled(node):
			out.append(nid)
	return out


## Returns entity_ids that would connect if this node had max_connections_override capacity.
## Excludes connections already in the preview node's connected_entity_ids.
func compute_preview_connections(entity: Entity, max_connections_override: int) -> Array[int]:
	if max_connections_override <= 0:
		return []
	var preview_node: Variant = null
	var c_cpn = entity.get_component(_C_ConstructionPowerNode)
	if c_cpn:
		preview_node = c_cpn
	else:
		preview_node = entity.get_component(C_PowerNode) as C_PowerNode
	if preview_node == null:
		return []
	var world: Node = ECS.world if ECS else null
	if world == null:
		return []
	var q = world.get("query")
	if q == null:
		return []
	var entities: Array = q.with_any([C_PowerNode, C_ConstructionPowerNode]).with_all([C_Structure]).execute()
	var entity_by_id: Dictionary = {}
	for e in entities:
		entity_by_id[e.get_instance_id()] = e
	var all_nodes: Array = []
	var node_by_id: Dictionary = {}
	for e in entities:
		for node in _get_all_power_nodes(e as Entity):
			var nid: String = _make_node_id(e.get_instance_id(), node)
			all_nodes.append({"entity": e, "node": node, "node_id": nid})
			node_by_id[nid] = {"entity": e, "node": node}
	var my_entity_id: int = entity.get_instance_id()
	var my_node_id: String = _make_node_id(my_entity_id, preview_node)
	var all_potential: Array = _compute_connections_for_node(preview_node, entity, my_node_id, all_nodes, node_by_id, max_connections_override)
	var result: Array[int] = []
	for other_node_id in all_potential:
		var other_data = node_by_id.get(other_node_id, {})
		var other_ent = other_data.get("entity")
		if other_ent:
			var other_id: int = other_ent.get_instance_id()
			if other_id not in preview_node.connected_entity_ids:
				result.append(other_id)
	return result


## Called by observers. Debounced so rapid events trigger a single refresh per frame.
func request_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_do_refresh")


func _do_refresh() -> void:
	_refresh_pending = false
	if ECS and ECS.world:
		refresh_graph(ECS.world)


## Query C_PowerEdge entities and build edge_by_pair. Key by node_id pair when available.
func _get_edge_by_pair(world: Node) -> Dictionary:
	var out: Dictionary = {}
	var q = world.get("query")
	if q == null:
		return out
	var edge_entities: Array = q.with_all([C_PowerEdge]).execute()
	for edge_ent in edge_entities:
		var c_edge: C_PowerEdge = edge_ent.get_component(C_PowerEdge) as C_PowerEdge
		if c_edge == null:
			continue
		var k: String
		if c_edge.node_id_a != "" and c_edge.node_id_b != "":
			k = _edge_key_node_ids(c_edge.node_id_a, c_edge.node_id_b)
		else:
			k = _edge_key_ids(c_edge.entity_id_a, c_edge.entity_id_b)
		out[k] = edge_ent
	return out


## Returns node_ids this node should connect to. Same-entity rule: skip nodes on same entity.
func _compute_connections_for_node(node: Variant, entity: Entity, my_node_id: String, all_nodes: Array, node_by_id: Dictionary, max_connections_override: int = -1) -> Array:
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	if node == null or c_structure == null:
		return []

	var my_max: int = max_connections_override if max_connections_override >= 0 else node.max_connections
	var my_pos: Vector3 = c_structure.structure_node.global_position if c_structure.structure_node else Vector3.ZERO
	var my_entity_id: int = entity.get_instance_id()
	var am_leaf: bool = my_max == 1

	var new_connections: Array = []  # node_ids
	var closest_other_node_id: String = ""
	var closest_dist: float = INF

	for entry in all_nodes:
		var other_ent: Entity = entry.entity
		var other_node: Variant = entry.node
		var other_node_id: String = entry.node_id
		if other_ent == entity:
			continue  # Same-entity rule: nodes on same entity cannot connect
		var other_struct: C_Structure = other_ent.get_component(C_Structure) as C_Structure
		if other_struct == null:
			continue
		if other_struct.structure_node == c_structure.structure_node:
			continue
		if not _is_power_node_enabled(other_node):
			continue

		var other_pos: Vector3 = other_struct.structure_node.global_position if other_struct.structure_node else Vector3.ZERO
		var dist: float = my_pos.distance_to(other_pos)
		if dist > node.max_connection_distance and dist > other_node.max_connection_distance:
			continue

		var exclude1: Node3D = c_structure.structure_node as Node3D
		var exclude2: Node3D = other_struct.structure_node as Node3D
		var los: bool = PowerConstants.has_line_of_sight(my_pos, other_pos, exclude1, exclude2)
		if not los:
			continue

		var other_entity_id: int = other_ent.get_instance_id()
		var already_connected: bool = other_entity_id in node.connected_entity_ids
		var my_can_accept: bool = node.connected_entity_ids.size() < my_max
		var can_form_new: bool = (
			my_can_accept
			and _can_accept_more_connections(other_node)
			and not (my_max == 1 and other_node.max_connections == 1)
		)
		if not already_connected and not can_form_new:
			continue

		if other_node.max_connections == 1:
			var leaf_pos: Vector3 = other_pos
			var my_dist_to_leaf: float = dist
			var am_closest: bool = true
			for cand_entry in all_nodes:
				if cand_entry.entity == other_ent or cand_entry.entity == entity:
					continue
				var cand_node: Variant = cand_entry.node
				var cand_struct: C_Structure = cand_entry.entity.get_component(C_Structure) as C_Structure
				if cand_struct == null or not _is_power_node_enabled(cand_node):
					continue
				var cand_pos: Vector3 = cand_struct.structure_node.global_position if cand_struct.structure_node else Vector3.ZERO
				var cand_dist: float = leaf_pos.distance_to(cand_pos)
				if cand_dist <= other_node.max_connection_distance:
					var c_los: bool = PowerConstants.has_line_of_sight(leaf_pos, cand_pos, exclude2, cand_struct.structure_node as Node3D)
					if c_los:
						var cand_node_id: String = cand_entry.node_id
						if cand_dist < my_dist_to_leaf:
							am_closest = false
							break
						if cand_dist == my_dist_to_leaf and cand_node_id < my_node_id:
							am_closest = false
							break
			if not am_closest:
				continue

		if am_leaf:
			if dist < closest_dist:
				closest_dist = dist
				closest_other_node_id = other_node_id
		elif other_node_id not in new_connections:
			new_connections.append(other_node_id)

	if am_leaf and closest_other_node_id != "":
		new_connections.clear()
		new_connections.append(closest_other_node_id)
	return new_connections


## Full refresh: recompute connections, create/remove edges, rebuild caches.
func refresh_graph(world: Node) -> void:
	if world == null:
		return
	var q = world.get("query")
	if q == null:
		return
	var entities: Array = q.with_any([C_PowerNode, C_ConstructionPowerNode]).with_all([C_Structure]).execute()
	var entity_by_id: Dictionary = {}
	var all_nodes: Array = []
	var node_by_id: Dictionary = {}
	for entity in entities:
		entity_by_id[entity.get_instance_id()] = entity
		for node in _get_all_power_nodes(entity as Entity):
			var nid: String = _make_node_id(entity.get_instance_id(), node)
			all_nodes.append({"entity": entity, "node": node, "node_id": nid})
			node_by_id[nid] = {"entity": entity, "node": node}

	_edge_by_pair = _get_edge_by_pair(world)

	for entry in all_nodes:
		var entity: Entity = entry.entity
		var node: Variant = entry.node
		var my_node_id: String = entry.node_id
		var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
		if c_structure == null:
			continue

		var new_connection_node_ids: Array = _compute_connections_for_node(node, entity, my_node_id, all_nodes, node_by_id)
		var new_connection_entity_ids: Array[int] = []
		for nid in new_connection_node_ids:
			var od = node_by_id.get(nid, {})
			var oe = od.get("entity")
			if oe:
				new_connection_entity_ids.append(oe.get_instance_id())

		var to_add: Array = []
		var to_remove: Array = []
		for nid in new_connection_node_ids:
			var od = node_by_id.get(nid, {})
			var oe = od.get("entity")
			if oe and oe.get_instance_id() not in node.connected_entity_ids:
				to_add.append({"node_id": nid, "entity": oe})
		for eid in node.connected_entity_ids:
			if eid not in new_connection_entity_ids:
				to_remove.append(eid)

		for add in to_add:
			var oe: Entity = add.entity
			var eid: int = oe.get_instance_id()
			if eid not in node.connected_entity_ids:
				node.connected_entity_ids.append(eid)
			var other_node: Variant = null
			for onode in _get_all_power_nodes(oe):
				if _make_node_id(eid, onode) == add.node_id:
					other_node = onode
					break
			if other_node and entity.get_instance_id() not in other_node.connected_entity_ids:
				other_node.connected_entity_ids.append(entity.get_instance_id())
			var struct: Node3D = c_structure.structure_node as Node3D
			if oe and struct:
				var o_struct: C_Structure = oe.get_component(C_Structure) as C_Structure
				if o_struct and o_struct.structure_node:
					_create_edge_entity(world, entity, node, my_node_id, oe, other_node, add.node_id, struct, o_struct.structure_node as Node3D)
		for eid in to_remove:
			var other_entity: Entity = entity_by_id.get(eid) as Entity
			var onid: String = ""
			if other_entity:
				for onode in _get_all_power_nodes(other_entity):
					onid = _make_node_id(eid, onode)
					_remove_edge_entity(world, my_node_id, onid, entity.get_instance_id(), eid)
					onode.connected_entity_ids.erase(entity.get_instance_id())
					break
			else:
				# Other entity already removed - find edge by entity ids and remove
				onid = _find_edge_other_node_id_for_removed_entity(my_node_id, entity.get_instance_id(), eid)
				if onid != "":
					_remove_edge_entity(world, my_node_id, onid, entity.get_instance_id(), eid)
			node.connected_entity_ids.erase(eid)

	_edge_by_pair = _get_edge_by_pair(world)
	_rebuild_caches(all_nodes, entity_by_id, node_by_id, _edge_by_pair)


func _create_edge_entity(world: Node, ent_a: Entity, _node_a: Variant, node_id_a: String, ent_b: Entity, _node_b: Variant, node_id_b: String, struct_a: Node3D, struct_b: Node3D) -> void:
	var id_a: int = ent_a.get_instance_id()
	var id_b: int = ent_b.get_instance_id()
	var key: String = _edge_key_node_ids(node_id_a, node_id_b)
	if _edge_by_pair.has(key):
		return

	var edge_entity: Entity = Entity.new()
	var c_edge: C_PowerEdge = C_PowerEdge.new()
	c_edge.entity_id_a = id_a
	c_edge.entity_id_b = id_b
	c_edge.node_id_a = node_id_a
	c_edge.node_id_b = node_id_b

	var pos_a: Vector3 = PowerEdgeLineNode.get_connection_anchor(struct_a)
	var pos_b: Vector3 = PowerEdgeLineNode.get_connection_anchor(struct_b)

	var line_node: PowerEdgeLineNode = PowerEdgeLineNode.new()
	line_node.edge_entity = edge_entity
	line_node.setup(pos_a, pos_b, struct_a, struct_b)

	var lines_parent: Node3D = GameWorld.power_lines_parent if GameWorld else null
	if lines_parent and is_instance_valid(lines_parent):
		lines_parent.add_child(line_node)

	c_edge.line_node = line_node

	world.add_entity(edge_entity, [c_edge], false)
	var stored: C_PowerEdge = edge_entity.get_component(C_PowerEdge) as C_PowerEdge
	if stored:
		stored.entity_id_a = id_a
		stored.entity_id_b = id_b
		stored.node_id_a = node_id_a
		stored.node_id_b = node_id_b
		stored.line_node = line_node
	_edge_by_pair[key] = edge_entity


func _find_edge_other_node_id_for_removed_entity(my_node_id: String, my_entity_id: int, removed_entity_id: int) -> String:
	for key in _edge_by_pair:
		var edge_ent = _edge_by_pair[key]
		if edge_ent == null or not is_instance_valid(edge_ent):
			continue
		var c_edge: C_PowerEdge = edge_ent.get_component(C_PowerEdge) as C_PowerEdge
		if c_edge == null:
			continue
		var id_a: int = c_edge.entity_id_a
		var id_b: int = c_edge.entity_id_b
		if (id_a == my_entity_id and id_b == removed_entity_id) or (id_a == removed_entity_id and id_b == my_entity_id):
			var nid_a: String = c_edge.node_id_a if c_edge.node_id_a != "" else "%d:PowerNode" % id_a
			var nid_b: String = c_edge.node_id_b if c_edge.node_id_b != "" else "%d:PowerNode" % id_b
			if nid_a == my_node_id:
				return nid_b
			if nid_b == my_node_id:
				return nid_a
	return ""


func _remove_edge_entity(world: Node, node_id_a: String, node_id_b: String, _entity_id_a: int, _entity_id_b: int) -> void:
	var key: String = _edge_key_node_ids(node_id_a, node_id_b)
	var edge_ref: Variant = _edge_by_pair.get(key)
	_edge_by_pair.erase(key)
	_edge_entity_by_pair.erase(key)
	_edge_enabled.erase(key)
	var nd_a: Dictionary = _nodes.get(node_id_a, {})
	var nd_b: Dictionary = _nodes.get(node_id_b, {})
	var struct_a: Node3D = nd_a.get("struct_node") as Node3D
	var struct_b: Node3D = nd_b.get("struct_node") as Node3D
	if struct_a and struct_b and is_instance_valid(struct_a) and is_instance_valid(struct_b):
		_update_edges_struct_map_for_edge_structs(struct_a, struct_b, false)
	if edge_ref == null or not is_instance_valid(edge_ref):
		return
	var edge_entity: Entity = edge_ref as Entity
	var c_edge: C_PowerEdge = edge_entity.get_component(C_PowerEdge) as C_PowerEdge
	if c_edge and c_edge.line_node and is_instance_valid(c_edge.line_node):
		c_edge.line_node.queue_free()
	if world and world.has_method("remove_entity"):
		world.remove_entity(edge_entity)


## Called by observers via call_deferred - accepts instance_id to avoid Entity type conversion issues.
func _deferred_add_node(entity_id: int) -> void:
	var entity: Entity = null
	var from_cache = _entity_by_id.get(entity_id)
	if from_cache != null and is_instance_valid(from_cache):
		entity = from_cache as Entity
	if entity == null and ECS and ECS.world:
		var q = ECS.world.get("query")
		if q:
			for e in q.with_any([C_PowerNode, C_ConstructionPowerNode]).with_all([C_Structure]).execute():
				if is_instance_valid(e) and e.get_instance_id() == entity_id:
					entity = e as Entity
					break
	if entity != null and is_instance_valid(entity):
		add_node(entity)


## Called by observers via call_deferred - accepts instance_id to avoid Entity type conversion issues.
func _deferred_remove_node(entity_id: int) -> void:
	var entity: Entity = null
	var from_cache = _entity_by_id.get(entity_id)
	if from_cache != null and is_instance_valid(from_cache):
		entity = from_cache as Entity
	if entity == null and ECS and ECS.world:
		var q = ECS.world.get("query")
		if q:
			for e in q.with_all([C_Structure]).execute():
				if is_instance_valid(e) and e.get_instance_id() == entity_id:
					entity = e as Entity
					break
	if entity != null and is_instance_valid(entity):
		remove_node(entity)
	else:
		request_refresh()


## Called by observers via call_deferred - accepts instance_id to avoid Entity type conversion issues.
func _deferred_node_enabled_changed(entity_id: int) -> void:
	var entity: Entity = null
	var from_cache = _entity_by_id.get(entity_id)
	if from_cache != null and is_instance_valid(from_cache):
		entity = from_cache as Entity
	if entity == null and ECS and ECS.world:
		var q = ECS.world.get("query")
		if q:
			for e in q.with_any([C_PowerNode, C_ConstructionPowerNode]).with_all([C_Structure]).execute():
				if is_instance_valid(e) and e.get_instance_id() == entity_id:
					entity = e as Entity
					break
	if entity != null and is_instance_valid(entity):
		node_enabled_changed(entity)


## Called by observers via call_deferred - accepts instance_id to avoid Entity type conversion issues.
func _deferred_refresh_entity_cache(entity_id: int) -> void:
	var entity: Entity = null
	var from_cache = _entity_by_id.get(entity_id)
	if from_cache != null and is_instance_valid(from_cache):
		entity = from_cache as Entity
	if entity == null and ECS and ECS.world:
		var q = ECS.world.get("query")
		if q:
			for e in q.with_all([C_Structure]).execute():
				if is_instance_valid(e) and e.get_instance_id() == entity_id:
					entity = e as Entity
					break
	if entity != null and is_instance_valid(entity):
		refresh_entity_cache(entity)


## Called by observers via call_deferred - accepts instance_id to avoid Entity type conversion issues.
func _deferred_edge_blocked_changed(edge_entity_id: int) -> void:
	var edge_entity: Entity = null
	if ECS and ECS.world:
		var q = ECS.world.get("query")
		if q:
			for e in q.with_all([C_PowerEdge]).execute():
				if is_instance_valid(e) and e.get_instance_id() == edge_entity_id:
					edge_entity = e as Entity
					break
	if edge_entity != null and is_instance_valid(edge_entity):
		edge_blocked_changed(edge_entity)


## Incremental: add power node(s) on entity. Triggers full refresh for composite correctness.
func add_node(entity: Entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	request_refresh()


## Incremental: remove power node(s) on entity. Triggers full refresh for composite correctness.
func remove_node(entity: Entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	request_refresh()


## Incremental: node is_enabled changed; update incident edge enabled state.
func node_enabled_changed(entity: Entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	request_refresh()


## Incremental: edge is_blocked changed; update that edge's enabled state.
func edge_blocked_changed(edge_entity: Entity) -> void:
	if edge_entity == null or not is_instance_valid(edge_entity):
		return
	var c_edge: C_PowerEdge = edge_entity.get_component(C_PowerEdge) as C_PowerEdge
	if c_edge == null:
		return
	var nid_a: String = c_edge.node_id_a if c_edge.node_id_a != "" else "%d:PowerNode" % c_edge.entity_id_a
	var nid_b: String = c_edge.node_id_b if c_edge.node_id_b != "" else "%d:PowerNode" % c_edge.entity_id_b
	var k: String = _edge_key_node_ids(nid_a, nid_b)
	_update_edge_enabled_for_pair_by_key(k, c_edge, nid_a, nid_b, edge_entity)
	var nd_a: Dictionary = _nodes.get(nid_a, {})
	var nd_b: Dictionary = _nodes.get(nid_b, {})
	var struct_a: Node3D = nd_a.get("struct_node") as Node3D
	var struct_b: Node3D = nd_b.get("struct_node") as Node3D
	if struct_a and struct_b:
		_update_edges_struct_map_for_edge_structs(struct_a, struct_b, _edge_enabled.get(k, false))


## Incremental: entity switched from C_ConstructionPowerNode to C_PowerNode; update caches.
func refresh_entity_cache(entity: Entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	request_refresh()


func _update_edge_enabled_for_pair(node_id_a: String, node_id_b: String) -> void:
	var k: String = _edge_key_node_ids(node_id_a, node_id_b)
	var node_a: Dictionary = _nodes.get(node_id_a, {})
	var node_b: Dictionary = _nodes.get(node_id_b, {})
	var struct_a: Node3D = node_a.get("struct_node") as Node3D
	var struct_b: Node3D = node_b.get("struct_node") as Node3D
	var both_enabled: bool = node_a.get("is_enabled", false) and node_b.get("is_enabled", false)
	var los: bool = true
	if struct_a and struct_b and is_instance_valid(struct_a) and is_instance_valid(struct_b):
		los = PowerConstants.has_line_of_sight(struct_a.global_position, struct_b.global_position, struct_a, struct_b)
	var blocked: bool = false
	var edge_ent = _edge_entity_by_pair.get(k)
	if edge_ent == null:
		edge_ent = _edge_by_pair.get(k)
	if edge_ent != null and is_instance_valid(edge_ent):
		var c_edge: C_PowerEdge = edge_ent.get_component(C_PowerEdge) as C_PowerEdge
		if c_edge:
			blocked = c_edge.is_blocked
		if not _edge_entity_by_pair.has(k):
			_edge_entity_by_pair[k] = edge_ent
	_edge_enabled[k] = not blocked and both_enabled and los


func _update_edge_enabled_for_pair_by_key(k: String, c_edge: C_PowerEdge, node_id_a: String, node_id_b: String, edge_entity: Entity) -> void:
	var node_a: Dictionary = _nodes.get(node_id_a, {})
	var node_b: Dictionary = _nodes.get(node_id_b, {})
	var struct_a: Node3D = node_a.get("struct_node") as Node3D
	var struct_b: Node3D = node_b.get("struct_node") as Node3D
	var both_enabled: bool = node_a.get("is_enabled", false) and node_b.get("is_enabled", false)
	var los: bool = true
	if struct_a and struct_b and is_instance_valid(struct_a) and is_instance_valid(struct_b):
		los = PowerConstants.has_line_of_sight(struct_a.global_position, struct_b.global_position, struct_a, struct_b)
	_edge_enabled[k] = not c_edge.is_blocked and both_enabled and los
	if not _edge_entity_by_pair.has(k):
		_edge_entity_by_pair[k] = edge_entity


func _update_edges_struct_map_for_edge_structs(struct_a: Node3D, struct_b: Node3D, enabled: bool) -> void:
	if struct_a == null or struct_b == null or not is_instance_valid(struct_a) or not is_instance_valid(struct_b):
		return
	if not _edges_struct_map.has(struct_a):
		_edges_struct_map[struct_a] = {}
	if not _edges_struct_map.has(struct_b):
		_edges_struct_map[struct_b] = {}
	if enabled:
		_edges_struct_map[struct_a][struct_b] = {}
		_edges_struct_map[struct_b][struct_a] = {}
	else:
		_edges_struct_map[struct_a].erase(struct_b)
		_edges_struct_map[struct_b].erase(struct_a)
		if _edges_struct_map[struct_a].is_empty():
			_edges_struct_map.erase(struct_a)
		if _edges_struct_map[struct_b].is_empty():
			_edges_struct_map.erase(struct_b)


## Rebuilds all caches from current nodes and edges (internal, used by refresh_graph).
func _rebuild_caches(all_nodes: Array, entity_by_id: Dictionary, node_by_id: Dictionary, edge_by_pair: Dictionary) -> void:
	_nodes.clear()
	_node_id_to_entity_id.clear()
	_entity_by_id.clear()
	_struct_id_to_entity_id.clear()
	_edge_enabled.clear()
	_edge_entity_by_pair.clear()
	_edges_struct_map.clear()

	for entry in all_nodes:
		var entity: Entity = entry.entity
		var node: Variant = entry.node
		var node_id: String = entry.node_id
		var entity_id: int = entity.get_instance_id()
		_entity_by_id[entity_id] = entity
		_node_id_to_entity_id[node_id] = entity_id

		var c_struct: C_Structure = entity.get_component(C_Structure) as C_Structure
		var c_const: C_Construction = entity.get_component(C_Construction) as C_Construction
		if c_struct == null:
			continue

		var struct_node: Node3D = c_struct.structure_node as Node3D
		var struct_id: int = struct_node.get_instance_id() if struct_node and is_instance_valid(struct_node) else 0
		var c_src: C_PowerSource = entity.get_component(C_PowerSource) as C_PowerSource
		var c_gen: C_PowerGenerator = entity.get_component(C_PowerGenerator) as C_PowerGenerator
		var built: bool = c_const == null or c_const.is_built
		var is_src: bool = c_src != null and built
		var has_gen: bool = c_gen != null and built

		_nodes[node_id] = {
			"entity_id": entity_id,
			"neighbor_ids": [],  # Filled from edges below
			"is_source": is_src,
			"is_enabled": _is_power_node_enabled(node),
			"struct_node": struct_node,
			"struct_id": struct_id,
			"has_user": entity.get_component(C_PowerUser) != null,
			"has_generator": has_gen
		}
		if struct_id != 0:
			_struct_id_to_entity_id[struct_id] = entity_id
		if struct_node and struct_node.get_parent() and struct_node.get_parent().get("building_type") != null:
			var parent_id: int = struct_node.get_parent().get_instance_id()
			_struct_id_to_entity_id[parent_id] = entity_id

	for key in edge_by_pair:
		var edge_ent: Entity = edge_by_pair[key] as Entity
		if edge_ent == null:
			continue
		var c_edge: C_PowerEdge = edge_ent.get_component(C_PowerEdge) as C_PowerEdge
		if c_edge == null:
			continue
		var nid_a: String = c_edge.node_id_a if c_edge.node_id_a != "" else "%d:PowerNode" % c_edge.entity_id_a
		var nid_b: String = c_edge.node_id_b if c_edge.node_id_b != "" else "%d:PowerNode" % c_edge.entity_id_b
		var k: String = _edge_key_node_ids(nid_a, nid_b)
		_edge_entity_by_pair[k] = edge_ent
		if _nodes.has(nid_a) and nid_b not in _nodes[nid_a].get("neighbor_ids", []):
			_nodes[nid_a].neighbor_ids.append(nid_b)
		if _nodes.has(nid_b) and nid_a not in _nodes[nid_b].get("neighbor_ids", []):
			_nodes[nid_b].neighbor_ids.append(nid_a)

		var node_a: Dictionary = _nodes.get(nid_a, {})
		var node_b: Dictionary = _nodes.get(nid_b, {})
		var blocked: bool = c_edge.is_blocked
		var both_enabled: bool = node_a.get("is_enabled", false) and node_b.get("is_enabled", false)
		var struct_a: Node3D = node_a.get("struct_node") as Node3D
		var struct_b: Node3D = node_b.get("struct_node") as Node3D
		var los: bool = true
		if struct_a and struct_b and is_instance_valid(struct_a) and is_instance_valid(struct_b):
			los = PowerConstants.has_line_of_sight(struct_a.global_position, struct_b.global_position, struct_a, struct_b)
		_edge_enabled[k] = not blocked and both_enabled and los

	for node_id in _nodes:
		var nd: Dictionary = _nodes[node_id]
		for nid in nd.get("neighbor_ids", []):
			var k: String = _edge_key_node_ids(node_id, nid)
			if _edge_enabled.has(k):
				continue
			var nnd: Dictionary = _nodes.get(nid, {})
			if not nd.get("is_enabled", false) or not nnd.get("is_enabled", false):
				continue
			var struct_a: Node3D = nd.get("struct_node") as Node3D
			var struct_b: Node3D = nnd.get("struct_node") as Node3D
			var los: bool = true
			if struct_a and struct_b and is_instance_valid(struct_a) and is_instance_valid(struct_b):
				los = PowerConstants.has_line_of_sight(struct_a.global_position, struct_b.global_position, struct_a, struct_b)
			_edge_enabled[k] = los

	for node_id in _nodes:
		var nd: Dictionary = _nodes[node_id]
		var struct_a: Node3D = nd.get("struct_node") as Node3D
		if struct_a == null or not is_instance_valid(struct_a):
			continue
		if not _edges_struct_map.has(struct_a):
			_edges_struct_map[struct_a] = {}
		for nid in nd.get("neighbor_ids", []):
			var k: String = _edge_key_node_ids(node_id, nid)
			if not _edge_enabled.get(k, false):
				continue
			var nnd: Dictionary = _nodes.get(nid, {})
			var struct_b: Node3D = nnd.get("struct_node") as Node3D
			if struct_b and is_instance_valid(struct_b):
				_edges_struct_map[struct_a][struct_b] = {}


## Draw power from nearest sources. Returns total drawn. Caller adds to C_PowerUser.power_buffer.
## Sets is_flashing on C_PowerEdge for edges along the power flow path so lines light up.
func draw_power(entity_id: int, amount: float) -> float:
	if entity_id <= 0 or amount <= 0:
		return 0.0
	var start_node_ids: Array = _get_node_ids_for_entity(entity_id)
	if start_node_ids.is_empty():
		return 0.0

	var queue: Array = start_node_ids.duplicate()
	var visited: Dictionary = {}
	for nid in start_node_ids:
		visited[nid] = true
	var path_map: Dictionary = {}
	var total_drawn: float = 0.0
	var remaining: float = amount
	var sources_drawn_from: Array = []

	while not queue.is_empty() and remaining > 0:
		var cid: String = queue.pop_front()
		var cnd: Dictionary = _nodes.get(cid, {})
		if cnd.is_empty():
			continue

		if cnd.get("is_source", false):
			var eid: int = cnd.get("entity_id", 0)
			var ent = _entity_by_id.get(eid)
			if ent != null and is_instance_valid(ent):
				ent = ent as Entity
				var c_src: C_PowerSource = ent.get_component(C_PowerSource) as C_PowerSource
				if c_src:
					var draw_amount: float = minf(remaining, c_src.current_storage)
					if draw_amount > 0:
						c_src.current_storage -= draw_amount
						total_drawn += draw_amount
						remaining -= draw_amount
						sources_drawn_from.append(cid)
			if remaining <= 0:
				break

		for nid in cnd.get("neighbor_ids", []):
			if visited.get(nid, false):
				continue
			var k: String = _edge_key_node_ids(cid, nid)
			if not _edge_enabled.get(k, false):
				continue
			var nnd: Dictionary = _nodes.get(nid, {})
			if not nnd.get("is_enabled", false):
				continue
			visited[nid] = true
			path_map[nid] = cid
			queue.append(nid)

	if total_drawn > 0:
		_flash_edges_along_paths(start_node_ids[0], sources_drawn_from, path_map)

	return total_drawn


func _flash_edges_along_paths(start_node_id: String, source_ids: Array, path_map: Dictionary) -> void:
	var edges_to_flash: Dictionary = {}
	for src_id in source_ids:
		var node_id: String = src_id
		while path_map.has(node_id):
			var prev_id: String = path_map[node_id]
			var k: String = _edge_key_node_ids(prev_id, node_id)
			edges_to_flash[k] = true
			node_id = prev_id
	for k in edges_to_flash:
		var edge_ent = _edge_entity_by_pair.get(k)
		if edge_ent != null and is_instance_valid(edge_ent):
			var c_edge: C_PowerEdge = edge_ent.get_component(C_PowerEdge) as C_PowerEdge
			if c_edge:
				c_edge.is_flashing = true


## Flash edges along a path of entities (for generator excess distribution).
## Path is Array of Entity from consumer toward source.
func flash_edges_along_path(path: Array) -> void:
	for i in range(path.size() - 1):
		var ent_a = path[i]
		var ent_b = path[i + 1]
		if ent_a == null or ent_b == null or not is_instance_valid(ent_a) or not is_instance_valid(ent_b):
			continue
		var id_a: int = ent_a.get_instance_id()
		var id_b: int = ent_b.get_instance_id()
		for nid_a in _get_node_ids_for_entity(id_a):
			for nid_b in _get_node_ids_for_entity(id_b):
				var k: String = _edge_key_node_ids(nid_a, nid_b)
				var edge_ent = _edge_entity_by_pair.get(k)
				if edge_ent != null and is_instance_valid(edge_ent):
					var c_edge: C_PowerEdge = edge_ent.get_component(C_PowerEdge) as C_PowerEdge
					if c_edge:
						c_edge.is_flashing = true
						break


## Wrapper: accepts Entity, adds drawn amount to buffer. For mining, construction, turrets, tests.
func draw_power_for_user_entity(user_entity: Entity, amount: float) -> float:
	if user_entity == null:
		return 0.0
	var c_power_user: C_PowerUser = user_entity.get_component(C_PowerUser) as C_PowerUser
	if c_power_user == null:
		return 0.0
	var drawn: float = draw_power(user_entity.get_instance_id(), amount)
	c_power_user.power_buffer += drawn
	return drawn


## BFS to find nearest source. Returns { "source_entity": Entity, "path": Array[Entity] }.
func find_nearest_source_entity(entity: Entity, exclude_start: bool = false) -> Dictionary:
	if entity == null or not is_instance_valid(entity):
		return {"source_entity": null, "path": []}
	var entity_id: int = entity.get_instance_id()
	return find_nearest_source_entity_by_id(entity_id, exclude_start)


func find_nearest_source_entity_by_id(entity_id: int, exclude_start: bool = false) -> Dictionary:
	if entity_id <= 0:
		return {"source_entity": null, "path": []}

	var start_node_ids: Array = _get_node_ids_for_entity(entity_id)
	if start_node_ids.is_empty():
		return {"source_entity": null, "path": []}

	var queue: Array = start_node_ids.duplicate()
	var visited: Dictionary = {}
	for nid in start_node_ids:
		visited[nid] = true
	var path_map: Dictionary = {}

	while not queue.is_empty():
		var cid: String = queue.pop_front()
		var cnd: Dictionary = _nodes.get(cid, {})
		if cnd.is_empty():
			continue

		var eid: int = cnd.get("entity_id", 0)
		if cnd.get("is_source", false):
			if not (exclude_start and eid == entity_id):
				var path_entities: Array = []
				var node_id: String = cid
				var prev_eid: int = -1
				while true:
					var nent = _nodes.get(node_id, {})
					var neid: int = nent.get("entity_id", 0)
					if neid != prev_eid:
						var ent = _entity_by_id.get(neid)
						if ent != null and is_instance_valid(ent):
							path_entities.insert(0, ent as Entity)
						prev_eid = neid
					if not path_map.has(node_id):
						break
					node_id = path_map[node_id]
				var start_ent = _entity_by_id.get(entity_id)
				if start_ent != null and is_instance_valid(start_ent) and (path_entities.is_empty() or path_entities[0] != start_ent):
					path_entities.insert(0, start_ent)
				var src_ent = _entity_by_id.get(eid)
				var src_entity: Entity = (src_ent as Entity) if (src_ent != null and is_instance_valid(src_ent)) else null
				return {"source_entity": src_entity, "path": path_entities}

		for nid in cnd.get("neighbor_ids", []):
			if visited.get(nid, false):
				continue
			var k: String = _edge_key_node_ids(cid, nid)
			if not _edge_enabled.get(k, false):
				continue
			var nnd: Dictionary = _nodes.get(nid, {})
			if not nnd.get("is_enabled", false):
				continue
			visited[nid] = true
			queue.append(nid)
			path_map[nid] = cid

	return {"source_entity": null, "path": []}


func find_subgraph_for_entity(entity: Entity) -> PowerSubgraph:
	if entity == null or not is_instance_valid(entity):
		return null
	var c_struct: C_Structure = entity.get_component(C_Structure) as C_Structure
	if c_struct == null or c_struct.structure_node == null:
		return null
	return find_subgraph_for_node(c_struct.structure_node as Node3D)


func find_subgraph_for_node(struct: Node3D) -> PowerSubgraph:
	if struct == null or not is_instance_valid(struct):
		return null
	var resolved: Node3D = struct
	if struct.get_parent() and struct.get_parent().get("building_type") != null:
		resolved = struct.get_parent() as Node3D
	var entity_id: int = struct_to_entity_id(resolved)
	if entity_id <= 0:
		return null

	var start_node_ids: Array = _get_node_ids_for_entity(entity_id)
	if start_node_ids.is_empty():
		return null

	var visited: Dictionary = {}
	var subgraph_entity_ids: Array = []
	for nid in start_node_ids:
		_find_connected_entity_ids_from_node(nid, visited, subgraph_entity_ids)

	var sg: PowerSubgraph = PowerSubgraph.new()
	for eid in subgraph_entity_ids:
		var ent = _entity_by_id.get(eid)
		if ent == null or not is_instance_valid(ent):
			continue
		ent = ent as Entity
		sg.nodes.append(ent)
		var node_ids_for_ent: Array = _get_node_ids_for_entity(eid)
		var nd: Dictionary = _nodes.get(node_ids_for_ent[0], {}) if node_ids_for_ent.size() > 0 else {}
		if nd.get("is_source", false):
			sg.sources.append(ent)
		if nd.get("has_user", false):
			sg.users.append(ent)
		if nd.get("has_generator", false):
			sg.generators.append(ent)
	return sg


func _find_connected_entity_ids_from_node(current_node_id: String, visited: Dictionary, out: Array) -> void:
	if visited.get(current_node_id, false):
		return
	visited[current_node_id] = true
	var nd: Dictionary = _nodes.get(current_node_id, {})
	var eid: int = nd.get("entity_id", 0)
	if eid > 0 and eid not in out:
		out.append(eid)
	if not nd.get("is_enabled", false):
		return
	for nid in nd.get("neighbor_ids", []):
		if visited.get(nid, false):
			continue
		var k: String = _edge_key_node_ids(current_node_id, nid)
		if not _edge_enabled.get(k, false):
			continue
		var nnd: Dictionary = _nodes.get(nid, {})
		if nnd.get("is_enabled", false):
			_find_connected_entity_ids_from_node(nid, visited, out)


func get_edges() -> Dictionary:
	return _edges_struct_map.duplicate(true)


func is_edge_enabled(node1: Node3D, node2: Node3D) -> bool:
	var id_a: int = struct_to_entity_id(node1)
	var id_b: int = struct_to_entity_id(node2)
	if id_a <= 0 or id_b <= 0:
		return false
	for nid_a in _get_node_ids_for_entity(id_a):
		for nid_b in _get_node_ids_for_entity(id_b):
			if _edge_enabled.get(_edge_key_node_ids(nid_a, nid_b), false):
				return true
	return false


func is_edge_enabled_entity_ids(id_a: int, id_b: int) -> bool:
	for nid_a in _get_node_ids_for_entity(id_a):
		for nid_b in _get_node_ids_for_entity(id_b):
			if _edge_enabled.get(_edge_key_node_ids(nid_a, nid_b), false):
				return true
	return false


func get_edge_entity(id_a: int, id_b: int) -> Variant:
	for nid_a in _get_node_ids_for_entity(id_a):
		for nid_b in _get_node_ids_for_entity(id_b):
			var edge = _edge_entity_by_pair.get(_edge_key_node_ids(nid_a, nid_b))
			if edge != null:
				return edge
	return null


func struct_to_entity_id(struct: Node3D) -> int:
	if struct == null or not is_instance_valid(struct):
		return 0
	return _struct_id_to_entity_id.get(struct.get_instance_id(), 0)


func get_power_capacity() -> float:
	var total: float = 0.0
	var counted: Dictionary = {}
	for node_id in _nodes:
		var nd: Dictionary = _nodes[node_id]
		if not nd.get("is_source", false):
			continue
		var eid: int = nd.get("entity_id", 0)
		if counted.get(eid, false):
			continue
		counted[eid] = true
		var ent = _entity_by_id.get(eid)
		if ent == null or not is_instance_valid(ent):
			continue
		ent = ent as Entity
		var c: C_PowerSource = ent.get_component(C_PowerSource) as C_PowerSource
		if c:
			total += c.max_storage
	return total


func get_power_current() -> float:
	var total: float = 0.0
	var counted: Dictionary = {}
	for node_id in _nodes:
		var nd: Dictionary = _nodes[node_id]
		if not nd.get("is_source", false):
			continue
		var eid: int = nd.get("entity_id", 0)
		if counted.get(eid, false):
			continue
		counted[eid] = true
		var ent = _entity_by_id.get(eid)
		if ent == null or not is_instance_valid(ent):
			continue
		ent = ent as Entity
		var c: C_PowerSource = ent.get_component(C_PowerSource) as C_PowerSource
		if c:
			total += c.current_storage
	return total


func set_node_enabled(struct: Node3D, enabled: bool) -> void:
	if struct == null:
		return
	var entity_id: int = struct_to_entity_id(struct)
	if entity_id <= 0:
		return
	var ent: Entity = _entity_by_id.get(entity_id) as Entity
	if ent and is_instance_valid(ent):
		for node in _get_all_power_nodes(ent):
			node.is_enabled = enabled
	# Observer will trigger request_refresh; caches rebuilt then


func is_entity_powered(entity: Entity) -> bool:
	var c_src = entity.get_component(C_PowerSource)
	var c_gen = entity.get_component(C_PowerGenerator)
	if c_src != null or c_gen != null:
		return true
	var c_power_user: C_PowerUser = entity.get_component(C_PowerUser) as C_PowerUser
	if c_power_user:
		return c_power_user.has_power()
	var power_nodes: Array = _get_all_power_nodes(entity)
	if power_nodes.is_empty():
		return true
	var any_enabled: bool = false
	for node in power_nodes:
		if _is_power_node_enabled(node):
			any_enabled = true
			break
	if not any_enabled:
		return false
	var sg: PowerSubgraph = find_subgraph_for_entity(entity)
	if sg == null:
		return false
	return float(sg.power_current) > 0.0


## Pure logic - no graph needed.
static func can_power_node_accept_more_connections(c_power_node: C_PowerNode) -> bool:
	if c_power_node == null:
		return false
	return c_power_node.connected_entity_ids.size() < c_power_node.max_connections


## Pure logic - reads from entity. True if any power node can accept more.
static func can_entity_accept_more_connections(entity: Entity) -> bool:
	for node in _get_all_power_nodes(entity):
		if _can_accept_more_connections(node):
			return true
	return false


## For placement preview: use built max_connections so under-construction relays show as multi-connection targets.
static func can_entity_accept_more_connections_for_preview(entity: Entity) -> bool:
	var max_conn: int = _get_preview_max_connections_for_entity(entity)
	if max_conn <= 0:
		return false
	for node in _get_all_power_nodes(entity):
		if node.connected_entity_ids.size() < max_conn:
			return true
	return false


static func is_entity_valid_connection_target(entity: Entity) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	var power_nodes: Array = _get_all_power_nodes(entity)
	if power_nodes.is_empty():
		return false
	var c_construction: C_Construction = entity.get_component(C_Construction) as C_Construction
	var is_under_construction: bool = c_construction != null and not c_construction.is_built
	if is_under_construction:
		return true
	for node in power_nodes:
		if node is C_PowerNode and (node as C_PowerNode).node_type == C_PowerNode.NodeType.LEAF:
			continue
		if _can_accept_more_connections(node):
			return true
	return false


static func get_connection_status(c_power_node: C_PowerNode) -> String:
	if c_power_node == null:
		return "0/0"
	return "%d/%d" % [c_power_node.connected_entity_ids.size(), c_power_node.max_connections]

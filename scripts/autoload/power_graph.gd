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


# Graph caches - rebuilt each sync
var _nodes: Dictionary = {}  # entity_id -> {neighbor_ids, is_source, is_enabled, struct_node, has_user, has_generator}
var _entity_by_id: Dictionary = {}
var _struct_id_to_entity_id: Dictionary = {}  # struct instance_id -> entity_id
var _edge_enabled: Dictionary = {}  # "lo_hi" -> bool
var _edge_entity_by_pair: Dictionary = {}  # "lo_hi" -> Entity
var _edges_struct_map: Dictionary = {}  # struct_a -> {struct_b -> {}}


func _edge_key(id_a: int, id_b: int) -> String:
	var lo: int = mini(id_a, id_b)
	var hi: int = maxi(id_a, id_b)
	return "%d_%d" % [lo, hi]


func _edge_key_ids(id_a: int, id_b: int) -> String:
	var lo: int = mini(id_a, id_b)
	var hi: int = maxi(id_a, id_b)
	return "e_%d_%d" % [lo, hi]


## Returns the power node component for this entity. Graph uses C_PowerNode only.
## C_ConstructionPowerNode overrides max_connections to 1 during construction; graph does not care.
static func _get_active_power_node(entity: Entity) -> Variant:
	return entity.get_component(C_PowerNode) as C_PowerNode


## Whether the power node is enabled (participates in connections).
static func _is_active_node_enabled(active_node: Variant) -> bool:
	if active_node is C_PowerNode:
		return (active_node as C_PowerNode).is_enabled
	return false


## For placement preview: get built max_connections. Under construction uses saved_max_connections.
static func _get_preview_max_connections_for_entity(entity: Entity) -> int:
	var c_build: Variant = entity.get_component(_C_ConstructionPowerNode)
	if c_build and c_build.get("saved_max_connections") != null:
		return int(c_build.saved_max_connections)
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node:
		return c_power_node.max_connections
	return 0


## Whether the node can accept more connections. Works with C_PowerNode or C_ConstructionPowerNode.
static func _can_accept_more_connections(active_node: Variant) -> bool:
	if active_node == null:
		return false
	return active_node.connected_entity_ids.size() < active_node.max_connections


## Returns entity_ids that would connect if this node had max_connections_override capacity.
## Excludes connections already in C_PowerNode.connected_entity_ids (preview shows additional only).
func compute_preview_connections(entity: Entity, max_connections_override: int) -> Array[int]:
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node == null or max_connections_override <= 0:
		return []
	var world: Node = ECS.world if ECS else null
	if world == null:
		return []
	var q = world.get("query")
	if q == null:
		return []
	var entities: Array = q.with_all([C_Structure, C_PowerNode]).execute()
	var entity_by_id: Dictionary = {}
	for e in entities:
		entity_by_id[e.get_instance_id()] = e
	var all_potential: Array = _compute_connections_for_entity(entity, entities, entity_by_id, max_connections_override)
	var result: Array[int] = []
	for id in all_potential:
		if id not in c_power_node.connected_entity_ids:
			result.append(id)
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


## Query C_PowerEdge entities and build edge_by_pair for cache rebuild.
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
		var k: String = _edge_key_ids(c_edge.entity_id_a, c_edge.entity_id_b)
		out[k] = edge_ent
	return out


## Returns entity_ids this entity should connect to. Uses bidirectional range, LOS, leaf rules.
## max_connections_override: if >= 0, use instead of node's max_connections (for preview computation).
func _compute_connections_for_entity(entity: Entity, entities: Array, entity_by_id: Dictionary, max_connections_override: int = -1) -> Array:
	var c_power_node: Variant = _get_active_power_node(entity)
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	if c_power_node == null or c_structure == null:
		return []

	var my_max: int = max_connections_override if max_connections_override >= 0 else c_power_node.max_connections
	var my_pos: Vector3 = c_structure.structure_node.global_position if c_structure.structure_node else Vector3.ZERO
	var my_id: int = entity.get_instance_id()
	var am_leaf: bool = my_max == 1

	var new_connections: Array[int] = []
	var closest_other_id: int = -1
	var closest_dist: float = INF
	for other in entities:
		if other == entity:
			continue
		var other_node: Variant = _get_active_power_node(other)
		var other_struct: C_Structure = other.get_component(C_Structure) as C_Structure
		if other_node == null or other_struct == null:
			continue
		if other_struct.structure_node == c_structure.structure_node:
			continue
		if not _is_active_node_enabled(other_node):
			continue

		var other_pos: Vector3 = other_struct.structure_node.global_position if other_struct.structure_node else Vector3.ZERO
		var dist: float = my_pos.distance_to(other_pos)
		# Bidirectional range: connect if either node can reach the other
		if dist > c_power_node.max_connection_distance and dist > other_node.max_connection_distance:
			continue

		var exclude1: Node3D = c_structure.structure_node as Node3D
		var exclude2: Node3D = other_struct.structure_node as Node3D
		var los: bool = PowerConstants.has_line_of_sight(my_pos, other_pos, exclude1, exclude2)
		if not los:
			continue

		var other_id: int = other.get_instance_id()
		var already_connected: bool = other_id in c_power_node.connected_entity_ids
		var my_can_accept: bool = c_power_node.connected_entity_ids.size() < my_max
		var can_form_new: bool = (
			my_can_accept
			and _can_accept_more_connections(other_node)
			and not (my_max == 1 and other_node.max_connections == 1)
		)
		if not already_connected and not can_form_new:
			continue

		if other_node.max_connections == 1:
			# Leaf can only have one connection - only the single closest node may connect.
			# Tie-break by entity id when distances are equal for deterministic behavior.
			var leaf_pos: Vector3 = other_pos
			var my_dist_to_leaf: float = dist
			var am_closest: bool = true
			for candidate in entities:
				if candidate == other or candidate == entity:
					continue
				var cand_node: Variant = _get_active_power_node(candidate)
				var cand_struct: C_Structure = candidate.get_component(C_Structure) as C_Structure
				if cand_node == null or cand_struct == null or not _is_active_node_enabled(cand_node):
					continue
				var cand_pos: Vector3 = cand_struct.structure_node.global_position if cand_struct.structure_node else Vector3.ZERO
				var cand_dist: float = leaf_pos.distance_to(cand_pos)
				if cand_dist <= other_node.max_connection_distance:
					var c_los: bool = PowerConstants.has_line_of_sight(leaf_pos, cand_pos, exclude2, cand_struct.structure_node as Node3D)
					if c_los:
						var cand_id: int = candidate.get_instance_id()
						if cand_dist < my_dist_to_leaf:
							am_closest = false
							break
						if cand_dist == my_dist_to_leaf and cand_id < my_id:
							am_closest = false
							break
			if not am_closest:
				continue

		# When we are a leaf (max_connections=1), only keep the single closest
		if am_leaf:
			if dist < closest_dist:
				closest_dist = dist
				closest_other_id = other_id
		elif other_id not in new_connections:
			new_connections.append(other_id)

	if am_leaf and closest_other_id >= 0:
		new_connections.clear()
		new_connections.append(closest_other_id)
	return new_connections


## Full refresh: recompute connections, create/remove edges, rebuild caches.
func refresh_graph(world: Node) -> void:
	if world == null:
		return
	var q = world.get("query")
	if q == null:
		return
	var entities: Array = q.with_all([C_Structure, C_PowerNode]).execute()
	var entity_by_id: Dictionary = {}
	for entity in entities:
		entity_by_id[entity.get_instance_id()] = entity

	_edge_by_pair = _get_edge_by_pair(world)

	for entity in entities:
		var c_power_node: Variant = _get_active_power_node(entity)
		var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
		if c_power_node == null or c_structure == null:
			continue

		var my_id: int = entity.get_instance_id()
		var new_connections: Array = _compute_connections_for_entity(entity, entities, entity_by_id)

		var to_add: Array[int] = []
		var to_remove: Array[int] = []
		for id in new_connections:
			if id not in c_power_node.connected_entity_ids:
				to_add.append(id)
		for id in c_power_node.connected_entity_ids:
			if id not in new_connections:
				to_remove.append(id)

		for id in to_add:
			if id not in c_power_node.connected_entity_ids:
				c_power_node.connected_entity_ids.append(id)
			var other_entity: Entity = entity_by_id.get(id) as Entity
			if other_entity:
				var other_node: Variant = _get_active_power_node(other_entity)
				if other_node and my_id not in other_node.connected_entity_ids:
					other_node.connected_entity_ids.append(my_id)
			var struct: Node3D = c_structure.structure_node as Node3D
			var other_ent: Entity = entity_by_id.get(id) as Entity
			if other_ent and struct:
				var o_struct: C_Structure = other_ent.get_component(C_Structure) as C_Structure
				if o_struct and o_struct.structure_node:
					_create_edge_entity(world, entity, other_ent, struct, o_struct.structure_node as Node3D)
		for id in to_remove:
			_remove_edge_entity(world, my_id, id)
			var other_entity: Entity = entity_by_id.get(id) as Entity
			c_power_node.connected_entity_ids.erase(id)
			if other_entity:
				var other_node: Variant = _get_active_power_node(other_entity)
				if other_node:
					other_node.connected_entity_ids.erase(my_id)

	_edge_by_pair = _get_edge_by_pair(world)
	_rebuild_caches(entities, entity_by_id, _edge_by_pair)


func _create_edge_entity(world: Node, ent_a: Entity, ent_b: Entity, struct_a: Node3D, struct_b: Node3D) -> void:
	var id_a: int = ent_a.get_instance_id()
	var id_b: int = ent_b.get_instance_id()
	var key: String = _edge_key_ids(id_a, id_b)
	if _edge_by_pair.has(key):
		return

	var edge_entity: Entity = Entity.new()
	var c_edge: C_PowerEdge = C_PowerEdge.new()
	c_edge.entity_id_a = id_a
	c_edge.entity_id_b = id_b

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
	# Re-set refs: add_entity duplicates components, which can null Node refs and sometimes ints
	var stored: C_PowerEdge = edge_entity.get_component(C_PowerEdge) as C_PowerEdge
	if stored:
		stored.entity_id_a = id_a
		stored.entity_id_b = id_b
		stored.line_node = line_node
	_edge_by_pair[key] = edge_entity


func _remove_edge_entity(world: Node, id_a: int, id_b: int) -> void:
	var key: String = _edge_key_ids(id_a, id_b)
	var edge_ref: Variant = _edge_by_pair.get(key)
	_edge_by_pair.erase(key)
	_edge_entity_by_pair.erase(_edge_key(id_a, id_b))
	_edge_enabled.erase(_edge_key(id_a, id_b))
	_update_edges_struct_map_for_edge(id_a, id_b, false)
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
			for e in q.with_all([C_Structure, C_PowerNode]).execute():
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
	elif _nodes.has(entity_id):
		# Entity freed (e.g. test purge) - remove edges then clean cache
		var nd: Dictionary = _nodes.get(entity_id, {})
		var world: Node = ECS.world if ECS else null
		for nid in nd.get("neighbor_ids", []):
			_remove_edge_entity(world, entity_id, nid)
		_remove_node_from_cache(entity_id)


## Called by observers via call_deferred - accepts instance_id to avoid Entity type conversion issues.
func _deferred_node_enabled_changed(entity_id: int) -> void:
	var entity: Entity = null
	var from_cache = _entity_by_id.get(entity_id)
	if from_cache != null and is_instance_valid(from_cache):
		entity = from_cache as Entity
	if entity == null and ECS and ECS.world:
		var q = ECS.world.get("query")
		if q:
			for e in q.with_all([C_Structure, C_PowerNode]).execute():
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


## Incremental: add a new power node, compute its connections, create edges, update caches.
func add_node(entity: Entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var world: Node = ECS.world if ECS else null
	if world == null:
		return
	var q = world.get("query")
	if q == null:
		return
	var entities: Array = q.with_all([C_Structure, C_PowerNode]).execute()
	var entity_by_id: Dictionary = {}
	for e in entities:
		entity_by_id[e.get_instance_id()] = e

	_edge_by_pair = _get_edge_by_pair(world)

	var c_power_node: Variant = _get_active_power_node(entity)
	var c_structure: C_Structure = entity.get_component(C_Structure) as C_Structure
	if c_power_node == null or c_structure == null:
		return

	var my_id: int = entity.get_instance_id()
	var new_connections: Array = _compute_connections_for_entity(entity, entities, entity_by_id)

	for id in new_connections:
		if id not in c_power_node.connected_entity_ids:
			c_power_node.connected_entity_ids.append(id)
		var other_entity: Entity = entity_by_id.get(id) as Entity
		if other_entity:
			var other_node: Variant = _get_active_power_node(other_entity)
			if other_node and my_id not in other_node.connected_entity_ids:
				other_node.connected_entity_ids.append(my_id)
		var struct: Node3D = c_structure.structure_node as Node3D
		var other_ent: Entity = entity_by_id.get(id) as Entity
		if other_ent and struct:
			var o_struct: C_Structure = other_ent.get_component(C_Structure) as C_Structure
			if o_struct and o_struct.structure_node:
				_create_edge_entity(world, entity, other_ent, struct, o_struct.structure_node as Node3D)

	_add_node_to_cache(entity)
	for id in new_connections:
		_update_edge_enabled_for_pair(my_id, id)
	_update_edges_struct_map_for_node(my_id)


## Incremental: remove a power node, disconnect edges, update caches.
func remove_node(entity: Entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var world: Node = ECS.world if ECS else null
	var c_power_node: Variant = _get_active_power_node(entity)
	var my_id: int = entity.get_instance_id()
	var neighbor_ids: Array[int] = []
	if c_power_node:
		neighbor_ids = c_power_node.connected_entity_ids.duplicate()

	for other_id in neighbor_ids:
		var other_entity: Entity = _entity_by_id.get(other_id) as Entity
		if other_entity:
			var other_node: Variant = _get_active_power_node(other_entity)
			if other_node:
				other_node.connected_entity_ids.erase(my_id)
		_remove_edge_entity(world, my_id, other_id)

	_remove_node_from_cache(my_id)


## Incremental: node is_enabled changed; update incident edge enabled state.
func node_enabled_changed(entity: Entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var entity_id: int = entity.get_instance_id()
	var nd: Dictionary = _nodes.get(entity_id, {})
	for nid in nd.get("neighbor_ids", []):
		_update_edge_enabled_for_pair(entity_id, nid)
	_update_edges_struct_map_for_node(entity_id)


## Incremental: edge is_blocked changed; update that edge's enabled state.
func edge_blocked_changed(edge_entity: Entity) -> void:
	if edge_entity == null or not is_instance_valid(edge_entity):
		return
	var c_edge: C_PowerEdge = edge_entity.get_component(C_PowerEdge) as C_PowerEdge
	if c_edge == null:
		return
	_update_edge_enabled_for_pair(c_edge.entity_id_a, c_edge.entity_id_b)
	_update_edges_struct_map_for_edge(c_edge.entity_id_a, c_edge.entity_id_b, _edge_enabled.get(_edge_key(c_edge.entity_id_a, c_edge.entity_id_b), false))


## Incremental: entity switched from C_ConstructionPowerNode to C_PowerNode; update caches.
func refresh_entity_cache(entity: Entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var entity_id: int = entity.get_instance_id()
	if not _nodes.has(entity_id):
		return
	_add_node_to_cache(entity)
	for nid in _nodes.get(entity_id, {}).get("neighbor_ids", []):
		_update_edge_enabled_for_pair(entity_id, nid)
	_update_edges_struct_map_for_node(entity_id)


func _add_node_to_cache(entity: Entity) -> void:
	var id: int = entity.get_instance_id()
	var c_node: Variant = _get_active_power_node(entity)
	var c_struct: C_Structure = entity.get_component(C_Structure) as C_Structure
	var c_const: C_Construction = entity.get_component(C_Construction) as C_Construction
	if c_node == null or c_struct == null:
		return

	_entity_by_id[id] = entity
	var struct_node: Node3D = c_struct.structure_node as Node3D
	var struct_id: int = struct_node.get_instance_id() if struct_node and is_instance_valid(struct_node) else 0
	var c_src: C_PowerSource = entity.get_component(C_PowerSource) as C_PowerSource
	var c_gen: C_PowerGenerator = entity.get_component(C_PowerGenerator) as C_PowerGenerator
	var built: bool = c_const == null or c_const.is_built
	var is_src: bool = c_src != null and built
	var has_gen: bool = c_gen != null and built

	_nodes[id] = {
		"neighbor_ids": c_node.connected_entity_ids.duplicate(),
		"is_source": is_src,
		"is_enabled": _is_active_node_enabled(c_node),
		"struct_node": struct_node,
		"struct_id": struct_id,
		"has_user": entity.get_component(C_PowerUser) != null,
		"has_generator": has_gen
	}
	if struct_id != 0:
		_struct_id_to_entity_id[struct_id] = id
	if struct_node and struct_node.get_parent() and struct_node.get_parent().get("building_type") != null:
		var parent_id: int = struct_node.get_parent().get_instance_id()
		_struct_id_to_entity_id[parent_id] = id


func _remove_node_from_cache(entity_id: int) -> void:
	var nd: Dictionary = _nodes.get(entity_id, {})
	for nid in nd.get("neighbor_ids", []):
		_edge_enabled.erase(_edge_key(entity_id, nid))
		_edge_entity_by_pair.erase(_edge_key(entity_id, nid))
	var struct_node_val = nd.get("struct_node")
	var struct_node: Node3D = null
	if struct_node_val != null and is_instance_valid(struct_node_val):
		struct_node = struct_node_val as Node3D
	if struct_node != null:
		var struct_id: int = struct_node.get_instance_id()
		if _struct_id_to_entity_id.get(struct_id) == entity_id:
			_struct_id_to_entity_id.erase(struct_id)
		var parent = struct_node.get_parent()
		if parent != null and is_instance_valid(parent) and parent.get("building_type") != null:
			var parent_id: int = parent.get_instance_id()
			if _struct_id_to_entity_id.get(parent_id) == entity_id:
				_struct_id_to_entity_id.erase(parent_id)
		if _edges_struct_map.has(struct_node):
			_edges_struct_map.erase(struct_node)
		for nid in nd.get("neighbor_ids", []):
			var nnd: Dictionary = _nodes.get(nid, {})
			var struct_b_val = nnd.get("struct_node")
			var struct_b: Node3D = null
			if struct_b_val != null and is_instance_valid(struct_b_val):
				struct_b = struct_b_val as Node3D
			if struct_b != null and _edges_struct_map.has(struct_b):
				_edges_struct_map[struct_b].erase(struct_node)
				if _edges_struct_map[struct_b].is_empty():
					_edges_struct_map.erase(struct_b)
	_nodes.erase(entity_id)
	_entity_by_id.erase(entity_id)


func _update_edge_enabled_for_pair(id_a: int, id_b: int) -> void:
	var k: String = _edge_key(id_a, id_b)
	var node_a: Dictionary = _nodes.get(id_a, {})
	var node_b: Dictionary = _nodes.get(id_b, {})
	var struct_a: Node3D = node_a.get("struct_node") as Node3D
	var struct_b: Node3D = node_b.get("struct_node") as Node3D
	var both_enabled: bool = node_a.get("is_enabled", false) and node_b.get("is_enabled", false)
	var los: bool = true
	if struct_a and struct_b and is_instance_valid(struct_a) and is_instance_valid(struct_b):
		los = PowerConstants.has_line_of_sight(struct_a.global_position, struct_b.global_position, struct_a, struct_b)
	var blocked: bool = false
	var edge_ent = _edge_entity_by_pair.get(k)
	if edge_ent == null:
		edge_ent = _edge_by_pair.get(_edge_key_ids(id_a, id_b))
	if edge_ent != null and is_instance_valid(edge_ent):
		var c_edge: C_PowerEdge = edge_ent.get_component(C_PowerEdge) as C_PowerEdge
		if c_edge:
			blocked = c_edge.is_blocked
		if not _edge_entity_by_pair.has(k):
			_edge_entity_by_pair[k] = edge_ent
	_edge_enabled[k] = not blocked and both_enabled and los


func _update_edges_struct_map_for_edge(id_a: int, id_b: int, enabled: bool) -> void:
	var nd_a: Dictionary = _nodes.get(id_a, {})
	var nd_b: Dictionary = _nodes.get(id_b, {})
	var sa: Variant = nd_a.get("struct_node")
	var sb: Variant = nd_b.get("struct_node")
	if sa == null or sb == null or not is_instance_valid(sa) or not is_instance_valid(sb):
		return
	var struct_a: Node3D = sa as Node3D
	var struct_b: Node3D = sb as Node3D
	if struct_a == null or struct_b == null:
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


func _update_edges_struct_map_for_node(entity_id: int) -> void:
	var nd: Dictionary = _nodes.get(entity_id, {})
	var struct_a: Node3D = nd.get("struct_node") as Node3D
	if struct_a == null or not is_instance_valid(struct_a):
		return
	if not _edges_struct_map.has(struct_a):
		_edges_struct_map[struct_a] = {}
	for nid in nd.get("neighbor_ids", []):
		var k: String = _edge_key(entity_id, nid)
		var enabled: bool = _edge_enabled.get(k, false)
		var nnd: Dictionary = _nodes.get(nid, {})
		var struct_b: Node3D = nnd.get("struct_node") as Node3D
		if struct_b and is_instance_valid(struct_b) and enabled:
			_edges_struct_map[struct_a][struct_b] = {}
			if not _edges_struct_map.has(struct_b):
				_edges_struct_map[struct_b] = {}
			_edges_struct_map[struct_b][struct_a] = {}


## Rebuilds all caches from current entities and edges (internal, used by refresh_graph).
func _rebuild_caches(entities: Array, entity_by_id: Dictionary, edge_by_pair: Dictionary) -> void:
	_nodes.clear()
	_entity_by_id.clear()
	_struct_id_to_entity_id.clear()
	_edge_enabled.clear()
	_edge_entity_by_pair.clear()
	_edges_struct_map.clear()

	for entity in entities:
		var id: int = entity.get_instance_id()
		_entity_by_id[id] = entity

		var c_node: Variant = _get_active_power_node(entity)
		var c_struct: C_Structure = entity.get_component(C_Structure) as C_Structure
		var c_const: C_Construction = entity.get_component(C_Construction) as C_Construction
		if c_node == null or c_struct == null:
			continue

		var struct_node: Node3D = c_struct.structure_node as Node3D
		var struct_id: int = struct_node.get_instance_id() if struct_node and is_instance_valid(struct_node) else 0
		var c_src: C_PowerSource = entity.get_component(C_PowerSource) as C_PowerSource
		var c_gen: C_PowerGenerator = entity.get_component(C_PowerGenerator) as C_PowerGenerator
		var built: bool = c_const == null or c_const.is_built
		var is_src: bool = c_src != null and built
		var has_gen: bool = c_gen != null and built

		_nodes[id] = {
			"neighbor_ids": c_node.connected_entity_ids.duplicate(),
			"is_source": is_src,
			"is_enabled": _is_active_node_enabled(c_node),
			"struct_node": struct_node,
			"struct_id": struct_id,
			"has_user": entity.get_component(C_PowerUser) != null,
			"has_generator": has_gen
		}
		if struct_id != 0:
			_struct_id_to_entity_id[struct_id] = id
		if struct_node and struct_node.get_parent() and struct_node.get_parent().get("building_type") != null:
			var parent_id: int = struct_node.get_parent().get_instance_id()
			_struct_id_to_entity_id[parent_id] = id

	for key in edge_by_pair:
		var edge_ent: Entity = edge_by_pair[key] as Entity
		if edge_ent == null:
			continue
		var c_edge: C_PowerEdge = edge_ent.get_component(C_PowerEdge) as C_PowerEdge
		if c_edge == null:
			continue
		var id_a: int = c_edge.entity_id_a
		var id_b: int = c_edge.entity_id_b
		var k: String = _edge_key(id_a, id_b)
		_edge_entity_by_pair[k] = edge_ent

		var ent_a: Entity = entity_by_id.get(id_a) as Entity
		var ent_b: Entity = entity_by_id.get(id_b) as Entity
		if ent_a == null or ent_b == null:
			_edge_enabled[k] = false
			continue
		var node_a: Dictionary = _nodes.get(id_a, {})
		var node_b: Dictionary = _nodes.get(id_b, {})
		var blocked: bool = c_edge.is_blocked
		var both_enabled: bool = node_a.get("is_enabled", false) and node_b.get("is_enabled", false)
		var struct_a: Node3D = node_a.get("struct_node") as Node3D
		var struct_b: Node3D = node_b.get("struct_node") as Node3D
		var los: bool = true
		if struct_a and struct_b and is_instance_valid(struct_a) and is_instance_valid(struct_b):
			los = PowerConstants.has_line_of_sight(struct_a.global_position, struct_b.global_position, struct_a, struct_b)
		_edge_enabled[k] = not blocked and both_enabled and los

	# Backfill _edge_enabled for connections with no edge entity: enable if both nodes enabled + LOS
	for id in _nodes:
		var nd: Dictionary = _nodes[id]
		for nid in nd.get("neighbor_ids", []):
			var k: String = _edge_key(id, nid)
			if _edge_enabled.has(k):
				continue  # Already set from edge_by_pair
			var nnd: Dictionary = _nodes.get(nid, {})
			if not nd.get("is_enabled", false) or not nnd.get("is_enabled", false):
				continue
			var struct_a: Node3D = nd.get("struct_node") as Node3D
			var struct_b: Node3D = nnd.get("struct_node") as Node3D
			var los: bool = true
			if struct_a and struct_b and is_instance_valid(struct_a) and is_instance_valid(struct_b):
				los = PowerConstants.has_line_of_sight(struct_a.global_position, struct_b.global_position, struct_a, struct_b)
			_edge_enabled[k] = los

	for id in _nodes:
		var nd: Dictionary = _nodes[id]
		var struct_a: Node3D = nd.get("struct_node") as Node3D
		if struct_a == null or not is_instance_valid(struct_a):
			continue
		if not _edges_struct_map.has(struct_a):
			_edges_struct_map[struct_a] = {}
		for nid in nd.get("neighbor_ids", []):
			var k: String = _edge_key(id, nid)
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
	var nd: Dictionary = _nodes.get(entity_id, {})
	if nd.is_empty() or not nd.get("is_enabled", false):
		return 0.0

	var queue: Array = [entity_id]
	var visited: Dictionary = {entity_id: true}
	var path_map: Dictionary = {}  # node_id -> came_from_id
	var total_drawn: float = 0.0
	var remaining: float = amount
	var sources_drawn_from: Array[int] = []

	while not queue.is_empty() and remaining > 0:
		var cid: int = queue.pop_front()
		var cnd: Dictionary = _nodes.get(cid, {})
		if cnd.is_empty():
			continue

		if cnd.get("is_source", false):
			var ent = _entity_by_id.get(cid)
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
			if not _edge_enabled.get(_edge_key(cid, nid), false):
				continue
			var nnd: Dictionary = _nodes.get(nid, {})
			if not nnd.get("is_enabled", false):
				continue
			visited[nid] = true
			path_map[nid] = cid
			queue.append(nid)

	# Flash edges along path from consumer to each source we drew from
	if total_drawn > 0:
		_flash_edges_along_paths(entity_id, sources_drawn_from, path_map)

	return total_drawn


func _flash_edges_along_paths(start_id: int, source_ids: Array, path_map: Dictionary) -> void:
	var edges_to_flash: Dictionary = {}  # "lo_hi" -> true
	for src_id in source_ids:
		var node_id: int = src_id
		while path_map.has(node_id):
			var prev_id: int = path_map[node_id]
			var k: String = _edge_key(prev_id, node_id)
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
		var edge_ent = _edge_entity_by_pair.get(_edge_key(id_a, id_b))
		if edge_ent != null and is_instance_valid(edge_ent):
			var c_edge: C_PowerEdge = edge_ent.get_component(C_PowerEdge) as C_PowerEdge
			if c_edge:
				c_edge.is_flashing = true


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

	var queue: Array = [entity_id]
	var visited: Dictionary = {entity_id: true}
	var path_map: Dictionary = {}

	while not queue.is_empty():
		var cid: int = queue.pop_front()
		var cnd: Dictionary = _nodes.get(cid, {})
		if cnd.is_empty():
			continue

		if cnd.get("is_source", false):
			if not (exclude_start and cid == entity_id):
				var path: Array = []
				var node_id: int = cid
				while node_id != entity_id:
					var ent = _entity_by_id.get(node_id)
					if ent != null and is_instance_valid(ent):
						path.insert(0, ent as Entity)
					if not path_map.has(node_id):
						break
					node_id = path_map[node_id]
				var start_ent = _entity_by_id.get(entity_id)
				if start_ent != null and is_instance_valid(start_ent):
					path.insert(0, start_ent as Entity)
				var src_ent = _entity_by_id.get(cid)
				var src_entity: Entity = (src_ent as Entity) if (src_ent != null and is_instance_valid(src_ent)) else null
				return {"source_entity": src_entity, "path": path}

		for nid in cnd.get("neighbor_ids", []):
			if visited.get(nid, false):
				continue
			if not _edge_enabled.get(_edge_key(cid, nid), false):
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

	var visited: Dictionary = {}
	var subgraph_ids: Array = []
	_find_connected_ids(entity_id, visited, subgraph_ids)

	var sg: PowerSubgraph = PowerSubgraph.new()
	for nid in subgraph_ids:
		var ent = _entity_by_id.get(nid)
		if ent == null or not is_instance_valid(ent):
			continue
		ent = ent as Entity
		sg.nodes.append(ent)
		var nd: Dictionary = _nodes.get(nid, {})
		if nd.get("is_source", false):
			sg.sources.append(ent)
		if nd.get("has_user", false):
			sg.users.append(ent)
		if nd.get("has_generator", false):
			sg.generators.append(ent)
	return sg


func _find_connected_ids(current_id: int, visited: Dictionary, out: Array) -> void:
	if visited.get(current_id, false):
		return
	visited[current_id] = true
	out.append(current_id)
	var nd: Dictionary = _nodes.get(current_id, {})
	if not nd.get("is_enabled", false):
		return
	for nid in nd.get("neighbor_ids", []):
		if visited.get(nid, false):
			continue
		if not _edge_enabled.get(_edge_key(current_id, nid), false):
			continue
		var nnd: Dictionary = _nodes.get(nid, {})
		if nnd.get("is_enabled", false):
			_find_connected_ids(nid, visited, out)


func get_edges() -> Dictionary:
	return _edges_struct_map.duplicate(true)


func is_edge_enabled(node1: Node3D, node2: Node3D) -> bool:
	var id_a: int = struct_to_entity_id(node1)
	var id_b: int = struct_to_entity_id(node2)
	if id_a <= 0 or id_b <= 0:
		return false
	return _edge_enabled.get(_edge_key(id_a, id_b), false)


func is_edge_enabled_entity_ids(id_a: int, id_b: int) -> bool:
	return _edge_enabled.get(_edge_key(id_a, id_b), false)


func get_edge_entity(id_a: int, id_b: int) -> Variant:
	return _edge_entity_by_pair.get(_edge_key(id_a, id_b))


func struct_to_entity_id(struct: Node3D) -> int:
	if struct == null or not is_instance_valid(struct):
		return 0
	return _struct_id_to_entity_id.get(struct.get_instance_id(), 0)


func get_power_capacity() -> float:
	var total: float = 0.0
	for id in _nodes:
		var nd: Dictionary = _nodes[id]
		if not nd.get("is_source", false):
			continue
		var ent = _entity_by_id.get(id)
		if ent == null or not is_instance_valid(ent):
			continue
		ent = ent as Entity
		var c: C_PowerSource = ent.get_component(C_PowerSource) as C_PowerSource
		if c:
			total += c.max_storage
	return total


func get_power_current() -> float:
	var total: float = 0.0
	for id in _nodes:
		var nd: Dictionary = _nodes[id]
		if not nd.get("is_source", false):
			continue
		var ent = _entity_by_id.get(id)
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
		var c_node: C_PowerNode = ent.get_component(C_PowerNode) as C_PowerNode
		if c_node:
			c_node.is_enabled = enabled
	# Observer will trigger request_refresh; caches rebuilt then


func is_entity_powered(entity: Entity) -> bool:
	# Producers (C_PowerSource/C_PowerGenerator) are always powered
	var c_src = entity.get_component(C_PowerSource)
	var c_gen = entity.get_component(C_PowerGenerator)
	if c_src != null or c_gen != null:
		return true
	var c_power_user: C_PowerUser = entity.get_component(C_PowerUser) as C_PowerUser
	if c_power_user:
		return c_power_user.has_power()
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node == null:
		return true
	if not c_power_node.is_enabled:
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


## Pure logic - reads from entity.
static func can_entity_accept_more_connections(entity: Entity) -> bool:
	var active_node: Variant = _get_active_power_node(entity)
	return _can_accept_more_connections(active_node)


## For placement preview: use built max_connections so under-construction relays show as multi-connection targets.
static func can_entity_accept_more_connections_for_preview(entity: Entity) -> bool:
	var c_power_node: C_PowerNode = entity.get_component(C_PowerNode) as C_PowerNode
	if c_power_node == null:
		return false
	var max_conn: int = _get_preview_max_connections_for_entity(entity)
	return c_power_node.connected_entity_ids.size() < max_conn


static func is_entity_valid_connection_target(entity: Entity) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	var active_node: Variant = _get_active_power_node(entity)
	if active_node == null:
		return false
	var c_construction: C_Construction = entity.get_component(C_Construction) as C_Construction
	var is_under_construction: bool = c_construction != null and not c_construction.is_built
	if is_under_construction:
		return true
	if active_node is C_PowerNode and (active_node as C_PowerNode).node_type == C_PowerNode.NodeType.LEAF:
		return false
	return _can_accept_more_connections(active_node)


static func get_connection_status(c_power_node: C_PowerNode) -> String:
	if c_power_node == null:
		return "0/0"
	return "%d/%d" % [c_power_node.connected_entity_ids.size(), c_power_node.max_connections]
